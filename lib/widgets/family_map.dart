// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../models/person.dart';
import '../models/settings.dart';
import '../theme.dart';
import '../util/format.dart';
import 'avatar.dart';

/// Lets the home screen move the camera without caring which map is used.
class FamilyMapController {
  _MapDelegate? _delegate;

  void focus(LatLng point, {double zoom = 15.5}) =>
      _delegate?.focus(point, zoom);

  void fit(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) return focus(points.first);
    _delegate?.fit(points);
  }
}

abstract class _MapDelegate {
  void focus(LatLng point, double zoom);
  void fit(List<LatLng> points);
}

/// The map with everyone's pins, plus an optional history trail.
class FamilyMap extends StatelessWidget {
  const FamilyMap({
    super.key,
    required this.provider,
    required this.controller,
    required this.people,
    required this.onPersonTap,
    this.selectedTopic,
    this.trail = const [],
    this.trailStops = const [],
    this.trailColor,
    this.onMapTap,
    this.bottomInset = 0,
    this.topInset = 0,
  });

  /// Test/screenshot hook: replaces network tiles. Never set in the app.
  @visibleForTesting
  static fm.TileProvider? debugTileProvider;

  final MapProvider provider;
  final FamilyMapController controller;
  final List<Person> people;
  final String? selectedTopic;
  final List<LatLng> trail;
  final List<LatLng> trailStops;
  final Color? trailColor;
  final ValueChanged<Person> onPersonTap;
  final VoidCallback? onMapTap;

  /// Height covered by the bottom sheet, so focusing centres in what's visible.
  final double bottomInset;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final visible = people.where((p) => p.hasLocation).toList();
    // Draw the selected person last so they sit on top.
    visible.sort((a, b) {
      if (a.topic == selectedTopic) return 1;
      if (b.topic == selectedTopic) return -1;
      return 0;
    });
    switch (provider) {
      case MapProvider.google:
        return _GoogleFamilyMap(map: this, visible: visible);
      case MapProvider.standard:
        return _StandardFamilyMap(map: this, visible: visible);
    }
  }
}

// ---------------------------------------------------------------- Standard --

class _StandardFamilyMap extends StatefulWidget {
  const _StandardFamilyMap({required this.map, required this.visible});
  final FamilyMap map;
  final List<Person> visible;

  @override
  State<_StandardFamilyMap> createState() => _StandardFamilyMapState();
}

