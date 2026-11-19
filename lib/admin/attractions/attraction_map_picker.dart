import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../attractions/models/attraction.dart';
import '../../park/venue_configuration.dart';
import '../../park/venue_map.dart';
import '../portal/admin_theme.dart';

/// Click-to-place editor using the same map tiles, park bounds and normalized
/// positions as the Visitor Map's GeographicParkMap / venueCoordinate.
///
/// Storage uses Attraction.mapX and mapY (0..1); no latitude/longitude fields
/// are added and no existing attraction records are rewritten.
class AttractionMapPicker extends StatefulWidget {
  const AttractionMapPicker({
    super.key,
    required this.position,
    required this.onChanged,
    this.places = const [],
    this.excludeId,
  });

  final Offset? position;
  final ValueChanged<Offset>? onChanged;
  final List<Attraction> places;
  final String? excludeId;

  @override
  State<AttractionMapPicker> createState() => _AttractionMapPickerState();
}

class _AttractionMapPickerState extends State<AttractionMapPicker> {
  String? _locationError;

  LatLng _toLatLng(Offset normalized) => LatLng(
    VenueConfiguration.north! -
        normalized.dy * (VenueConfiguration.north! - VenueConfiguration.south!),
    VenueConfiguration.west! +
        normalized.dx * (VenueConfiguration.east! - VenueConfiguration.west!),
  );

  void _chooseLocation(LatLng selected) {
    final north = VenueConfiguration.north!;
    final south = VenueConfiguration.south!;
    final east = VenueConfiguration.east!;
    final west = VenueConfiguration.west!;

    if (selected.latitude < south || selected.latitude > north ||
        selected.longitude < west || selected.longitude > east) {
      setState(() => _locationError = 'Choose a location on campus.');
      return;
    }

    final x = (selected.longitude - west) / (east - west);
    final y = (north - selected.latitude) / (north - south);
    setState(() => _locationError = null);
    widget.onChanged?.call(Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    if (!VenueConfiguration.boundsReady ||
        VenueConfiguration.north! < VenueConfiguration.latitude ||
        VenueConfiguration.south! > VenueConfiguration.latitude ||
        VenueConfiguration.east! < VenueConfiguration.longitude ||
        VenueConfiguration.west! > VenueConfiguration.longitude) {
      return const Text(
        'Map unavailable. Try again.',
        style: TextStyle(color: Color(0xFFB42318), fontSize: 13),
      );
    }

    final north = VenueConfiguration.north!;
    final south = VenueConfiguration.south!;
    final east = VenueConfiguration.east!;
    final west = VenueConfiguration.west!;
    final bounds = LatLngBounds(
      LatLng(south, west),
      LatLng(north, east),
    );
    final otherPlaces = widget.places.where(
      (p) => p.id != widget.excludeId &&
          p.mapX >= 0 && p.mapX <= 1 && p.mapY >= 0 && p.mapY <= 1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    options: MapOptions(
                      // Same TAR UMT Penang bounds as Visitor Map.
                      initialCenter: LatLng(
                        VenueConfiguration.latitude,
                        VenueConfiguration.longitude,
                      ),
                      initialZoom: 18,
                      minZoom: 17,
                      maxZoom: 21,
                      cameraConstraint: CameraConstraint.containCenter(bounds: bounds),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.drag |
                            InteractiveFlag.pinchMove |
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.scrollWheelZoom |
                            InteractiveFlag.doubleTapZoom,
                      ),
                      onTap: widget.onChanged == null
                          ? null
                          : (_, point) => _chooseLocation(point),
                    ),
                    children: [
                      // Reuse the Visitor Map's Mapbox / OSM tile provider.
                      const ProviderTileLayer(),
                      IgnorePointer(
                        child: MarkerLayer(
                          markers: [
                            for (final place in otherPlaces)
                              Marker(
                                point: _toLatLng(Offset(place.mapX, place.mapY)),
                                width: 130,
                                height: 64,
                                child: Tooltip(
                                  message: place.name,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.place,
                                          size: 25, color: Color(0xFF536C60)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: .94),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          place.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AdminTheme.ink,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (widget.position != null)
                              Marker(
                                point: _toLatLng(widget.position!),
                                width: 48,
                                height: 52,
                                child: const Icon(
                                  Icons.location_on,
                                  size: 43,
                                  color: AdminTheme.rose,
                                  shadows: [
                                    Shadow(color: Color(0x70000000),
                                        blurRadius: 7, offset: Offset(0, 2)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const ProviderAttribution(),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: const [BoxShadow(
                        color: Color(0x14000000), blurRadius: 8,
                        offset: Offset(0, 2),
                      )],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('TAR UMT PENANG',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.ink)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_locationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _locationError!,
              style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
            ),
          ),

      ],
    );
  }
}
