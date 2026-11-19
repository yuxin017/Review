import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'venue_configuration.dart';

/// This uses the park's configured bounding rectangle, not a surveyed polygon.
/// A good GPS fix inside it is an estimate, not proof of entering the building.
class VisitorGps {
  static const maxAccuracyMeters = 80.0;
  static const maxAge = Duration(seconds: 90);

  static bool inside(double latitude, double longitude) =>
      VenueConfiguration.boundsReady &&
      latitude >= VenueConfiguration.south! &&
      latitude <= VenueConfiguration.north! &&
      longitude >= VenueConfiguration.west! &&
      longitude <= VenueConfiguration.east!;

  static bool trusted(Position? p) =>
      p != null &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      p.accuracy <= maxAccuracyMeters &&
      DateTime.now().difference(p.timestamp).abs() <= maxAge &&
      inside(p.latitude, p.longitude);

  static String? reason(Position? p) {
    if (p == null) return 'Enable location to discover what is near you.';
    if (!inside(p.latitude, p.longitude)) {
      return 'You appear to be outside TAR UMT Penang. Nearby and park navigation are available on campus.';
    }
    if (p.accuracy > maxAccuracyMeters) {
      return 'Your location is not precise enough yet. Try again outdoors or near a window.';
    }
    if (DateTime.now().difference(p.timestamp).abs() > maxAge) {
      return 'Your location has expired. Tap Locate again to refresh.';
    }
    return null;
  }

  static Future<Position> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on your device location and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Allow location access to use Nearby and walking directions.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  static double metres(Position p, LatLng target) => Geolocator.distanceBetween(
    p.latitude, p.longitude, target.latitude, target.longitude);
}
