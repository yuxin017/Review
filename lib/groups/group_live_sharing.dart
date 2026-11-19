import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../park/visitor_gps.dart';
import 'group_repository.dart';

/// Explicit opt-in. Runs only while the app stays in the foreground.
/// Keeps a teammate's short-lived location current across visitor tabs.
class GroupLiveSharing with WidgetsBindingObserver {
  GroupLiveSharing._();
  static final GroupLiveSharing instance = GroupLiveSharing._();
  final ValueNotifier<String?> activeGroupId = ValueNotifier(null);

  GroupRepository? _repository;
  StreamSubscription<Position>? _positions;
  StreamSubscription<User?>? _auth;
  Timer? _heartbeat;
  bool _publishing = false;
  int _generation = 0;

  Future<void> start(String groupId, GroupRepository repository) async {
    await stop();
    final position = await VisitorGps.locate();
    if (!VisitorGps.trusted(position)) {
      throw StateError(VisitorGps.reason(position) ?? 'Position unavailable.');
    }
    await repository.request('location', {
      'groupId': groupId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
    });
    _repository = repository;
    activeGroupId.value = groupId;
    final generation = ++_generation;
    WidgetsBinding.instance.addObserver(this);
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) unawaited(stop());
    });
    _positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) => unawaited(_send(position, generation)),
        onError: (Object _) {});
    // Movement can be zero: refresh the 2-minute location TTL regardless.
    _heartbeat = Timer.periodic(const Duration(seconds: 35), (_) async {
      if (generation != _generation) return;
      try {
        final position = await VisitorGps.locate();
        await _send(position, generation);
      } catch (_) {
        // Keep the last sample short-lived. Never substitute an old fix.
      }
    });
  }

  Future<void> _send(Position position, int generation) async {
    if (_publishing || generation != _generation) return;
    if (!VisitorGps.trusted(position)) {
      // We cannot claim on-campus sharing from an unreliable or out-of-park fix.
      if (!VisitorGps.inside(position.latitude, position.longitude)) {
        await stop();
      }
      return;
    }
    final id = activeGroupId.value;
    final repo = _repository;
    if (id == null || repo == null) return;
    _publishing = true;
    try {
      await repo.request('location', {
        'groupId': id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      });
    } catch (_) {
      // No fake position. The server-side record will expire in two minutes.
    } finally {
      _publishing = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _positions?.cancel();
    _positions = null;
    await _auth?.cancel();
    _auth = null;
    WidgetsBinding.instance.removeObserver(this);
    final id = activeGroupId.value;
    final repo = _repository;
    activeGroupId.value = null;
    _repository = null;
    if (id != null && repo != null) {
      try {
        await repo.request('location', {'groupId': id, 'sharing': false});
      } catch (_) {
        // The server TTL ensures any retained location quickly disappears.
      }
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
