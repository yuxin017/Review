import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_repository.dart';
import 'visitor_gps.dart';

/// Foreground-only opted-in location sharing. The server keeps each position for
/// two minutes, and this service refreshes it every 30 seconds while active.
class ParkLiveSharing with WidgetsBindingObserver {
  ParkLiveSharing._();
  static final ParkLiveSharing instance = ParkLiveSharing._();

  final ValueNotifier<bool> active = ValueNotifier(false);
  final ValueNotifier<Position?> position = ValueNotifier(null);
  Timer? _refresh;
  StreamSubscription<User?>? _auth;
  String? _sessionId;
  ParkLocationRepository? _repo;
  bool _updating = false;
  int _generation = 0;

  Future<void> start({ParkLocationRepository? repository}) async {
    if (active.value) return;
    final repo = repository ?? FirebaseParkLocationRepository();
    final fix = await VisitorGps.locate();
    if (!VisitorGps.trusted(fix)) {
      throw StateError(VisitorGps.reason(fix) ?? 'Location unavailable.');
    }
    final result = await repo.request('start', {'consent': true});
    final id = result['sessionId'];
    if (id is! String || id.isEmpty) throw StateError('Could not start location sharing.');
    _repo = repo;
    _sessionId = id;
    final generation = ++_generation;
    WidgetsBinding.instance.addObserver(this);
    active.value = true;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) unawaited(stop());
    });
    try {
      await _publish(fix, generation);
    } catch (_) {
      await stop();
      rethrow;
    }
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (generation != _generation || !active.value) return;
      try {
        final fix = await VisitorGps.locate();
        if (!VisitorGps.inside(fix.latitude, fix.longitude)) {
          await stop();
        } else if (VisitorGps.trusted(fix)) {
          await _publish(fix, generation);
        }
      } catch (_) {
        // Do not claim a fresh location. Old records expire server-side.
      }
    });
  }

  Future<void> _publish(Position fix, int generation) async {
    if (_updating || generation != _generation || _sessionId == null) return;
    _updating = true;
    try {
      await _repo!.request('update', {
        'sessionId': _sessionId,
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracy': fix.accuracy,
        'observedAt': fix.timestamp.toUtc().toIso8601String(),
        'source': 'gps',
      });
      if (generation == _generation) position.value = fix;
    } finally {
      _updating = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    _refresh?.cancel();
    _refresh = null;
    await _auth?.cancel();
    _auth = null;
    WidgetsBinding.instance.removeObserver(this);
    final id = _sessionId;
    final repo = _repo;
    _repo = null;
    _sessionId = null;
    active.value = false;
    position.value = null;
    if (id != null && repo != null) {
      try { await repo.request('stop', {'sessionId': id}); } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }
}
