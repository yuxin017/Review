import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../photos/photo_widgets.dart';
import 'location_repository.dart';
import 'park_live_sharing.dart';
import 'venue_configuration.dart';
import 'venue_map.dart';
import 'visitor_gps.dart';

class LiveLocationPage extends StatefulWidget {
  const LiveLocationPage({super.key, this.repository});
  final ParkLocationRepository? repository;

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  final sharing = ParkLiveSharing.instance;
  bool _busy = false;
  String? _message;

  Future<void> _toggle() async {
    if (_busy) return;
    if (sharing.active.value) {
      setState(() => _busy = true);
      await sharing.stop();
      if (mounted) setState(() { _busy = false; _message = null; });
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share live location?'),
        content: const Text(
          'Help estimate park crowds using your location. Updates while the app is open, stops when it goes into the background. You can turn it off anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Share Location')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _message = null; });
    try {
      await sharing.start(repository: widget.repository);
    } catch (e) {
      if (mounted) setState(() => _message = e is StateError ? e.message :
          'Could not start sharing. Check GPS permission and connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PhotoFrame(
    title: 'My Live Location',
    selectedIndex: 2,
    helpTitle: 'Your live location',
    helpText: 'Opt-in only. Location sharing stops when the app is in the background. You can stop it whenever you like.',
    body: ValueListenableBuilder<bool>(
      valueListenable: sharing.active,
      builder: (context, isSharing, _) => ValueListenableBuilder(
        valueListenable: sharing.position,
        builder: (context, position, __) => ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Icon(isSharing ? Icons.location_on : Icons.location_off_outlined,
                  color: const Color(0xFFAD7472), size: 30),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TAR UMT Penang',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(isSharing ? 'Sharing while the app is in use' : 'Sharing is off',
                      style: const TextStyle(color: Color(0xFFAD7472))),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 14),
            ClipRRect(borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 320,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: position == null
                      ? const LatLng(VenueConfiguration.latitude, VenueConfiguration.longitude)
                      : LatLng(position.latitude, position.longitude),
                    initialZoom: 17, minZoom: 14, maxZoom: 21),
                  children: [
                    const ProviderTileLayer(),
                    if (position != null && VisitorGps.trusted(position))
                      CircleLayer(circles: [
                        CircleMarker(point: LatLng(position.latitude, position.longitude),
                          radius: position.accuracy, useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: .12),
                          borderColor: Colors.blue.withValues(alpha: .3)),
                      ]),
                    if (position != null && VisitorGps.trusted(position))
                      MarkerLayer(markers: [
                        Marker(point: LatLng(position.latitude, position.longitude),
                          width: 44, height: 44,
                          child: const Icon(Icons.my_location,
                            size: 34, color: Colors.blue)),
                      ]),
                    const ProviderAttribution(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (position != null && VisitorGps.trusted(position))
              Text('GPS accuracy: ±${position.accuracy.round()} m',
                style: const TextStyle(fontSize: 12)),
            if (_message != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!,
                  style: const TextStyle(color: Color(0xFFB34747)))),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: Icon(isSharing ? Icons.stop_circle_outlined : Icons.my_location),
              label: Padding(padding: const EdgeInsets.all(10),
                child: Text(_busy ? 'Updating…' :
                  isSharing ? 'Stop Sharing' : 'Share My Location')),
            ),
            const SizedBox(height: 10),
            if (isSharing)
              const Text('You can return to the park map. Sharing will keep updating while the app stays in the foreground.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF7B6B69))),
          ],
        ),
      ),
    ),
  );
}
