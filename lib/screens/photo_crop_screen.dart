// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Shows a picked photo large, lets the person drag and pinch it inside a
/// circle, and returns the chosen square as JPEG bytes (or null on cancel).
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.original});

  final Uint8List original;

  /// Opens the cropper and returns the cropped photo, or null if cancelled.
  static Future<Uint8List?> open(BuildContext context, Uint8List original) =>
      Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PhotoCropScreen(original: original),
        ),
      );

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _transform = TransformationController();
  PreparedPhoto? _photo;
  bool _failed = false;
  bool _saving = false;
  double _viewport = 0;
  Size _child = Size.zero;

  @override
  void initState() {
    super.initState();
    compute(preparePhoto, widget.original).then((p) {
      if (!mounted) return;
      setState(() {
        _photo = p;
        _failed = p == null;
      });
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Size the photo so it just covers the square, and centre it.
  void _layout(double viewport) {
    final p = _photo!;
    if (viewport == _viewport) return;
    _viewport = viewport;
    final cover = viewport / (p.width < p.height ? p.width : p.height);
    _child = Size(p.width * cover, p.height * cover);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -(_child.width - viewport) / 2,
        -(_child.height - viewport) / 2,
        0,
        1,
      );
  }

  Future<void> _done() async {
    final p = _photo!;
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final toPixels = p.width / _child.width;
    final rect = CropRect(
      x: (-t.x / scale) * toPixels,
      y: (-t.y / scale) * toPixels,
      side: (_viewport / scale) * toPixels,
    );
    setState(() => _saving = true);
    final out = await compute(cropPhoto, (p.bytes, rect));
    if (mounted) Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        title: const Text('Move and scale'),
        actions: [
          TextButton(
            onPressed: photo == null || _saving ? null : _done,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Use photo'),
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? const Center(
                child: Text(
                  'That photo couldn\'t be opened. Try another one.',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : photo == null || _saving
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, c) {
                  final side =
                      (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) -
                      32;
                  _layout(side);
                  return Column(
                    children: [
                      const Spacer(),
                      Center(
                        child: SizedBox.square(
                          dimension: side,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  constrained: false,
                                  minScale: 1,
                                  maxScale: 6,
                                  child: Image.memory(
                                    photo.bytes,
                                    width: _child.width,
                                    height: _child.height,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                              const IgnorePointer(
                                child: CustomPaint(painter: _CircleMask()),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Drag to move. Pinch to zoom.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// Darkens everything outside the circle that becomes the profile photo.
class _CircleMask extends CustomPainter {
  const _CircleMask();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final hole = Path()..addOval(r);
    final shade = Path.combine(
      PathOperation.difference,
      Path()..addRect(r),
      hole,
    );
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      r.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_CircleMask old) => false;
}

/// A photo with its EXIF rotation applied, shrunk to a workable size, so
/// what's shown on screen and what gets cropped line up exactly.
class PreparedPhoto {
  const PreparedPhoto(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

class CropRect {
  const CropRect({required this.x, required this.y, required this.side});
  final double x;
  final double y;
  final double side;
}

/// Runs in an isolate.
PreparedPhoto? preparePhoto(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  const maxSide = 1600;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  return PreparedPhoto(
    Uint8List.fromList(img.encodeJpg(im, quality: 92)),
    im.width,
    im.height,
  );
}

/// Size of the saved profile photo, in pixels.
const kFaceSize = 320;

/// Runs in an isolate. Crops [rect] (clamped to the image) and resizes it
/// to a [kFaceSize] square JPEG.
Uint8List cropPhoto((Uint8List, CropRect) args) {
  final (bytes, rect) = args;
  final im = img.decodeImage(bytes)!;
  final maxSide = im.width < im.height ? im.width : im.height;
  final side = rect.side.round().clamp(1, maxSide);
  final x = rect.x.round().clamp(0, im.width - side);
  final y = rect.y.round().clamp(0, im.height - side);
  final square = img.copyCrop(im, x: x, y: y, width: side, height: side);
  final small = img.copyResize(
    square,
    width: kFaceSize,
    height: kFaceSize,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(small, quality: 85));
}
