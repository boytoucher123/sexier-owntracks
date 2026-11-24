import 'dart:convert';

/// How hard the phone works to track your position.
enum TrackingMode {
  /// Few updates, minimal battery. Good for "roughly where are they".
  batterySaver,

  /// Default. Updates every few minutes or every ~100 m of movement.
  balanced,

  /// Frequent, high-accuracy updates. Uses noticeably more battery.
  precise,
}

/// Which map tiles to draw.
enum MapProvider {
  /// Free OpenStreetMap-based tiles (CARTO Voyager). Works out of the box.
  standard,

  /// Google Maps. Only offered when the build has a Google Maps API key.
  google,
}

/// Everything the user configures. Secrets (passwords) are not serialised
/// here; they live in secure storage and are attached at load time.
class AppSettings {
  const AppSettings({
    this.host = '',
    this.port = 8883,
    this.useTls = true,
    this.useWebSocket = false,
    this.username = '',
    this.password = '',
    this.deviceName = '',
    this.trackerId = '',
    this.displayName = '',
    this.baseTopic = 'owntracks',
    this.recorderUrl = '',
    this.recorderUsername = '',
    this.recorderPassword = '',
    this.trackingMode = TrackingMode.balanced,
    this.mapProvider = MapProvider.standard,
    this.sharingLocation = true,
    this.setupComplete = false,
    this.keepAliveSeconds = 60,
    this.allowUntrustedCertificates = false,
  });

  // --- Connection -----------------------------------------------------------
  final String host;
  final int port;
  final bool useTls;
  final bool useWebSocket;

  /// The shared login everyone uses. Also the user segment of the topic.
  final String username;
  final String password;

  // --- Who am I -------------------------------------------------------------
  /// Topic-safe device segment, e.g. `Fred` in `owntracks/crew/Fred`.
  final String deviceName;

  /// Two-character tracker ID shown on maps, e.g. `FD`.
  final String trackerId;

  /// Friendly name published in the card, e.g. `Fred Durk`.
  final String displayName;

  // --- Advanced -------------------------------------------------------------
  final String baseTopic;
  final String recorderUrl;
  final String recorderUsername;
  final String recorderPassword;
  final int keepAliveSeconds;
  final bool allowUntrustedCertificates;

  // --- Preferences ----------------------------------------------------------
  final TrackingMode trackingMode;
  final MapProvider mapProvider;
  final bool sharingLocation;
  final bool setupComplete;

  /// `owntracks/<login>/<device>`: where this phone publishes its location.
  String get ownTopic => '$baseTopic/$username/$deviceName';

  bool get hasRecorder => recorderUrl.trim().isNotEmpty;

  bool get hasConnectionDetails =>
      host.trim().isNotEmpty && username.trim().isNotEmpty;

  AppSettings copyWith({
    String? host,
    int? port,
    bool? useTls,
    bool? useWebSocket,
    String? username,
    String? password,
    String? deviceName,
    String? trackerId,
    String? displayName,
    String? baseTopic,
    String? recorderUrl,
    String? recorderUsername,
    String? recorderPassword,
    TrackingMode? trackingMode,
    MapProvider? mapProvider,
    bool? sharingLocation,
    bool? setupComplete,
    int? keepAliveSeconds,
    bool? allowUntrustedCertificates,
  }) {
    return AppSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      useTls: useTls ?? this.useTls,
      useWebSocket: useWebSocket ?? this.useWebSocket,
      username: username ?? this.username,
      password: password ?? this.password,
      deviceName: deviceName ?? this.deviceName,
      trackerId: trackerId ?? this.trackerId,
      displayName: displayName ?? this.displayName,
      baseTopic: baseTopic ?? this.baseTopic,
      recorderUrl: recorderUrl ?? this.recorderUrl,
      recorderUsername: recorderUsername ?? this.recorderUsername,
      recorderPassword: recorderPassword ?? this.recorderPassword,
      trackingMode: trackingMode ?? this.trackingMode,
      mapProvider: mapProvider ?? this.mapProvider,
      sharingLocation: sharingLocation ?? this.sharingLocation,
      setupComplete: setupComplete ?? this.setupComplete,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      allowUntrustedCertificates:
          allowUntrustedCertificates ?? this.allowUntrustedCertificates,
    );
  }

  /// Non-secret fields only.
  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'useTls': useTls,
    'useWebSocket': useWebSocket,
    'username': username,
    'deviceName': deviceName,
    'trackerId': trackerId,
    'displayName': displayName,
    'baseTopic': baseTopic,
    'recorderUrl': recorderUrl,
    'recorderUsername': recorderUsername,
    'trackingMode': trackingMode.name,
    'mapProvider': mapProvider.name,
    'sharingLocation': sharingLocation,
    'setupComplete': setupComplete,
    'keepAliveSeconds': keepAliveSeconds,
    'allowUntrustedCertificates': allowUntrustedCertificates,
  };

  factory AppSettings.fromJson(
    Map<String, dynamic> j, {
    String password = '',
    String recorderPassword = '',
  }) {
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    return AppSettings(
      host: pick('host', ''),
      port: pick('port', 8883),
      useTls: pick('useTls', true),
      useWebSocket: pick('useWebSocket', false),
      username: pick('username', ''),
      password: password,
      deviceName: pick('deviceName', ''),
      trackerId: pick('trackerId', ''),
      displayName: pick('displayName', ''),
      baseTopic: pick('baseTopic', 'owntracks'),
      recorderUrl: pick('recorderUrl', ''),
      recorderUsername: pick('recorderUsername', ''),
      recorderPassword: recorderPassword,
      trackingMode: TrackingMode.values.firstWhere(
        (m) => m.name == j['trackingMode'],
        orElse: () => TrackingMode.balanced,
      ),
      mapProvider: MapProvider.values.firstWhere(
        (m) => m.name == j['mapProvider'],
        orElse: () => MapProvider.standard,
      ),
      sharingLocation: pick('sharingLocation', true),
      setupComplete: pick('setupComplete', false),
      keepAliveSeconds: pick('keepAliveSeconds', 60),
      allowUntrustedCertificates: pick('allowUntrustedCertificates', false),
    );
  }

  String encode() => jsonEncode(toJson());
}

/// Turns "Fred Durk" into a topic-safe device name: `Fred`.
/// Uses the first word so topics read naturally (owntracks/crew/Fred).
String deviceNameFromDisplayName(String displayName) {
  final first = displayName.trim().split(RegExp(r'\s+')).first;
  return sanitizeTopicSegment(first);
}

/// MQTT topic levels can't contain `/`, `+` or `#`; we also drop anything
/// that isn't a letter, digit, `-` or `_` to keep things predictable.
String sanitizeTopicSegment(String input) {
  return input.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
}

/// "Fred Durk" -> "FD", "Fred" -> "FR", "" -> "".
String trackerIdFromDisplayName(String displayName) {
  final words = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}
