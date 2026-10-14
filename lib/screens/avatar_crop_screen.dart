// avatar_crop_screen.dart — profielfoto uitsnijden: de gekozen foto vult een
// vierkant met een rond kader erover; knijpen = zoomen, slepen =
// verschuiven. "Gebruiken" snijdt precies het zichtbare vierkant uit en
// levert een JPEG van 512×512 op.
//
// Het rekenwerk (welk stuk van de foto is zichtbaar?) zit in
// [visibleImageRect], los van de UI, zodat het te testen is.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/kinetic_theme.dart';

/// Uitvoergrootte van de profielfoto (vierkant).
const kAvatarSize = 512;

/// Opent het uitsnijscherm voor [bytes]; geeft de uitgesneden JPEG terug,
/// of null bij annuleren of een onleesbare afbeelding.
Future<Uint8List?> cropAvatar(BuildContext context, Uint8List bytes) {
  return Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropScreen(bytes: bytes),
    ),
  );
}

/// Het deel van de originele foto (in pixels) dat binnen het vierkante
/// kader valt.
///
/// De foto wordt eerst zo geschaald dat hij het kader van [viewport] ×
/// [viewport] precies vult ("cover", schaal [baseScale] = viewport / kortste
/// zijde); [transform] is daarna de zoom/verschuiving van de gebruiker
/// (scène → beeld, zoals de TransformationController van een
/// InteractiveViewer). Het resultaat is altijd vierkant en valt binnen de
/// foto.
Rect visibleImageRect({
  required Size imageSize,
  required double viewport,
  required Matrix4 transform,
}) {
  final baseScale = viewport / math.min(imageSize.width, imageSize.height);
  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(viewport, viewport),
  );
  var side = (bottomRight.dx - topLeft.dx) / baseScale;
  side = side.clamp(1.0, math.min(imageSize.width, imageSize.height));
  final left = (topLeft.dx / baseScale).clamp(0.0, imageSize.width - side);
  final top = (topLeft.dy / baseScale).clamp(0.0, imageSize.height - side);
  return Rect.fromLTWH(left, top, side, side);
}

/// Snijdt [rect] uit [bytes] en schaalt naar [kAvatarSize] — draait in een
/// aparte isolate, zodat een grote camerafoto de UI niet laat haperen.
Future<Uint8List?> cropAndEncode(Uint8List bytes, Rect rect) => compute(
  _cropAndEncode,
  (bytes, rect.left, rect.top, rect.width),
);

Uint8List? _cropAndEncode((Uint8List, double, double, double) args) {
  final (bytes, left, top, side) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Camerafoto's staan vaak "gedraaid" met een EXIF-oriëntatie.
  final oriented = img.bakeOrientation(decoded);
  final cropped = img.copyCrop(
    oriented,
    x: left.round(),
    y: top.round(),
    width: side.round(),
    height: side.round(),
  );
  final resized = img.copyResize(
    cropped,
    width: kAvatarSize,
    height: kAvatarSize,
    interpolation: img.Interpolation.cubic,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

/// Afmetingen na EXIF-oriëntatie, zodat het kader klopt met wat je ziet.
Future<Size?> _orientedSize(Uint8List bytes) => compute((Uint8List b) {
  final decoded = img.decodeImage(b);
  if (decoded == null) return null;
  final o = img.bakeOrientation(decoded);
  return Size(o.width.toDouble(), o.height.toDouble());
}, bytes);

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final _transform = TransformationController();
  Size? _imageSize;
  double? _viewport;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _orientedSize(widget.bytes).then((size) {
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _failed = size == null;
      });
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Start gecentreerd: het midden van de foto in het midden van het kader.
  void _center(double viewport, Size child) {
    if (_viewport == viewport) return;
    _viewport = viewport;
    _transform.value = Matrix4.translationValues(
      -(child.width - viewport) / 2,
      -(child.height - viewport) / 2,
      0,
    );
  }

  Future<void> _use() async {
    final size = _imageSize;
    final viewport = _viewport;
    if (size == null || viewport == null) return;
    setState(() => _saving = true);
    final rect = visibleImageRect(
      imageSize: size,
      viewport: viewport,
      transform: _transform.value,
    );
    final result = await cropAndEncode(widget.bytes, rect);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return Scaffold(
      appBar: AppBar(
        title: Text('Foto uitsnijden', style: AppText.bodyStrong),
        actions: [
          TextButton(
            onPressed: size == null || _saving ? null : _use,
            child: const Text('Gebruiken'),
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Deze afbeelding kan niet worden gelezen. Kies een andere foto.',
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : size == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: AppSpace.lg),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final viewport = math.min(
                        constraints.maxWidth - 2 * AppSpace.gutter,
                        420.0,
                      );
                      final base =
                          viewport / math.min(size.width, size.height);
                      final child = Size(
                        size.width * base,
                        size.height * base,
                      );
                      _center(viewport, child);
                      return SizedBox(
                        width: viewport,
                        height: viewport,
                        child: Stack(
                          children: [
                            ClipRect(
                              child: InteractiveViewer(
                                transformationController: _transform,
                                constrained: false,
                                minScale: 1,
                                maxScale: 6,
                                boundaryMargin: EdgeInsets.zero,
                                child: SizedBox(
                                  width: child.width,
                                  height: child.height,
                                  child: Image.memory(
                                    widget.bytes,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ),
                            const IgnorePointer(
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _CircleMaskPainter(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.gutter,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.pinch_outlined,
                          size: 18,
                          color: AppColor.inkFaint,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Knijp om in te zoomen, sleep om te verschuiven.',
                            style: AppText.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.gutter),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () {
                                    _viewport = null;
                                    setState(() {});
                                  },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: const Text('Herstel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _saving ? null : _use,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Gebruiken'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Donkert alles buiten de cirkel en tekent een dunne ijsblauwe rand —
/// zo zie je precies wat er straks in het profielrondje staat.
class _CircleMaskPainter extends CustomPainter {
  const _CircleMaskPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect.deflate(1));
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      circle,
    );
    canvas.drawPath(mask, Paint()..color = AppColor.bg.withValues(alpha: .72));
    canvas.drawPath(
      circle,
      Paint()
        ..color = AppColor.ice
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter oldDelegate) => false;
}
