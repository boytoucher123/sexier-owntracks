import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/settings.dart';
import '../strings.dart';

enum LocationAccess {
  /// We haven't asked yet, or the user dismissed the prompt.
  notAsked,

  /// Only while the app is open. Friends won't see updates in the background.
  whileUsing,

  /// All the time. What we want.
  always,

  /// Blocked. Only fixable from system settings.
  denied,

  /// Location services are switched off for the whole phone.
  servicesOff,
}

/// A position plus the phone's battery, ready to publish.
class DeviceFix {
  DeviceFix(this.position, this.battery, this.charging, this.trigger);
  final Position position;
  final int? battery;
  final bool? charging;

  /// OwnTracks trigger: `p` ping, `u` user, `r` response to request, `t` timer.
  final String trigger;
}

/// Watches the phone's location in the foreground and background.
class LocationService {
  final _battery = Battery();
  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  Position? _last;

  final ValueNotifier<Position?> current = ValueNotifier(null);

  /// Called with every fix that should be published.
  void Function(DeviceFix fix)? onFix;

  Position? get last => _last;

  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.servicesOff;
    }
    final p = await Geolocator.checkPermission();
    return _map(p);
  }

  /// Shows the system prompt. On Android 11+ and iOS, "always" has to be
  /// requested as a second step after "while using".
  Future<LocationAccess> request() async {
    final p = await Geolocator.requestPermission();
    return _map(p);
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  LocationAccess _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
        return LocationAccess.always;
      case LocationPermission.whileInUse:
        return LocationAccess.whileUsing;
      case LocationPermission.deniedForever:
        return LocationAccess.denied;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.notAsked;
    }
  }

  Future<void> start(TrackingMode mode) async {
    await stop();
    final a = await access();
    if (a != LocationAccess.always && a != LocationAccess.whileUsing) return;

    _sub = Geolocator.getPositionStream(locationSettings: _settingsFor(mode))
        .listen((pos) => _emit(pos, 'p'), onError: (Object _) {});

    // Even when nobody moves, send a check-in so friends can see the phone
    // is alive and the battery level stays fresh.
    _heartbeat = Timer.periodic(_heartbeatFor(mode), (_) => reportNow('t'));

    // Publish where we are right away rather than waiting for movement.
    unawaited(reportNow('u'));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Gets a fresh fix and publishes it. Used for "refresh", for the
  /// heartbeat, and when someone else asks for our location.
  Future<void> reportNow(String trigger) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      await _emit(pos, trigger);
    } on Object {
      final l = _last;
      if (l != null) await _emit(l, trigger);
    }
  }

  Future<void> _emit(Position pos, String trigger) async {
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
    _last = pos;
    current.value = pos;
    int? level;
    bool? charging;
    try {
      level = await _battery.batteryLevel;
      final st = await _battery.batteryState;
      charging = st == BatteryState.charging || st == BatteryState.full
          ? true
          : st == BatteryState.discharging ||
                st == BatteryState.connectedNotCharging
          ? false
          : null;
    } on Object {
      // battery info is optional
    }
    onFix?.call(DeviceFix(pos, level, charging, trigger));
  }

  Duration _heartbeatFor(TrackingMode m) => switch (m) {
    TrackingMode.batterySaver => const Duration(minutes: 30),
    TrackingMode.balanced => const Duration(minutes: 15),
    TrackingMode.precise => const Duration(minutes: 5),
  };

  LocationSettings _settingsFor(TrackingMode m) {
    final (accuracy, distance, interval) = switch (m) {
      TrackingMode.batterySaver => (
        LocationAccuracy.low,
        500,
        const Duration(minutes: 10),
      ),
      TrackingMode.balanced => (
        LocationAccuracy.medium,
        100,
        const Duration(minutes: 2),
      ),
      TrackingMode.precise => (
        LocationAccuracy.high,
        15,
        const Duration(seconds: 20),
      ),
    };

    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: Txt.sharingYourLocation,
          notificationText: Txt.yourFriendsCanSeeWhere2,
          notificationChannelName: Txt.locationSharing,
          setOngoing: true,
          enableWakeLock: false,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: m == TrackingMode.batterySaver,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distance);
  }
}