class _StandardFamilyMapState extends State<_StandardFamilyMap>
    implements _MapDelegate {
  final _mc = fm.MapController();
  bool _ready = false;
  void Function()? _pending;

  @override
  void initState() {
    super.initState();
    widget.map.controller._delegate = this;
  }

  @override
  void didUpdateWidget(covariant _StandardFamilyMap old) {
    super.didUpdateWidget(old);
    widget.map.controller._delegate = this;
  }

  void _run(void Function() f) => _ready ? f() : _pending = f;

  @override
  void focus(LatLng point, double zoom) => _run(() {
    _mc.move(
      point,
      zoom,
      offset: Offset(0, -(widget.map.bottomInset - widget.map.topInset) / 2),
    );
  });

  @override
  void fit(List<LatLng> points) => _run(() {
    _mc.fitCamera(
      fm.CameraFit.coordinates(
        coordinates: points,
        padding: EdgeInsets.fromLTRB(
          64,
          widget.map.topInset + 64,
          64,
          widget.map.bottomInset + 48,
        ),
        maxZoom: 16,
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = dark ? 'dark_all' : 'rastertiles/voyager';
    final trailColor = m.trailColor ?? FlockColors.brand;
    return fm.FlutterMap(
      mapController: _mc,
      options: fm.MapOptions(
        initialCenter: widget.visible.isNotEmpty
            ? widget.visible.first.last!.latLng
            : const LatLng(-33.8688, 151.2093),
        initialZoom: widget.visible.isNotEmpty ? 13 : 3,
        minZoom: 2,
        maxZoom: 19,
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
        onTap: (_, _) => m.onMapTap?.call(),
        onMapReady: () {
          _ready = true;
          final p = _pending;
          _pending = null;
          p?.call();
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/$style/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: fm.RetinaMode.isHighDensity(context),
          userAgentPackageName: 'app.flock.flock',
          maxNativeZoom: 20,
          tileProvider: FamilyMap.debugTileProvider,
        ),
        if (m.trail.length > 1)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: m.trail,
                strokeWidth: 5,
                color: trailColor,
                borderStrokeWidth: 2,
                borderColor: Colors.white.withOpacity(0.9),
              ),
            ],
          ),
        if (m.trailStops.isNotEmpty)
          fm.CircleLayer(
            circles: [
              for (final s in m.trailStops)
                fm.CircleMarker(
                  point: s,
                  radius: 7,
                  color: Colors.white,
                  borderColor: trailColor,
                  borderStrokeWidth: 4,
                ),
            ],
          ),
        fm.MarkerLayer(
          markers: [
            for (final p in widget.visible)
              fm.Marker(
                key: ValueKey(p.topic),
                point: p.last!.latLng,
                width: MapPin.width,
                height: MapPin.height,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => m.onPersonTap(p),
                  child: MapPin(
                    person: p,
                    selected: p.topic == m.selectedTopic,
                    stale: isStale(p.last!.timestamp),
                  ),
                ),
              ),
          ],
        ),
        fm.RichAttributionWidget(
          alignment: fm.AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [
            fm.TextSourceAttribution('OpenStreetMap contributors'),
            fm.TextSourceAttribution('CARTO'),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Google --

class _GoogleFamilyMap extends StatefulWidget {
  const _GoogleFamilyMap({required this.map, required this.visible});
  final FamilyMap map;
  final List<Person> visible;

  @override
  State<_GoogleFamilyMap> createState() => _GoogleFamilyMapState();
}

class _GoogleFamilyMapState extends State<_GoogleFamilyMap>
    implements _MapDelegate {
  final _controller = Completer<gm.GoogleMapController>();
  final Map<String, gm.BitmapDescriptor> _icons = {};
  final Map<String, String> _iconKeys = {};

  @override
  void initState() {
    super.initState();
    widget.map.controller._delegate = this;
  }

  @override
  void didUpdateWidget(covariant _GoogleFamilyMap old) {
    super.didUpdateWidget(old);
    widget.map.controller._delegate = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshIcons();
  }

  gm.LatLng _g(LatLng p) => gm.LatLng(p.latitude, p.longitude);

  @override
  void focus(LatLng point, double zoom) async {
    final c = await _controller.future;
    await c.animateCamera(gm.CameraUpdate.newLatLngZoom(_g(point), zoom));
  }

  @override
  void fit(List<LatLng> points) async {
    final c = await _controller.future;
    var s = points.first.latitude, n = s, w = points.first.longitude, e = w;
    for (final p in points) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    await c.animateCamera(
      gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(southwest: gm.LatLng(s, w), northeast: gm.LatLng(n, e)),
        64,
      ),
    );
  }

  Future<void> _refreshIcons() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    for (final p in widget.visible) {
      final stale = isStale(p.last!.timestamp);
      final key = '${p.face?.length ?? 0}:${p.initials}:$stale';
      if (_iconKeys[p.topic] == key) continue;
      _iconKeys[p.topic] = key;
      final Uint8List bytes = await renderPinBitmap(
        p,
        pixelRatio: ratio,
        stale: stale,
      );
      _icons[p.topic] = gm.BitmapDescriptor.bytes(
        bytes,
        width: MapPin.width,
        height: MapPin.height,
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _refreshIcons();
    final m = widget.map;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final trailColor = m.trailColor ?? FlockColors.brand;
    final first = widget.visible.isNotEmpty
        ? widget.visible.first.last!.latLng
        : null;
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(
        target: first != null ? _g(first) : const gm.LatLng(-33.8688, 151.2093),
        zoom: first != null ? 13 : 3,
      ),
      onMapCreated: (c) {
        if (!_controller.isCompleted) _controller.complete(c);
      },
      style: dark ? _darkStyle : null,
      padding: EdgeInsets.only(top: m.topInset, bottom: m.bottomInset),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onTap: (_) => m.onMapTap?.call(),
      markers: {
        for (final p in widget.visible)
          gm.Marker(
            markerId: gm.MarkerId(p.topic),
            position: _g(p.last!.latLng),
            anchor: const Offset(0.5, 1),
            icon: _icons[p.topic] ?? gm.BitmapDescriptor.defaultMarker,
            zIndexInt: p.topic == m.selectedTopic ? 10 : 1,
            onTap: () => m.onPersonTap(p),
          ),
        for (var i = 0; i < m.trailStops.length; i++)
          gm.Marker(
            markerId: gm.MarkerId('stop$i'),
            position: _g(m.trailStops[i]),
            anchor: const Offset(0.5, 0.5),
            flat: true,
            icon: gm.BitmapDescriptor.defaultMarkerWithHue(
              HSVColor.fromColor(trailColor).hue,
            ),
          ),
      },
      polylines: {
        if (m.trail.length > 1)
          gm.Polyline(
            polylineId: const gm.PolylineId('trail'),
            points: m.trail.map(_g).toList(),
            color: trailColor,
            width: 5,
          ),
      },
    );
  }
}

const _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d1b26"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8f8aa3"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1d1b26"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c2938"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3d3850"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f0e17"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]
''';
