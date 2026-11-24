import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';

/// Asks the native side whether a Google Maps API key was compiled in.
/// Google Maps is only offered to users when one is present.
class MapAvailability {
  static const _channel = MethodChannel('flock/config');
  static bool? _cached;

  static Future<bool> googleMapsAvailable() async {
    if (_cached != null) return _cached!;
    try {
      _cached = await _channel.invokeMethod<bool>('hasGoogleMapsKey') ?? false;
    } on Object {
      _cached = false;
    }
    return _cached!;
  }
}

/// Turns coordinates into "12 Smith St, Newtown" using the phone's own
/// geocoder (free, no API key). Results are cached.
class AddressLookup {
  static final Geocoding _geocoder = Geocoding();
  static final Map<String, String?> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};

  static String _key(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  static String? cached(double lat, double lon) => _cache[_key(lat, lon)];

  /// Test/screenshot hook: pre-fill an address.
  @visibleForTesting
  static void seed(double lat, double lon, String? label) =>
      _cache[_key(lat, lon)] = label;

  static Future<String?> lookup(double lat, double lon) {
    final k = _key(lat, lon);
    if (_cache.containsKey(k)) return Future.value(_cache[k]);
    return _inFlight[k] ??= _resolve(lat, lon, k);
  }

  static Future<String?> _resolve(double lat, double lon, String k) async {
    String? result;
    try {
      final marks = await _geocoder.placemarkFromCoordinates(lat, lon);
      if (marks.isNotEmpty) result = formatPlacemark(marks.first);
    } on Object {
      result = null;
    }
    _cache[k] = result;
    _inFlight.remove(k);
    return result;
  }

  static String? formatPlacemark(Placemark p) {
    final street = [
      p.subThoroughfare,
      p.thoroughfare,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    final area = [
      p.subLocality,
      p.locality,
    ].firstWhere((s) => s != null && s.trim().isNotEmpty, orElse: () => null);
    final parts = [if (street.isNotEmpty) street, ?area];
    if (parts.isEmpty) {
      final n = p.name?.trim();
      return (n == null || n.isEmpty) ? null : n;
    }
    return parts.join(', ');
  }
}
