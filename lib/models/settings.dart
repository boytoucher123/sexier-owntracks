import 'dart:convert';

import '../config/server_config.dart';

/// How hard the phone works to track your position.
enum TrackingMode {
  /// Few updates, minimal battery. Good for "roughly where are they".
  batterySaver,

  /// Default. Updates every few minutes or every ~100 m of movement.
  balanced,

  /// Frequent, high-accuracy updates. Uses noticeably more battery.
  precise,
}

extension TrackingModeText on TrackingMode {
  String get label => switch (this) {
    TrackingMode.batterySaver => 'Saver',
    TrackingMode.balanced => 'Balanced',
    TrackingMode.precise => 'Precise',
  };

  String get description => switch (this) {
    TrackingMode.batterySaver =>
      'Updates when you move about 500 m. Easiest on battery.',
    TrackingMode.balanced => 'Updates every ~100 m of movement. Recommended.',
    TrackingMode.precise =>
      'Frequent, exact updates. Uses noticeably more battery.',
  };
}

/// Which map tiles to draw.
enum MapProvider {
  /// Free OpenStreetMap-based tiles (CARTO), with Esri imagery for satellite.
  standard,

  /// Google Maps. The default when the build has a Google Maps API key;
  /// builds without one fall back to [standard].
  google,
}

/// What the map looks like.
enum MapStyle {
  /// Satellite photos with street names on top. The default.
  satellite,

  /// A light street map.
  streets,

  /// Hills and parks shaded in. Google Maps only.
  terrain,

  /// A dark street map, easy on the eyes at night.
  dark,
}

/// Everything the user configures. Secrets (passwords) are not serialised
/// here; they live in secure storage and are attached at load time.
class AppSettings {
  const AppSettings({
    this.host = kDefaultHost,
    this.port = kDefaultPort,
    this.useTls = true,
    this.useWebSocket = false,
    this.username = '',
    this.password = '',
    this.deviceName = kDeviceName,
    this.trackerId = '',
    this.displayName = '',
    this.baseTopic = 'owntracks',
    this.recorderUrl = kDefaultRecorderUrl,
    this.recorderUsername = '',
    this.recorderPassword = '',
    this.trackingMode = TrackingMode.balanced,
    this.mapProvider = MapProvider.google,
    this.mapStyle = MapStyle.satellite,
    this.sharingLocation = true,
    this.setupComplete = false,
    this.keepAliveSeconds = 60,
    this.allowUntrustedCertificates = false,
    this.caPem = kServerCaPem,
    this.activeGroupId = 0,
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

  /// The CA the server's certificate must chain to, on top of the phone's
  /// normal ones. Comes from the active group; empty = the phone's own only.
  /// Not saved: the group's settings fill it in at runtime.
  final String caPem;

  /// The group whose settings (server, tracking) this phone uses. 0 = the
  /// first group you're in.
  final int activeGroupId;

  // --- Preferences ----------------------------------------------------------
  final TrackingMode trackingMode;
  final MapProvider mapProvider;
  final MapStyle mapStyle;
  final bool sharingLocation;
  final bool setupComplete;

  /// `owntracks/<login>/<device>`: where this phone publishes its location.
  String get ownTopic => '$baseTopic/$username/$deviceName';

  /// A personal account made by the app (not the old shared login).
  bool get hasAccount =>
      username.isNotEmpty && password.isNotEmpty && username != kLegacyUsername;

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
    MapStyle? mapStyle,
    bool? sharingLocation,
    bool? setupComplete,
    int? keepAliveSeconds,
    bool? allowUntrustedCertificates,
    String? caPem,
    int? activeGroupId,
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
      mapStyle: mapStyle ?? this.mapStyle,
      sharingLocation: sharingLocation ?? this.sharingLocation,
      setupComplete: setupComplete ?? this.setupComplete,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      allowUntrustedCertificates:
          allowUntrustedCertificates ?? this.allowUntrustedCertificates,
      caPem: caPem ?? this.caPem,
      activeGroupId: activeGroupId ?? this.activeGroupId,
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
    'mapStyle': mapStyle.name,
    'sharingLocation': sharingLocation,
    'setupComplete': setupComplete,
    'keepAliveSeconds': keepAliveSeconds,
    'allowUntrustedCertificates': allowUntrustedCertificates,
    'activeGroupId': activeGroupId,
  };

  factory AppSettings.fromJson(
    Map<String, dynamic> j, {
    String password = '',
    String recorderPassword = '',
  }) {
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    return AppSettings(
      host: pick('host', kDefaultHost),
      port: pick('port', kDefaultPort),
      useTls: pick('useTls', true),
      useWebSocket: pick('useWebSocket', false),
      username: pick('username', ''),
      password: password,
      deviceName: pick('deviceName', kDeviceName),
      trackerId: pick('trackerId', ''),
      displayName: pick('displayName', ''),
      baseTopic: pick('baseTopic', 'owntracks'),
      // Saved before history was set up? Use the server's history address.
      recorderUrl: pick('recorderUrl', '').trim().isEmpty
          ? kDefaultRecorderUrl
          : pick('recorderUrl', ''),
      recorderUsername: pick('recorderUsername', ''),
      recorderPassword: recorderPassword,
      trackingMode: TrackingMode.values.firstWhere(
        (m) => m.name == j['trackingMode'],
        orElse: () => TrackingMode.balanced,
      ),
      mapProvider: MapProvider.values.firstWhere(
        (m) => m.name == j['mapProvider'],
        orElse: () => MapProvider.google,
      ),
      mapStyle: MapStyle.values.firstWhere(
        (m) => m.name == j['mapStyle'],
        orElse: () => MapStyle.satellite,
      ),
      sharingLocation: pick('sharingLocation', true),
      setupComplete: pick('setupComplete', false),
      keepAliveSeconds: pick('keepAliveSeconds', 60),
      allowUntrustedCertificates: pick('allowUntrustedCertificates', false),
      activeGroupId: pick('activeGroupId', 0),
    );
  }

  String encode() => jsonEncode(toJson());
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
