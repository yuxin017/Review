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

typedef RouteStart = ({String name, LatLng point});

class VisitorNavigationPage extends StatefulWidget {
  const VisitorNavigationPage({
    super.key,
    required this.destinationName,
    required this.destination,
    this.initialPosition,
    this.initialStart,
    this.chooseStart,
  });

  final String destinationName;
  final LatLng destination;
  final Position? initialPosition;
  final RouteStart? initialStart;
  final Future<RouteStart?> Function()? chooseStart;

  @override
  State<VisitorNavigationPage> createState() => _VisitorNavigationPageState();
}

class _VisitorNavigationPageState extends State<VisitorNavigationPage> {
  static const _navigationAccuracy = 15.0;
  static const _radiansPerDegree = 0.017453292519943295;

  final _tts = FlutterTts();
  final _mapController = MapController();

  Position? _here;
  RouteStart? _landmark;
  Position? _liveFix;
  StreamSubscription<Position>? _liveLocation;
  Timer? _liveExpiry;

  List<LatLng> _path = const [];
  List<String> _steps = const [];
  List<LatLng?> _maneuvers = const [];
  List<double?> _bearings = const [];
  int _offRouteFixes = 0;
  DateTime? _lastReroute;
  int _instruction = 0;
  int _liveInstruction = 0;
  bool _arrived = false;
  bool _mapReady = false;
  bool _following = true;
  bool _trackingStarting = false;
  String? _trackingNotice;
  double? _walkingMetres;
  bool _approximateStart = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _landmark = widget.initialStart;
    unawaited(
      _load(initialPosition: widget.initialPosition, landmark: _landmark),
    );
  }

  bool _usable(Position position) =>
      position.accuracy.isFinite &&
      position.accuracy >= 0 &&
      DateTime.now().difference(position.timestamp).abs() <=
          VisitorGps.maxAge &&
      VisitorGps.inside(position.latitude, position.longitude);

  Future<void> _load({Position? initialPosition, RouteStart? landmark}) async {
    try {
      Position? here;
      if (landmark == null) {
        here = initialPosition != null && _usable(initialPosition)
            ? initialPosition
            : await VisitorGps.locate();
        if (!_usable(here)) {
          throw StateError(VisitorGps.reason(here) ?? 'Position unavailable.');
        }
      }
      final start = landmark?.point ?? LatLng(here!.latitude, here.longitude);
      if (!VisitorGps.inside(start.latitude, start.longitude)) {
        throw StateError('Choose a starting point inside the campus area.');
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
          '${start.longitude},${start.latitude};'
          '${widget.destination.longitude},${widget.destination.latitude}';
      final url =
          Uri.parse(
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
        throw StateError(
          'The walking route service is unavailable. Try again.',
        );
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
      final maneuvers = <LatLng?>[];
      final bearings = <double?>[];

      for (final leg in legs) {
        for (final step in (leg['steps'] as List? ?? [])) {
          final maneuver = (step as Map)['maneuver'];
          if (maneuver is! Map || maneuver['instruction'] is! String) continue;

          instructions.add(maneuver['instruction'] as String);
          final location = maneuver['location'];
          final bearing = maneuver['bearing_after'];
          maneuvers.add(
            location is List &&
                    location.length >= 2 &&
                    location[0] is num &&
                    location[1] is num
                ? LatLng(
                    (location[1] as num).toDouble(),
                    (location[0] as num).toDouble(),
                  )
                : null,
          );
          bearings.add(
            maneuver['type'] != 'arrive' && bearing is num
                ? bearing.toDouble()
                : null,
          );
        }
      }

      if (!mounted) return;
      if (here != null && !_usable(here)) {
        throw StateError(
          'Your location has expired. Refresh GPS to try again.',
        );
      }

      final approximate = here != null && !_canGuide(here);
      setState(() {
        _here = here;
        _path = path;
        _steps = instructions;
        _maneuvers = maneuvers;
        _bearings = bearings;
        _offRouteFixes = 0;
        _instruction = 0;
        _liveInstruction = 0;
        _arrived = false;
        _approximateStart = approximate;
        _walkingMetres = (route['distance'] as num?)?.toDouble();
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady && identical(_path, path)) _fitRoute();
      });
      // A landmark start is also navigable: always request a live GPS stream.
      unawaited(_startTracking());
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

  /// The map follows any fresh on-campus fix with acceptable display accuracy.
  /// Turn-by-turn instructions and off-route detection keep the tighter 15m
  /// accuracy threshold to avoid false reroutes between campus buildings.
  Future<void> _startTracking() async {
    if (_trackingStarting || _liveLocation != null || !mounted) return;
    _trackingStarting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _trackingNotice =
            'Turn on device location to follow your movement.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _trackingNotice =
            'Allow location access to enable live map following.');
        return;
      }
      if (!mounted || _liveLocation != null) return;
      setState(() => _trackingNotice = null);
      _liveLocation = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen(
        (fix) {
          if (!mounted) return;
          _liveExpiry?.cancel();
          if (!_usable(fix)) {
            _clearLiveFix();
            return;
          }
          final guiding = _canGuide(fix) && !_loading && _path.isNotEmpty;
          setState(() {
            _liveFix = fix;
            _trackingNotice = null;
            if (guiding && !_arrived) {
              if (_liveInstruction + 1 < _maneuvers.length) {
                final next = _maneuvers[_liveInstruction + 1];
                if (next != null && VisitorGps.metres(fix, next) <= 15) {
                  _liveInstruction++;
                }
              }
              _instruction = _liveInstruction;
              _arrived = _liveInstruction + 1 >= _maneuvers.length &&
                  VisitorGps.metres(fix, _path.last) <= 12;
            }
          });
          // Follow independently of the precision required for spoken steps.
          if (!_loading && _path.isNotEmpty && VisitorGps.trusted(fix)) {
            _follow(fix);
          }
          if (guiding && !_arrived) {
            _checkForReroute(fix);
          } else {
            _offRouteFixes = 0;
          }
          final remaining = VisitorGps.maxAge -
              DateTime.now().difference(fix.timestamp).abs();
          if (remaining > Duration.zero) {
            _liveExpiry = Timer(remaining, _clearLiveFix);
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _trackingNotice =
              'Live location stopped. Check GPS and tap Retry Tracking.');
          _liveLocation = null;
          _clearLiveFix();
        },
        onDone: () {
          _liveLocation = null;
          _clearLiveFix();
        },
      );
    } catch (_) {
      if (mounted) setState(() => _trackingNotice =
          'Could not start live location. Check GPS permission and try again.');
    } finally {
      _trackingStarting = false;
    }
  }

  bool _canGuide(Position? fix) =>
      fix != null &&
      VisitorGps.trusted(fix) &&
      fix.accuracy <= _navigationAccuracy;

  void _fitRoute() {
    if (_path.isEmpty) return;
    final fix = _liveFix ?? _here;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          ..._path,
          widget.destination,
          if (_landmark case final landmark?) landmark.point,
          if (fix != null) LatLng(fix.latitude, fix.longitude),
        ]),
        padding: const EdgeInsets.all(32),
        maxZoom: 19,
      ),
    );
  }

  void _follow(Position fix) {
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_mapReady ||
          _loading ||
          _path.isEmpty ||
          _liveFix != fix)
        return;
      _mapController.move(LatLng(fix.latitude, fix.longitude), 18.5);
    });
  }

  void _checkForReroute(Position fix) {
    // Project onto each mapped segment so long straight sections count too.
    final nearRoute = _path.asMap().entries.skip(1).any((entry) {
      final start = _path[entry.key - 1];
      final end = entry.value;
      final dx = end.longitude - start.longitude;
      final dy = end.latitude - start.latitude;
      final lengthSquared = dx * dx + dy * dy;
      final fraction = lengthSquared == 0
          ? 0.0
          : (((fix.longitude - start.longitude) * dx +
                        (fix.latitude - start.latitude) * dy) /
                    lengthSquared)
                .clamp(0.0, 1.0);
      return VisitorGps.metres(
            fix,
            LatLng(
              start.latitude + fraction * dy,
              start.longitude + fraction * dx,
            ),
          ) <=
          35;
    });

    _offRouteFixes = nearRoute ? 0 : _offRouteFixes + 1;
    final now = DateTime.now();
    final lastReroute = _lastReroute;
    if (_offRouteFixes < 3 ||
        (lastReroute != null &&
            now.difference(lastReroute) < const Duration(seconds: 30))) {
      return;
    }
    _lastReroute = now;
    _offRouteFixes = 0;
    setState(() {
      _loading = true;
      _landmark = null;
      _error = null;
    });
    unawaited(_load(initialPosition: fix));
  }

  void _clearLiveFix() {
    _liveExpiry?.cancel();
    if (mounted && _liveFix != null) {
      setState(() => _liveFix = null);
    }
  }

  Future<void> _pickStart() async {
    final start = await widget.chooseStart?.call();
    if (!mounted || start == null) return;
    _refresh(landmark: start);
  }

  void _refresh({RouteStart? landmark}) {
    if (_loading) return;
    setState(() {
      _loading = true;
      _landmark = landmark;
      _error = null;
      _here = null;
      _path = const [];
      _steps = const [];
      _walkingMetres = null;
      _approximateStart = false;
    });
    unawaited(_load(landmark: landmark));
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
    _mapController.dispose();
    super.dispose();
  }

  Widget _direction() {
    final step = _steps[_instruction];
    final words = step.toLowerCase();
    final arrow = switch (words) {
      _ when words.contains('u-turn') => Icons.u_turn_left,
      _ when words.contains('left') => Icons.turn_left,
      _ when words.contains('right') => Icons.turn_right,
      _ when words.contains('northeast') => Icons.north_east,
      _ when words.contains('northwest') => Icons.north_west,
      _ when words.contains('southeast') => Icons.south_east,
      _ when words.contains('southwest') => Icons.south_west,
      _ when words.contains('south') => Icons.south,
      _ when words.contains('east') => Icons.east,
      _ when words.contains('west') => Icons.west,
      _ when words.contains('arrive') => Icons.flag_outlined,
      _ => Icons.north,
    };
    return Row(children: [
      Icon(arrow, size: 36, color: const Color(0xFF973E4B)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Step ${_instruction + 1} of ${_steps.length}'),
        Text(step, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final here = _here;
    final liveFix = _liveFix;
    final markerFix = liveFix ?? here;
    final heading = liveFix?.heading ?? -1;
    final guiding = _canGuide(liveFix) && _path.isNotEmpty;
    final showHeading =
        guiding &&
        (liveFix?.speed ?? 0) > .5 &&
        heading.isFinite &&
        heading >= 0 &&
        heading < 360;
    final routeBearing = _steps.isEmpty ? null : _bearings[_instruction];
    final arrowBearing = showHeading ? heading : (routeBearing ?? 0);
    final gpsPoint = markerFix == null
        ? null
        : LatLng(markerFix.latitude, markerFix.longitude);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF4EF),
      appBar: AppBar(title: Text('To ${widget.destinationName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const LinearProgressIndicator()
          else
            const SizedBox.shrink(),
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
                if (_landmark case final landmark?)
                  Text('Starting point: ${landmark.name}'),
                if (_approximateStart && here != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Route preview • Start accuracy ±${here.accuracy.round()} m. '
                    'Check the starting point before following the steps.',
                    style: const TextStyle(color: Color(0xFF9B602D)),
                  ),
                ],
                if (guiding && _steps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _direction(),
                ],
                if (!guiding && _path.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The dots mark the ends of the mapped walking path. '
                    'The blue arrow marks your estimated position. '
                    'The flag marks the destination.',
                  ),
                ],
                if (liveFix != null)
                  Text(
                    _arrived
                        ? 'Arrived at the end of the mapped route'
                        : guiding
                        ? 'Live navigation • accuracy ±${liveFix.accuracy.round()} m'
                        : 'Live GPS • ±${liveFix.accuracy.round()} m • route preview',
                  )
                else if (here != null)
                  const Text(
                    'Showing route start • waiting for a live GPS fix',
                  ),
                if (_trackingNotice != null) ...[
             const SizedBox(height: 8),
             Text(_trackingNotice!, style: const TextStyle(color: Color(0xFF9B602D))),
             TextButton.icon(
               onPressed: () => unawaited(_startTracking()),
               icon: const Icon(Icons.gps_fixed),
               label: const Text('Retry Tracking'),
             ),
           ],
           if (!_loading) ...[
             const SizedBox(height: 8),
             OutlinedButton.icon(
               onPressed: () {
                 setState(() => _following = !_following);
                 if (_following && _liveFix != null &&
                     VisitorGps.trusted(_liveFix)) {
                   _follow(_liveFix!);
                 }
               },
               icon: Icon(_following ? Icons.gps_fixed : Icons.gps_off),
               label: Text(_following ? 'Following My Location' : 'Resume Follow Me'),
             ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _landmark == null ? 'Refresh GPS' : 'Use GPS Start',
                    ),
                  ),
                  if (widget.chooseStart != null)
                    OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.place_outlined),
                      label: const Text('Choose Starting Point'),
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
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      _landmark?.point ?? gpsPoint ?? widget.destination,
                  initialZoom: 18,
                  keepAlive: true,
                  onMapReady: () {
                    _mapReady = true;
                    _fitRoute();
                  },
                  minZoom: 10,
                  maxZoom: 21,
                ),
                children: [
                  const ProviderTileLayer(),
                  if (markerFix != null &&
                      gpsPoint != null &&
                      markerFix.accuracy > _navigationAccuracy)
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
                            angle: arrowBearing * _radiansPerDegree,
                            child: const Icon(
                              Icons.navigation,
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
                  Text(
                    guiding
                        ? 'Steps update as you walk. Tap Speak to hear the current step.'
                        : 'Use the arrows to change steps, or tap Speak '
                              'to hear the selected step.',
                  ),
                  const SizedBox(height: 10),
                  if (!guiding) _direction(),
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
                      if (!guiding)
                        IconButton(
                          tooltip: 'Previous step',
                          onPressed: _instruction > 0
                              ? () => setState(() => _instruction--)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                      if (!guiding)
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
