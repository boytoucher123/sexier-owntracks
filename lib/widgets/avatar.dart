// ignore_for_file: deprecated_member_use
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/person.dart';
import '../theme.dart';

/// Round photo, or coloured initials when there's no photo.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.colorKey,
    required this.initials,
    this.face,
    this.size = 48,
    this.ring = true,
    this.dimmed = false,
    this.enlargeable = false,
    this.label,
  });

  factory Avatar.person(
    Person p, {
    Key? key,
    double size = 48,
    bool dimmed = false,
    bool enlargeable = false,
  }) => Avatar(
    key: key,
    colorKey: p.topic,
    initials: p.initials,
    face: p.face,
    size: size,
    dimmed: dimmed,
    enlargeable: enlargeable,
    label: p.name,
  );

  final String colorKey;
  final String initials;
  final Uint8List? face;
  final double size;
  final bool ring;
  final bool dimmed;

  /// Tapping the photo opens it full screen. Has no effect without a photo.
  final bool enlargeable;

  /// Title shown above the enlarged photo.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final a = _build(context);
    if (!enlargeable || face == null) return a;
    return Semantics(
      button: true,
      label: 'Show photo',
      child: GestureDetector(
        onTap: () => showPhotoViewer(context, face!, title: label),
        child: Hero(tag: face!, child: a),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final color = FlockColors.forKey(colorKey);
    final ringWidth = ring ? (size * 0.06).clamp(2.0, 4.0) : 0.0;
    Widget inner;
    if (face != null) {
      inner = ClipOval(
        child: Image.memory(
          face!,
          width: size - ringWidth * 2,
          height: size - ringWidth * 2,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _initials(color),
        ),
      );
    } else {
      inner = _initials(color);
    }
    final w = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? color : Colors.transparent,
      ),
      child: inner,
    );
    return dimmed ? Opacity(opacity: 0.55, child: w) : w;
  }

  Widget _initials(Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.15)!, color],
        ),
        border: ring ? Border.all(color: Colors.white, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The pin drawn on the map for a person: avatar in a teardrop with a
/// little tail pointing at their exact spot.
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.person,
    this.selected = false,
    this.stale = false,
  });

  final Person person;
  final bool selected;
  final bool stale;

  static const double width = 56;
  static const double height = 68;

  @override
  Widget build(BuildContext context) {
    final color = FlockColors.forKey(person.topic);
    final scale = selected ? 1.15 : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _PinPainter(color: stale ? Colors.grey : color),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 5, 17),
            child: ClipOval(
              child: Avatar(
                colorKey: person.topic,
                initials: person.initials,
                face: person.face,
                size: 46,
                ring: false,
                dimmed: stale,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintPin(canvas, size, color);

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}

void paintPin(Canvas canvas, Size size, Color color) {
  final r = size.width / 2;
  final circle = Path()
    ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r));
  final tail = Path()
    ..moveTo(r - 9, size.width - 4)
    ..lineTo(r, size.height - 2)
    ..lineTo(r + 9, size.width - 4)
    ..close();
  // Union, so the overlap doesn't cancel out and show the shadow through.
  final path = Path.combine(PathOperation.union, circle, tail);
  canvas.drawShadow(path, Colors.black, 4, false);
  canvas.drawPath(path, Paint()..color = color);
  canvas.drawCircle(Offset(r, r), r - 3, Paint()..color = Colors.white);
}

/// Renders a person's pin to PNG bytes for Google Maps markers, which
/// can't host Flutter widgets.
Future<Uint8List> renderPinBitmap(
  Person p, {
  required double pixelRatio,
  bool stale = false,
}) async {
  final w = MapPin.width * pixelRatio;
  final h = MapPin.height * pixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  final color = stale ? Colors.grey : FlockColors.forKey(p.topic);
  paintPin(canvas, const Size(MapPin.width, MapPin.height), color);

  const center = Offset(MapPin.width / 2, MapPin.width / 2);
  const radius = MapPin.width / 2 - 5;
  final clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  ui.Image? photo;
  if (p.face != null) {
    try {
      final codec = await ui.instantiateImageCodec(p.face!);
      photo = (await codec.getNextFrame()).image;
    } on Object {
      photo = null;
    }
  }

  canvas.save();
  canvas.clipPath(clip);
  if (photo != null) {
    final src = Rect.fromLTWH(
      0,
      0,
      photo.width.toDouble(),
      photo.height.toDouble(),
    );
    final dst = Rect.fromCircle(center: center, radius: radius);
    canvas.drawImageRect(
      photo,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawCircle(center, radius, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: p.initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.ceil(), h.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Shows a profile photo as big as the screen allows. Tap anywhere or swipe
/// back to close; pinch to zoom.
Future<void> showPhotoViewer(
  BuildContext context,
  Uint8List face, {
  String? title,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (context, _, _) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: title == null ? null : Text(title),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: InteractiveViewer(
                maxScale: 4,
                child: Hero(
                  tag: face,
                  child: ClipOval(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Image.memory(
                        face,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionsBuilder: (context, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}
