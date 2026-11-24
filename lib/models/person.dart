import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// One position fix, as sent by an OwnTracks client.
class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.velocityKmh,
    this.course,
    this.battery,
    this.charging,
    this.trackerId,
    this.connection,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;
  final double? accuracy;
  final double? altitude;
  final double? velocityKmh;
  final double? course;

  /// Battery percent, 0-100.
  final int? battery;
  final bool? charging;
  final String? trackerId;

  /// `w` wifi, `m` mobile, `o` offline.
  final String? connection;

  LatLng get latLng => LatLng(lat, lon);
}

/// A person on the map. In this app's model each OwnTracks *device* is a
/// person: everyone shares one login and puts their own name as the device,
/// so `owntracks/crew/Fred` is Fred.
class Person {
  Person({
    required this.topic,
    required this.user,
    required this.device,
    this.cardName,
    this.face,
    this.trackerId,
    this.last,
  });

  /// Base topic, e.g. `owntracks/crew/Fred`. Unique key.
  final String topic;
  final String user;
  final String device;

  /// Name from the person's card (`_type: card`), if they've set one.
  String? cardName;

  /// Profile photo from the card, decoded from base64.
  Uint8List? face;

  String? trackerId;
  LocationFix? last;

  String get name {
    final n = cardName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return device;
  }

  String get initials {
    final t = trackerId?.trim();
    if (t != null && t.isNotEmpty) return t.toUpperCase();
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get hasLocation => last != null;
}
