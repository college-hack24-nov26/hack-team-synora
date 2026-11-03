import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// A single live location reading. All fields are nullable/empty when a fix
/// could not be obtained (permission denied, no GPS, timeout) so callers can
/// still send an alert without location rather than blocking on it.
class LocationFix {
  final double? latitude;
  final double? longitude;
  final String label; // reverse-geocoded human-readable area, or "lat, lng"
  final String mapsUrl;

  const LocationFix({
    this.latitude,
    this.longitude,
    this.label = '',
    this.mapsUrl = '',
  });

  bool get hasFix => latitude != null && longitude != null;

  static const empty = LocationFix();

  /// Fields ready to merge into any alert/notification JSON body.
  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'locationLabel': label,
        'mapsUrl': mapsUrl,
      };
}

/// One reusable place to get the patient's live location for alerts. Extracted
/// from the vitals screen's `_fetchLocation` so every alert path (disease,
/// vitals, mental-health, consult) attaches location the same way.
class LocationService {
  /// Best-effort current location. Never throws; returns [LocationFix.empty]
  /// when unavailable so an alert is never blocked by a missing fix.
  static Future<LocationFix> getFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationFix.empty;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationFix.empty;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return LocationFix.empty;

      final lat = pos.latitude;
      final lng = pos.longitude;
      String label = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      try {
        final placemarks = await placemarkFromCoordinates(lat, lng)
            .timeout(const Duration(seconds: 3), onTimeout: () => []);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if (p.subLocality?.isNotEmpty == true) p.subLocality!,
            if (p.locality?.isNotEmpty == true) p.locality!,
            if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
          ];
          if (parts.isNotEmpty) label = parts.join(', ');
        }
      } catch (_) {}

      return LocationFix(
        latitude: lat,
        longitude: lng,
        label: label,
        mapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
      );
    } catch (_) {
      return LocationFix.empty;
    }
  }
}
