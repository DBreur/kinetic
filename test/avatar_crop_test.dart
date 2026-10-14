// avatar_crop_test.dart — welk stuk van de foto is zichtbaar in het
// uitsnijkader, en levert uitsnijden precies dat stuk op?

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:kinetic/screens/avatar_crop_screen.dart';

void main() {
  const viewport = 300.0;

  group('visibleImageRect', () {
    test('liggende foto, gecentreerd zonder zoom: middelste vierkant', () {
      // 2000×1000 → cover-schaal 0,3: kind is 600×300, startverschuiving -150.
      final r = visibleImageRect(
        imageSize: const Size(2000, 1000),
        viewport: viewport,
        transform: Matrix4.translationValues(-150, 0, 0),
      );
      expect(r.left, closeTo(500, .001));
      expect(r.top, closeTo(0, .001));
      expect(r.width, closeTo(1000, .001));
      expect(r.height, r.width);
    });

    test('2× inzoomen op het midden: half zo groot vierkant', () {
      // Staande foto 1000×2000, kind 300×600. Zoom 2× rond het midden van
      // het kader (150,150) bovenop de centrering (-150 verticaal).
      final transform = Matrix4.identity()
        ..translateByDouble(150, 150, 0, 1)
        ..scaleByDouble(2, 2, 1, 1)
        ..translateByDouble(-150, -150, 0, 1)
        ..translateByDouble(0, -150, 0, 1);
      final r = visibleImageRect(
        imageSize: const Size(1000, 2000),
        viewport: viewport,
        transform: transform,
      );
      expect(r.width, closeTo(500, .001));
      expect(r.center.dx, closeTo(500, .001));
      expect(r.center.dy, closeTo(1000, .001));
    });

    test('verschoven tot buiten de foto: blijft binnen de randen', () {
      final r = visibleImageRect(
        imageSize: const Size(1000, 1000),
        viewport: viewport,
        transform: Matrix4.translationValues(80, 80, 0),
      );
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, 1000);
    });
  });

  test('cropAndEncode: 512×512 JPEG van precies het gekozen stuk', () async {
    // Links rood, rechts blauw.
    final source = img.Image(width: 400, height: 200);
    img.fill(source, color: img.ColorRgb8(220, 30, 30));
    img.fillRect(
      source,
      x1: 200,
      y1: 0,
      x2: 399,
      y2: 199,
      color: img.ColorRgb8(30, 30, 220),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));

    final out = await cropAndEncode(
      bytes,
      const Rect.fromLTWH(200, 0, 200, 200),
    );
    expect(out, isNotNull);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, kAvatarSize);
    expect(decoded.height, kAvatarSize);
    final p = decoded.getPixel(256, 256);
    expect(p.b, greaterThan(150), reason: 'rechterhelft (blauw) uitgesneden');
    expect(p.r, lessThan(100));
  });
}
