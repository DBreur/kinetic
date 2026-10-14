import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/widgets/kinetic.dart';

void main() {
  Future<double> shiftWith(
    WidgetTester tester,
    List<DisplayFeature> features,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(displayFeatures: features),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: KClock(avoidCutout: true),
          ),
        ),
      ),
    );
    await tester.pump(); // na de post-frame-controle
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(KClock),
        matching: find.byType(Transform),
      ),
    );
    return transform.transform.getTranslation().y;
  }

  testWidgets('klok onder een camera-uitsparing schuift eronder', (
    tester,
  ) async {
    final shift = await shiftWith(tester, const [
      DisplayFeature(
        bounds: Rect.fromLTWH(0, 0, 120, 30),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
    ]);
    expect(shift, greaterThanOrEqualTo(34)); // 30 + 4 marge
  });

  testWidgets('uitsparing ergens anders: klok blijft staan', (tester) async {
    final shift = await shiftWith(tester, const [
      DisplayFeature(
        bounds: Rect.fromLTWH(600, 0, 40, 30),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
    ]);
    expect(shift, 0);
  });

  testWidgets('geen uitsparing: klok blijft staan', (tester) async {
    expect(await shiftWith(tester, const []), 0);
  });
}
