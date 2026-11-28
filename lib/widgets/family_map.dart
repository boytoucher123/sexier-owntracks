import 'dart:math' as math;
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../models/person.dart';
import '../services/account_service.dart' show Place;
import '../models/settings.dart';
import '../theme.dart';
import '../util/format.dart';
import 'avatar.dart';
import '../strings.dart';

/// CARTO API key, passed at build time with
/// `--dart-define=CARTO_API_KEY=...` (the release workflow reads it from the
/// CARTO_API_KEY repository secret). Without it tiles show CARTO's watermark.
const cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

/// Tile URL for the standard map: CARTO Voyager (light) or Dark Matter
/// (dark). Since September 2026 CARTO watermarks every tile requested
/// without a key with "API KEY REQUIRED", so both styles carry the key.
@visibleForTesting
String cartoTileUrl({required bool dark, String key = cartoApiKey}) {
  final style = dark ? 'dark_all' : 'voyager';
  final url =
      'https://basemaps.cartocdn.com/rastertiles/$style/{z}/{x}/{y}{r}.png';
  if (key.isEmpty) return url;
  return '$url?key=${Uri.encodeQueryComponent(key)}';
}

/// Esri World Imagery: free satellite photos for the standard map, with
/// Esri's place-name layer drawn on top.
const esriImageryUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
const esriLabelsUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

/// Styles each map can draw. Terrain is Google-only; the standard map
/// shows streets instead.
List<MapStyle> mapStylesFor(MapProvider provider) =>
    provider == MapProvider.google
    ? MapStyle.values
    : const [MapStyle.satellite, MapStyle.streets, MapStyle.dark];

MapStyle effectiveMapStyle(MapProvider provider, MapStyle style) =>
    mapStylesFor(provider).contains(style) ? style : MapStyle.streets;

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

  /// Keep [point] in the middle of the map (no animation): for following
  /// something that moves every frame.
  void track(LatLng point) => _delegate?.track(point);

  /// The middle of the map right now.
  LatLng? get center => _delegate?.center;

  /// Zoom in on a place and show its area and name.
  void showPlace(Place place) => _delegate?.showPlace(place);

  /// Pans (keeping the zoom) only if [point] is near the edge or off screen.
  void ensureVisible(LatLng point) => _delegate?.ensureVisible(point);
}

abstract class _MapDelegate {
  LatLng? get center;
  void track(LatLng point);
  void showPlace(Place place);
  void focus(LatLng point, double zoom);
  void fit(List<LatLng> points);
  void ensureVisible(LatLng point);
}

/// How close to the visible edge (in logical pixels) counts as "near the edge".
const double _kEdgeMargin = 56;

/// The map with everyone's pins, plus an optional history trail.
class FamilyMap extends StatelessWidget {
  const FamilyMap({
    super.key,
    required this.provider,
    this.style = MapStyle.satellite,
    required this.controller,
    required this.people,
    required this.onPersonTap,
    this.selectedTopic,
    this.trail = const [],
    this.trailStops = const [],
    this.trailColor,
    this.trailGaps = const {},
    this.floatingDimmed = false,
    this.nodes = const [],
    this.selectedNode,
    this.onNodeTap,
    this.markStale = true,
    this.onMapTap,
    this.bottomInset = 0,
    this.topInset = 0,
    this.floatingTopic,
    this.places = const [],
    this.onCameraIdle,
  });

  /// Test/screenshot hook: replaces network tiles. Never set in the app.
  @visibleForTesting
  static fm.TileProvider? debugTileProvider;

  final MapProvider provider;
  final MapStyle style;
  final FamilyMapController controller;
  final List<Person> people;
  final String? selectedTopic;
  final List<LatLng> trail;
  final List<LatLng> trailStops;
  final Color? trailColor;

  /// Stretches of [trail] (index i: from point i to i+1) where data is
  /// missing. Drawn as a grey dashed line.
  final Set<int> trailGaps;

  /// Grey out the [floatingTopic] pin (its position is only a guess).
  final bool floatingDimmed;

  /// [trail] cut into runs: (points, isGap).
  List<(List<LatLng>, bool)> get trailRuns {
    final out = <(List<LatLng>, bool)>[];
    for (var i = 0; i + 1 < trail.length; i++) {
      final gap = trailGaps.contains(i);
      if (out.isNotEmpty && out.last.$2 == gap) {
        out.last.$1.add(trail[i + 1]);
      } else {
        out.add(([trail[i], trail[i + 1]], gap));
      }
    }
    return out;
  }

  /// Small tappable dots along the trail (history points).
  final List<LatLng> nodes;

