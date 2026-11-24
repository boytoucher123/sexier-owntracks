import 'dart:convert';
import 'dart:typed_data';

import '../models/person.dart';

/// Encoding and decoding of the OwnTracks JSON message format.
/// Reference: https://owntracks.org/booklet/tech/json/
///
/// Kept free of Flutter and MQTT so it can be unit tested on its own.
class OwnTracksProtocol {
  OwnTracksProtocol._();

  /// Splits `owntracks/crew/Fred/info` into its parts. Returns null for
  /// topics that aren't OwnTracks device topics under [baseTopic].
  static TopicParts? parseTopic(
    String topic, {
    String baseTopic = 'owntracks',
  }) {
    final baseParts = baseTopic.split('/');
    final parts = topic.split('/');
    if (parts.length < baseParts.length + 2) return null;
    for (var i = 0; i < baseParts.length; i++) {
      if (parts[i] != baseParts[i]) return null;
    }
    final user = parts[baseParts.length];
    final device = parts[baseParts.length + 1];
    final rest = parts.sublist(baseParts.length + 2);
    final deviceTopic = parts.sublist(0, baseParts.length + 2).join('/');
    return TopicParts(
      deviceTopic: deviceTopic,
      user: user,
      device: device,
      subtopic: rest.isEmpty ? null : rest.join('/'),
    );
  }

  /// Decodes a payload into a map, or null if it isn't a JSON object.
  /// An empty payload (a cleared retained message) also returns null.
  static Map<String, dynamic>? decode(String payload) {
    if (payload.trim().isEmpty) return null;
    try {
      final v = jsonDecode(payload);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  static LocationFix? parseLocation(Map<String, dynamic> j) {
    if (j['_type'] != 'location') return null;
    final lat = _toDouble(j['lat']);
    final lon = _toDouble(j['lon']);
    final tst = _toInt(j['tst']);
    if (lat == null || lon == null || tst == null) return null;
    final bs = _toInt(j['bs']);
    return LocationFix(
      lat: lat,
      lon: lon,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        tst * 1000,
        isUtc: true,
      ).toLocal(),
      accuracy: _toDouble(j['acc']),
      altitude: _toDouble(j['alt']),
      velocityKmh: _toDouble(j['vel']),
      course: _toDouble(j['cog']),
      battery: _toInt(j['batt']),
      // bs: 0 unknown, 1 unplugged, 2 charging, 3 full
      charging: bs == null || bs == 0 ? null : (bs == 2 || bs == 3),
      trackerId: j['tid'] is String ? j['tid'] as String : null,
      connection: j['conn'] is String ? j['conn'] as String : null,
    );
  }

  static CardInfo? parseCard(Map<String, dynamic> j) {
    if (j['_type'] != 'card') return null;
    Uint8List? face;
    final f = j['face'];
    if (f is String && f.isNotEmpty) {
      try {
        face = base64Decode(f);
      } on FormatException {
        face = null;
      }
    }
    return CardInfo(
      name: j['name'] is String ? j['name'] as String : null,
      face: face,
      trackerId: j['tid'] is String ? j['tid'] as String : null,
    );
  }

  static String encodeLocation({
    required double lat,
    required double lon,
    required DateTime timestamp,
    required String trackerId,
    double? accuracy,
    double? altitude,
    double? speedMetersPerSecond,
    double? heading,
    int? battery,
    bool? charging,
    String trigger = 'p',
  }) {
    final m = <String, dynamic>{
      '_type': 'location',
      'lat': _round(lat, 6),
      'lon': _round(lon, 6),
      'tst': timestamp.toUtc().millisecondsSinceEpoch ~/ 1000,
      'tid': trackerId,
      't': trigger,
    };
    if (accuracy != null && accuracy.isFinite) m['acc'] = accuracy.round();
    if (altitude != null && altitude.isFinite) m['alt'] = altitude.round();
    if (speedMetersPerSecond != null &&
        speedMetersPerSecond.isFinite &&
        speedMetersPerSecond >= 0) {
      m['vel'] = (speedMetersPerSecond * 3.6).round();
    }
    if (heading != null && heading.isFinite && heading >= 0) {
      m['cog'] = heading.round();
    }
    if (battery != null) m['batt'] = battery;
    if (charging != null) m['bs'] = charging ? 2 : 1;
    return jsonEncode(m);
  }

  static String encodeCard({
    required String name,
    required String trackerId,
    Uint8List? face,
  }) {
    final m = <String, dynamic>{
      '_type': 'card',
      'name': name,
      'tid': trackerId,
    };
    if (face != null) m['face'] = base64Encode(face);
    return jsonEncode(m);
  }

  /// Last will: sent by the broker if we vanish without disconnecting.
  static String encodeLwt(DateTime connectedAt) => jsonEncode({
    '_type': 'lwt',
    'tst': connectedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
  });

  /// Ask another device to publish its location right now.
  static String encodeReportLocationCommand() =>
      jsonEncode({'_type': 'cmd', 'action': 'reportLocation'});

  static bool isReportLocationCommand(Map<String, dynamic> j) =>
      j['_type'] == 'cmd' && j['action'] == 'reportLocation';

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double _round(double v, int places) {
    final s = v.toStringAsFixed(places);
    return double.parse(s);
  }
}

class TopicParts {
  const TopicParts({
    required this.deviceTopic,
    required this.user,
    required this.device,
    this.subtopic,
  });

  final String deviceTopic;
  final String user;
  final String device;

  /// e.g. `info`, `cmd`, `event`; null for the location topic itself.
  final String? subtopic;
}

class CardInfo {
  const CardInfo({this.name, this.face, this.trackerId});
  final String? name;
  final Uint8List? face;
  final String? trackerId;
}
