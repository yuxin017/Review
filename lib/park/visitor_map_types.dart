import 'package:latlong2/latlong.dart';

class VisitorTeammatePin {
  const VisitorTeammatePin({
    required this.id,
    required this.name,
    required this.position,
  });
  final String id;
  final String name;
  final LatLng position;
}
