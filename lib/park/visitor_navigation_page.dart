import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'venue_configuration.dart';
import 'venue_map.dart';
import 'visitor_gps.dart';

class VisitorNavigationPage extends StatefulWidget {
  const VisitorNavigationPage({
    super.key,
    required this.destinationName,
    required this.destination,
    this.initialPosition,
  });

  final String destinationName;
  final LatLng destination;
  final Position? initialPosition;

  @override
  State<VisitorNavigationPage> createState() => _VisitorNavigationPageState();
}

class _VisitorNavigationPageState extends State<VisitorNavigationPage> {
  final _tts = FlutterTts();

  Position? _here;
  Position? _liveFix;
  StreamSubscription<Position>? _liveLocation;
  Timer? _liveExpiry;

  List<LatLng> _path = const [];
  List<String> _steps = const [];
  List<Marker?> _stepArrows = const [];
  int _instruction = 0;
  double? _walkingMetres;
  bool _approximateStart = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(initialPosition: widget.initialPosition));
  }

  bool _usable(Position position) =>
      position.accuracy.isFinite &&
          position.accuracy >= 0 &&
          DateTime.now().difference(position.timestamp).abs() <=
              VisitorGps.maxAge &&
          VisitorGps.inside(position.latitude, position.longitude);

  Future<void> _load({Position? initialPosition}) async {
    try {
      final here = initialPosition != null && _usable(initialPosition)
          ? initialPosition
          : await VisitorGps.locate();

      if (!_usable(here)) {
        throw StateError(VisitorGps.reason(here) ?? 'Position unavailable.');
      }
      if (!VisitorGps.inside(
        widget.destination.latitude,
        widget.destination.longitude,
      )) {
        throw StateError(
          'This destination is outside the configured campus area.',
        );
      }
      if (!VenueConfiguration.mapboxReady) {
        throw StateError('Walking routes are not configured for this park.');
      }

      final coordinates =
          '${here.longitude},${here.latitude};'
          '${widget.destination.longitude},${widget.destination.latitude}';
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/walking/$coordinates',
      ).replace(
        queryParameters: {
          'access_token': VenueConfiguration.mapboxToken,
          'steps': 'true',
          'overview': 'full',
          'geometries': 'geojson',
        },
      );

      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('The walking route service is unavailable. Try again.');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty) {
        throw StateError(
          'No mapped pedestrian route was found for this destination.',
        );
      }

      final route = routes.first as Map<String, dynamic>;
      final coordinatesJson = (route['geometry'] as Map)['coordinates'] as List;
      final path = coordinatesJson.map((item) {
        final xy = item as List;
        return LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble());
      }).toList();

      if (path.length < 2 ||
          path.any((p) => !VisitorGps.inside(p.latitude, p.longitude))) {
        throw StateError(
          'No on-campus walking route is currently mapped. '
              'Follow campus signs instead.',
        );
      }

      final legs = route['legs'] as List? ?? [];
      final instructions = <String>[];
      final stepArrows = <Marker?>[];

      if (legs.isNotEmpty) {
        for (final step in (legs.first['steps'] as List? ?? [])) {
          final maneuver = (step as Map)['maneuver'];
          if (maneuver is Map && maneuver['instruction'] is String) {
            instructions.add(maneuver['instruction'] as String);
            final location = maneuver['location'];
            final bearing = maneuver['bearing_after'];

            stepArrows.add(
              maneuver['type'] != 'arrive' &&
                  location is List &&
                  location.length >= 2 &&
                  location[0] is num &&
                  location[1] is num &&
                  bearing is num
                  ? Marker(
                point: LatLng(
                  (location[1] as num).toDouble(),
                  (location[0] as num).toDouble(),
                ),
                width: 36,
                height: 36,
                child: Transform.rotate(
                  angle: bearing.toDouble() * 0.017453292519943295,
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.indigo,
                    size: 32,
                  ),
                ),
              )
                  : null,
            );
          }
        }
      }

      if (!mounted) return;
      if (!_usable(here)) {
        throw StateError('Your location has expired. Refresh GPS to try again.');
      }

      final approximate = !VisitorGps.trusted(here);
      setState(() {
        _here = here;
        _path = path;
        _steps = instructions;
        _stepArrows = stepArrows;
        _instruction = 0;
        _approximateStart = approximate;
        _walkingMetres = (route['distance'] as num?)?.toDouble();
        _loading = false;
        _error = null;
      });
      _trackPosition();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is StateError
            ? e.message
            : 'Could not load walking directions. Check your connection and try again.';
      });
    }
  }

  void _trackPosition() {
    _liveLocation ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).listen(
          (fix) {
        if (!mounted) return;
        _liveExpiry?.cancel();
        if (!_usable(fix)) {
          _clearLiveFix();
          return;
        }

        setState(() => _liveFix = fix);
        _liveExpiry = Timer(
          VisitorGps.maxAge - DateTime.now().difference(fix.timestamp).abs(),
          _clearLiveFix,
        );
      },
      onError: (Object error) => _clearLiveFix(),
      onDone: () {
        _liveLocation = null;
        _clearLiveFix();
      },
    );
  }

  void _clearLiveFix() {
    _liveExpiry?.cancel();
    if (mounted && _liveFix != null) {
      setState(() => _liveFix = null);
    }
  }

  void _refresh() {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _here = null;
      _path = const [];
      _steps = const [];
      _walkingMetres = null;
      _approximateStart = false;
    });
    unawaited(_load());
  }

  Future<void> _speak() async {
    if (_steps.isEmpty) return;
    final instruction = _steps[_instruction];

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(.46);
      await _tts.stop();
      if (mounted && !_loading) {
        await _tts.speak(instruction);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice guidance is unavailable on this device.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _liveExpiry?.cancel();
    unawaited(_liveLocation?.cancel());
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final here = _here;
    final liveFix = _liveFix;
    final markerFix = liveFix ?? here;
    final heading = liveFix?.heading ?? -1;
    final showHeading =
        VisitorGps.trusted(liveFix) &&
            (liveFix?.speed ?? 0) > .5 &&
            heading.isFinite &&
            heading >= 0 &&
            heading < 360;
    final gpsPoint = markerFix == null
        ? null
        : LatLng(markerFix.latitude, markerFix.longitude);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF4EF),
      appBar: AppBar(title: Text('To ${widget.destinationName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.destinationName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ??
                      (_walkingMetres == null
                          ? 'Looking for a mapped walking path…'
                          : 'Mapped walking route: ${_walkingMetres!.round()} m'),
                ),
                if (_approximateStart && here != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Route preview • Start accuracy ±${here.accuracy.round()} m. '
                        'Check the starting point before following the steps.',
                    style: const TextStyle(color: Color(0xFF9B602D)),
                  ),
                ],
                if (_path.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The dots mark the ends of the mapped walking path. '
                        'The purple arrow shows the selected route step, '
                        'and the flag marks the destination.',
                  ),
                ],
                if (liveFix != null)
                  Text('Live GPS • accuracy ±${liveFix.accuracy.round()} m')
                else if (here != null)
                  const Text('Showing route start • waiting for a live GPS fix'),
                if (!_loading) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh GPS'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 360,
              child: FlutterMap(
                key: ValueKey(_path),
                options: MapOptions(
                  initialCenter: gpsPoint ?? widget.destination,
                  initialZoom: 18,
                  initialCameraFit: _path.isEmpty
                      ? null
                      : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      ..._path,
                      widget.destination,
                      if (gpsPoint != null) gpsPoint,
                    ]),
                    padding: const EdgeInsets.all(32),
                    maxZoom: 19,
                  ),
                  minZoom: 10,
                  maxZoom: 21,
                ),
                children: [
                  const ProviderTileLayer(),
                  if (markerFix != null &&
                      gpsPoint != null &&
                      markerFix.accuracy > VisitorGps.maxAccuracyMeters)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: gpsPoint,
                          radius: markerFix.accuracy,
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: .10),
                          borderColor: Colors.blue.withValues(alpha: .45),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),
                  if (_path.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _path,
                          strokeWidth: 5,
                          color: const Color(0xFFAD7472),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: widget.destination,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.flag,
                          color: Color(0xFFAD7472),
                          size: 38,
                        ),
                      ),
                      if (gpsPoint != null)
                        Marker(
                          point: gpsPoint,
                          width: 42,
                          height: 42,
                          child: Transform.rotate(
                            angle: showHeading
                                ? heading * 0.017453292519943295
                                : 0,
                            child: Icon(
                              showHeading
                                  ? Icons.navigation
                                  : Icons.my_location,
                              color: Colors.blue,
                              size: 33,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_path.isNotEmpty)
                    CircleLayer(
                      circles: [
                        for (final endpoint in [_path.first, _path.last])
                          CircleMarker(
                            point: endpoint,
                            radius: 5,
                            color: const Color(0xFFAD7472),
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                          ),
                      ],
                    ),
                  if (_steps.isNotEmpty && _stepArrows[_instruction] != null)
                    MarkerLayer(markers: [_stepArrows[_instruction]!]),
                  const ProviderAttribution(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_steps.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Mapped route steps',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Use the arrows to change steps, or tap Speak '
                        'to hear the selected step.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Step ${_instruction + 1} of ${_steps.length}: '
                        '${_steps[_instruction]}',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _speak,
                          icon: const Icon(Icons.volume_up),
                          label: const Text('Speak'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous step',
                        onPressed: _instruction > 0
                            ? () => setState(() => _instruction--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next step',
                        onPressed: _instruction + 1 < _steps.length
                            ? () => setState(() => _instruction++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}