  /// Index into [nodes] drawn larger, or null.
  final int? selectedNode;
  final ValueChanged<int>? onNodeTap;

  /// Grey out pins whose location is old. Off for history, where every
  /// position is old on purpose.
  final bool markStale;
  final ValueChanged<Person> onPersonTap;
  final VoidCallback? onMapTap;

  /// Height covered by the bottom sheet, so focusing centres in what's visible.
  final double bottomInset;
  final double topInset;

  /// A pin that moves every frame (history playback). On Google Maps it's
  /// drawn over the map instead of as a marker: moving a marker makes the
  /// plugin re-send its picture each time, which flickers.
  final String? floatingTopic;

  /// Shared places, drawn as circles.
  final List<Place> places;

  /// Called with the centre of the map when it stops moving.
  final ValueChanged<LatLng>? onCameraIdle;

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
  int? _selectedPlace;

  @override
  void showPlace(Place place) {
    setState(() => _selectedPlace = place.id);
    focus(place.center, _zoomFor(place, MediaQuery.sizeOf(context).width));
  }

  @override
  void track(LatLng point) => _run(() {
    final m = widget.map;
    _mc.move(
      point,
      _mc.camera.zoom,
      offset: Offset(0, -(m.bottomInset - m.topInset) / 2),
    );
  });

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
  LatLng? get center => _ready ? _mc.camera.center : null;

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
  void ensureVisible(LatLng point) => _run(() {
    final cam = _mc.camera;
    final o = cam.getOffsetFromOrigin(point);
    final s = cam.nonRotatedSize;
    final m = widget.map;
    if (o.dx < _kEdgeMargin ||
        o.dx > s.width - _kEdgeMargin ||
        o.dy < m.topInset + _kEdgeMargin ||
        o.dy > s.height - m.bottomInset - _kEdgeMargin) {
      focus(point, cam.zoom);
    }
  });

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
    final style = effectiveMapStyle(MapProvider.standard, m.style);
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
        onTap: (_, _) {
          if (_selectedPlace != null) setState(() => _selectedPlace = null);
          m.onMapTap?.call();
        },
        onMapEvent: m.onCameraIdle == null
            ? null
            : (e) {
                if (e is fm.MapEventMoveEnd ||
                    e is fm.MapEventFlingAnimationEnd ||
                    e is fm.MapEventDoubleTapZoomEnd ||
                    e is fm.MapEventScrollWheelZoom) {
                  m.onCameraIdle!(e.camera.center);
                }
              },
        onMapReady: () {
          _ready = true;
          final p = _pending;
          _pending = null;
          p?.call();
        },
      ),
      children: [
        if (style == MapStyle.satellite) ...[
          fm.TileLayer(
            urlTemplate: esriImageryUrl,
            userAgentPackageName: 'app.flock.flock',
            maxNativeZoom: 18,
            tileProvider: FamilyMap.debugTileProvider,
          ),
          fm.TileLayer(
            urlTemplate: esriLabelsUrl,
            userAgentPackageName: 'app.flock.flock',
            maxNativeZoom: 18,
            tileProvider: FamilyMap.debugTileProvider,
          ),
        ] else
          fm.TileLayer(
            urlTemplate: cartoTileUrl(dark: style == MapStyle.dark),
            retinaMode: fm.RetinaMode.isHighDensity(context),
            userAgentPackageName: 'app.flock.flock',
            maxNativeZoom: 20,
            tileProvider: FamilyMap.debugTileProvider,
          ),
        if (m.places.isNotEmpty) ...[
          fm.CircleLayer(
            circles: [
              for (final pl in m.places)
                if (_showsArea(pl, _selectedPlace))
                  fm.CircleMarker(
                    point: pl.center,
                    radius: pl.radius,
                    useRadiusInMeter: true,
                    color: FlockColors.brand.withOpacity(0.12),
                    borderColor: FlockColors.brand.withOpacity(0.7),
                    borderStrokeWidth: 2,
                  ),
            ],
          ),
        ],
        if (m.trail.length > 1)
          fm.PolylineLayer(
            polylines: [
              for (final (pts, gap) in m.trailRuns)
                gap
                    ? fm.Polyline(
                        points: pts,
                        strokeWidth: 4,
                        color: Colors.grey.shade500,
                        pattern: fm.StrokePattern.dashed(
                          segments: const [10, 8],
                        ),
                      )
                    : fm.Polyline(
                        points: pts,
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
        if (m.nodes.isNotEmpty)
          fm.MarkerLayer(
            markers: [
              for (var i = 0; i < m.nodes.length; i++)
                fm.Marker(
                  point: m.nodes[i],
                  width: 28,
                  height: 28,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: m.onNodeTap == null ? null : () => m.onNodeTap!(i),
                    child: Center(
                      child: TrailDot(
                        color: trailColor,
                        selected: i == m.selectedNode,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (m.places.isNotEmpty)
          fm.MarkerLayer(
            markers: [
              for (final pl in m.places)
                if (_showsArea(pl, _selectedPlace))
                  fm.Marker(
                    point: pl.center,
                    width: 180,
                    height: 44,
                    alignment: const Alignment(
                      0,
                      1.6,
                    ), // under the spot: pins sit above it
                    child: IgnorePointer(child: PlaceLabel(name: pl.name)),
                  )
                else
                  fm.Marker(
                    point: pl.center,
                    width: PlaceIcon.size,
                    height: PlaceIcon.size,
                    child: GestureDetector(
                      onTap: () => showPlace(pl),
                      child: const PlaceIcon(),
                    ),
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
                    stale: p.topic == m.floatingTopic
                        ? m.floatingDimmed
                        : m.markStale && isStale(p.last!.timestamp),
                  ),
                ),
              ),
          ],
        ),
        fm.RichAttributionWidget(
          alignment: fm.AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: style == MapStyle.satellite
              ? [fm.TextSourceAttribution(Txt.esriMaxarEarthstarGeographicsAnd)]
              : [
                  fm.TextSourceAttribution(Txt.openstreetmapContributors),
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
  final Map<String, gm.BitmapDescriptor> _dots = {};
  Size _size = Size.zero;
  bool _following = false;

  /// Where the camera is, for placing the floating pin.
  gm.CameraPosition? _cam;
  int? _selectedPlace;
  gm.BitmapDescriptor? _placeIcon;
  bool _placeIconAsked = false;

  gm.BitmapDescriptor? _placeBitmap(double ratio) {
    if (!_placeIconAsked) {
      _placeIconAsked = true;
      _renderPlaceBitmap(ratio).then((bytes) {
        _placeIcon = gm.BitmapDescriptor.bytes(
          bytes,
          width: PlaceIcon.size,
          height: PlaceIcon.size,
        );
        if (mounted) setState(() {});
      });
    }
    return _placeIcon;
  }

  gm.GoogleMapController? _ctl;

  @override
  void track(LatLng point) {
    // No awaiting: called every frame while the history pin moves.
    _ctl?.moveCamera(gm.CameraUpdate.newLatLng(_g(point)));
  }

  @override
  void showPlace(Place place) {
    setState(() => _selectedPlace = place.id);
    focus(place.center, _zoomFor(place, MediaQuery.sizeOf(context).width));
  }

  @override
  LatLng? get center {
    final t = _cam?.target;
    return t == null ? null : LatLng(t.latitude, t.longitude);
  }

  /// [p] in screen pixels (Web Mercator; the map never tilts or rotates).
  /// The camera target sits in the middle of the padded area.
  Offset? _toScreen(LatLng p) {
    final cam = _cam;
    if (cam == null || _size.isEmpty) return null;
    final scale = 256 * math.pow(2, cam.zoom).toDouble();
    Offset world(double lat, double lon) {
      final sin = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
      return Offset(
        (lon + 180) / 360 * scale,
        (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale,
      );
    }

    final m = widget.map;
    final centre = Offset(
      _size.width / 2,
      m.topInset + (_size.height - m.topInset - m.bottomInset) / 2,
    );
    return centre +
        world(p.latitude, p.longitude) -
        world(cam.target.latitude, cam.target.longitude);
  }

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

  @override
  void ensureVisible(LatLng point) async {
    if (_following || _size.isEmpty) return;
    _following = true;
    try {
      final c = await _controller.future;
      final r = await c.getVisibleRegion();
      final n = r.northeast.latitude, s = r.southwest.latitude;
      final e = r.northeast.longitude, w = r.southwest.longitude;
      if (n == s || e == w) return;
      final x = (point.longitude - w) / (e - w) * _size.width;
      final y = (n - point.latitude) / (n - s) * _size.height;
      final m = widget.map;
      if (x < _kEdgeMargin ||
          x > _size.width - _kEdgeMargin ||
          y < m.topInset + _kEdgeMargin ||
          y > _size.height - m.bottomInset - _kEdgeMargin) {
        await c.animateCamera(gm.CameraUpdate.newLatLng(_g(point)));
      }
    } finally {
      _following = false;
    }
  }

  /// Dot icons for history points, drawn once per colour and kind.
  gm.BitmapDescriptor? _dot(Color color, _DotKind kind, double ratio) {
    final key = '${color.toARGB32()}:${kind.name}';
    final have = _dots[key];
    if (have != null) return have;
    _renderDotBitmap(color, kind, ratio).then((bytes) {
      final size = kind.size;
      _dots[key] = gm.BitmapDescriptor.bytes(bytes, width: size, height: size);
      if (mounted) setState(() {});
    });
    return null;
  }

  Future<void> _refreshIcons() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    for (final p in widget.visible) {
      final stale = widget.map.markStale && isStale(p.last!.timestamp);
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
    final trailColor = m.trailColor ?? FlockColors.brand;
    final first = widget.visible.isNotEmpty
        ? widget.visible.first.last!.latLng
        : null;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final stopIcon = _dot(trailColor, _DotKind.stop, ratio);
    final nodeIcon = _dot(trailColor, _DotKind.node, ratio);
    final selIcon = _dot(trailColor, _DotKind.selected, ratio);
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        final map = _buildMap(
          m,
          trailColor,
          first,
          stopIcon,
          nodeIcon,
          selIcon,
        );
        final floating = widget.visible
            .where((p) => p.topic == m.floatingTopic)
            .firstOrNull;
        final at = floating == null ? null : _toScreen(floating.last!.latLng);
        if (at == null) return map;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: map),
            Positioned(
              left: at.dx - MapPin.width / 2,
              top: at.dy - MapPin.height,
              child: IgnorePointer(
                child: MapPin(
                  person: floating!,
                  selected: floating.topic == m.selectedTopic,
                  stale: m.floatingDimmed,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMap(
    FamilyMap m,
    Color trailColor,
    LatLng? first,
    gm.BitmapDescriptor? stopIcon,
    gm.BitmapDescriptor? nodeIcon,
    gm.BitmapDescriptor? selIcon,
  ) {
    final start = gm.CameraPosition(
      target: first != null ? _g(first) : const gm.LatLng(-33.8688, 151.2093),
      zoom: first != null ? 13 : 3,
    );
    _cam ??= start;
    return gm.GoogleMap(
      initialCameraPosition: start,
      onCameraMove: (c) {
        // Redraw only when something is drawn from the camera position.
        if (m.floatingTopic != null) {
          setState(() => _cam = c);
        } else {
          _cam = c;
        }
      },
      onCameraIdle: () {
        // Put the floating pin exactly in place once the map settles (it
        // can trail a frame behind during a pinch).
        if (m.floatingTopic != null && mounted) setState(() {});
        final c = center;
        if (c != null) m.onCameraIdle?.call(c);
      },
      circles: {
        for (final pl in m.places)
          if (_showsArea(pl, _selectedPlace))
            gm.Circle(
              circleId: gm.CircleId('place${pl.id}'),
              center: _g(pl.center),
              radius: pl.radius,
              fillColor: FlockColors.brand.withOpacity(0.12),
              strokeColor: FlockColors.brand.withOpacity(0.7),
              strokeWidth: 2,
            ),
      },
      onMapCreated: (c) {
        _ctl = c;
        if (!_controller.isCompleted) _controller.complete(c);
      },
      mapType: switch (m.style) {
        MapStyle.satellite => gm.MapType.hybrid,
        MapStyle.terrain => gm.MapType.terrain,
        MapStyle.streets || MapStyle.dark => gm.MapType.normal,
      },
      style: m.style == MapStyle.dark ? _darkStyle : null,
      padding: EdgeInsets.only(top: m.topInset, bottom: m.bottomInset),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onTap: (_) {
        if (_selectedPlace != null) setState(() => _selectedPlace = null);
        m.onMapTap?.call();
      },
      markers: {
        for (final p in widget.visible)
          if (p.topic != m.floatingTopic)
            gm.Marker(
              markerId: gm.MarkerId(p.topic),
              position: _g(p.last!.latLng),
              anchor: const Offset(0.5, 1),
              icon: _icons[p.topic] ?? gm.BitmapDescriptor.defaultMarker,
              zIndexInt: p.topic == m.selectedTopic ? 10 : 1,
              onTap: () => m.onPersonTap(p),
            ),
        for (final pl in m.places)
          gm.Marker(
            markerId: gm.MarkerId('place${pl.id}'),
            position: _g(pl.center),
            anchor: const Offset(0.5, 0.5),
            icon:
                _placeBitmap(MediaQuery.devicePixelRatioOf(context)) ??
                gm.BitmapDescriptor.defaultMarkerWithHue(
                  gm.BitmapDescriptor.hueViolet,
                ),
            zIndexInt: 0,
            infoWindow: gm.InfoWindow(title: pl.name),
            onTap: () => showPlace(pl),
          ),
        for (var i = 0; i < m.trailStops.length; i++)
          gm.Marker(
            markerId: gm.MarkerId('stop$i'),
            position: _g(m.trailStops[i]),
            anchor: const Offset(0.5, 0.5),
            flat: true,
            consumeTapEvents: true,
            icon:
                stopIcon ??
                gm.BitmapDescriptor.defaultMarkerWithHue(
                  HSVColor.fromColor(trailColor).hue,
                ),
          ),
        if (nodeIcon != null)
          for (var i = 0; i < m.nodes.length; i++)
            gm.Marker(
              markerId: gm.MarkerId('node$i'),
              position: _g(m.nodes[i]),
              anchor: const Offset(0.5, 0.5),
              flat: true,
              consumeTapEvents: true,
              zIndexInt: i == m.selectedNode ? 3 : 2,
              icon: i == m.selectedNode ? (selIcon ?? nodeIcon) : nodeIcon,
              onTap: m.onNodeTap == null ? null : () => m.onNodeTap!(i),
            ),
      },
      polylines: {
        for (final (i, (pts, gap)) in m.trailRuns.indexed)
          gm.Polyline(
            polylineId: gm.PolylineId('trail$i'),
            points: pts.map(_g).toList(),
            color: gap ? Colors.grey.shade500 : trailColor,
            width: gap ? 4 : 5,
            patterns: gap
                ? [gm.PatternItem.dash(20), gm.PatternItem.gap(14)]
                : const [],
          ),
      },
    );
  }
}

enum _DotKind {
  node(14),
  selected(22),
  stop(18);

  const _DotKind(this.size);
  final double size;
}

/// A history point: a filled dot with a white rim, bigger when selected.
class TrailDot extends StatelessWidget {
  const TrailDot({super.key, required this.color, this.selected = false});
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? _DotKind.selected.size : _DotKind.node.size;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 3 : 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
      ),
    );
  }
}

/// PNG for a place's icon on Google Maps, matching [PlaceIcon].
Future<Uint8List> _renderPlaceBitmap(double ratio) async {
  final px = (PlaceIcon.size * ratio).ceilToDouble();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final c = Offset(px / 2, px / 2);
  canvas.drawCircle(c, px / 2, Paint()..color = Colors.white);
  canvas.drawCircle(
    c,
    px / 2 - 1.5 * ratio,
    Paint()..color = FlockColors.brand,
  );
  final icon = Icons.place_rounded;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 11 * ratio,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  final image = await rec.endRecording().toImage(px.toInt(), px.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// PNG for a Google Maps dot marker, matching [TrailDot] (or a ring for stops).
Future<Uint8List> _renderDotBitmap(
  Color color,
  _DotKind kind,
  double ratio,
) async {
  final px = (kind.size * ratio).ceilToDouble();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final c = Offset(px / 2, px / 2);
  final r = px / 2;
  canvas.drawCircle(c, r, Paint()..color = Colors.white);
  if (kind == _DotKind.stop) {
    canvas.drawCircle(
      c,
      r - 2.5 * ratio,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * ratio,
    );
  } else {
    final rim = (kind == _DotKind.selected ? 3 : 2) * ratio;
    canvas.drawCircle(c, r - rim, Paint()..color = color);
  }
  final image = await rec.endRecording().toImage(px.toInt(), px.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
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

/// A place shows its circle and name only when tapped (or while being
/// made, id -1); otherwise it's a small icon.
bool _showsArea(Place p, int? selected) => p.id == -1 || p.id == selected;

/// A zoom where the place's circle fills about half the screen width.
double _zoomFor(Place p, double screenWidth) {
  final metersPerPx = (p.radius * 2) / (screenWidth * 0.5);
  final z =
      math.log(156543.03 * math.cos(p.lat * math.pi / 180) / metersPerPx) /
      math.ln2;
  return z.clamp(12.0, 19.0);
}

/// A place's icon on the map.
class PlaceIcon extends StatelessWidget {
  const PlaceIcon({super.key});
  static const double size = 18;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: FlockColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
      ),
      child: const Icon(Icons.place_rounded, size: 11, color: Colors.white),
    );
  }
}

/// A place's name on the map.
class PlaceLabel extends StatelessWidget {
  const PlaceLabel({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FlockColors.brand.withOpacity(0.5)),
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: FlockColors.brand,
          ),
        ),
      ),
    );
  }
}
