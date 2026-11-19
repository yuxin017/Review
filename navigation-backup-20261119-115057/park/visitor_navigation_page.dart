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

/// Uses actual Mapbox pedestrian paths, when a route exists entirely within
/// the configured park area. No straight line is presented as a walking route.
class VisitorNavigationPage extends StatefulWidget {
  const VisitorNavigationPage({
    super.key,
    required this.destinationName,
    required this.destination,
  });
  final String destinationName;
  final LatLng destination;

  @override
  State<VisitorNavigationPage> createState() => _VisitorNavigationPageState();
}

class _VisitorNavigationPageState extends State<VisitorNavigationPage> {
  final _tts = FlutterTts();
  Position? _here;
  List<LatLng> _path = const [];
  List<String> _steps = const [];
  int _instruction = 0;
  double? _walkingMetres;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final here = await VisitorGps.locate();
      if (!VisitorGps.trusted(here)) {
        throw StateError(VisitorGps.reason(here) ?? 'Position unavailable.');
      }
      if (!VisitorGps.inside(
          widget.destination.latitude, widget.destination.longitude)) {
        throw StateError('This destination is outside the configured campus area.');
      }
      if (!VenueConfiguration.mapboxReady) {
        throw StateError('Walking routes are not configured for this park.');
      }
      final coordinates =
          '${here.longitude},${here.latitude};${widget.destination.longitude},${widget.destination.latitude}';
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/walking/$coordinates',
      ).replace(queryParameters: {
        'access_token': VenueConfiguration.mapboxToken,
        'steps': 'true',
        'overview': 'full',
        'geometries': 'geojson',
      });
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('The walking route service is unavailable. Try again.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty) {
        throw StateError('No mapped pedestrian route was found for this destination.');
      }
      final route = routes.first as Map<String, dynamic>;
      final coordinatesJson = (route['geometry'] as Map)['coordinates'] as List;
      final path = coordinatesJson.map((item) {
        final xy = item as List;
        return LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble());
      }).toList();
      if (path.length < 2 || path.any((p) =>
          !VisitorGps.inside(p.latitude, p.longitude))) {
        throw StateError('No on-campus walking route is currently mapped. Follow campus signs instead.');
      }
      final legs = route['legs'] as List? ?? [];
      final instructions = <String>[];
      if (legs.isNotEmpty) {
        for (final step in (legs.first['steps'] as List? ?? [])) {
          final maneuver = (step as Map)['maneuver'];
          if (maneuver is Map && maneuver['instruction'] is String) {
            instructions.add(maneuver['instruction'] as String);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _here = here;
        _path = path;
        _steps = instructions;
        _walkingMetres = (route['distance'] as num?)?.toDouble();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is StateError ? e.message :
            'Could not load walking directions. Check your connection and try again.';
      });
    }
  }

  Future<void> _speak() async {
    if (_steps.isEmpty) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(.46);
      await _tts.stop();
      await _tts.speak(_steps[_instruction]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice guidance is unavailable on this device.')),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
              Text(widget.destinationName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error ?? (_walkingMetres == null
                  ? 'Looking for a mapped walking path…'
                  : 'Mapped walking route: ${_walkingMetres!.round()} m')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 360,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _here == null
                    ? widget.destination
                    : LatLng(_here!.latitude, _here!.longitude),
                initialZoom: 18,
                minZoom: 14,
                maxZoom: 21,
              ),
              children: [
                const ProviderTileLayer(),
                if (_path.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(points: _path,
                        strokeWidth: 5, color: const Color(0xFFAD7472)),
                  ]),
                MarkerLayer(markers: [
                  Marker(point: widget.destination, width: 48, height: 48,
                    child: const Icon(Icons.flag, color: Color(0xFFAD7472), size: 38)),
                  if (_here != null)
                    Marker(point: LatLng(_here!.latitude, _here!.longitude),
                      width: 42, height: 42,
                      child: const Icon(Icons.my_location, color: Colors.blue, size: 33)),
                ]),
                const ProviderAttribution(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          FilledButton.icon(
            onPressed: () {
              setState(() {_loading = true; _error = null;});
              unawaited(_load());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        if (_steps.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Voice walking guide',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Tap to hear a route instruction. Check your surroundings; campus walkways may change.'),
                const SizedBox(height: 10),
                Text('Step ${_instruction + 1} of ${_steps.length}: ${_steps[_instruction]}'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: _speak,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Speak'),
                  )),
                  IconButton(
                    tooltip: 'Previous step',
                    onPressed: _instruction > 0
                        ? () => setState(() => _instruction--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next step',
                    onPressed: _instruction + 1 < _steps.length
                        ? () => setState(() => _instruction++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
