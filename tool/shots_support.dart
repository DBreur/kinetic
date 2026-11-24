// shots_support.dart: helpers om schermen met seed-data naar PNG te
// renderen (echte Inter-fonts + Material-icons), in licht en/of donker.
//
//   flutter test tool/<x>_test.dart --dart-define=SHOTS_DIR=<map>
//     [--dart-define=THEME=dark|light|both] [--dart-define=ONLY=a,b]

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/main.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/seed_data.dart';

const shotsDir = String.fromEnvironment('SHOTS_DIR', defaultValue: 'build/design_shots');
const _only = String.fromEnvironment('ONLY');
const _theme = String.fromEnvironment('THEME', defaultValue: 'dark');

bool wantShot(String name) => _only.isEmpty || _only.split(',').contains(name);

/// De thema's om te renderen (true = donker).
List<bool> get shotThemes => switch (_theme) {
  'light' => [false],
  'both' => [true, false],
  _ => [true],
};

Future<void> loadShotFonts() async {
  final inter = FontLoader('Inter');
  for (final w in [400, 500, 600, 700, 800, 900]) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await inter.load();
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final iconFile = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
  await icons.load();
}

/// Eén render-sessie: app met seed-data, aanpasbare klok, PNG-export.
class ShotSession {
  ShotSession(this.tester);
  final WidgetTester tester;
  final boundaryKey = GlobalKey();
  late DateTime clock;
  late KineticStore store;
  late bool dark;

  /// Telefoon van 390 breed; [height] groter voor lange scrollpagina's.
  /// [bottomInset] simuleert de Android-navigatiebalk (48dp).
  Future<void> pumpApp({
    required bool dark,
    double height = 844,
    double mmol = 6.5,
    Trend trend = Trend.flat,
    int hr = 164,
    double bottomInset = 48,
  }) async {
    this.dark = dark;
    tester.view.physicalSize = Size(390 * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(top: 24 * 3, bottom: bottomInset * 3);
    tester.view.viewPadding = FakeViewPadding(top: 24 * 3, bottom: bottomInset * 3);
    addTearDown(tester.view.reset);
    clock = seedNow;
    store = seededStore(clock: () => clock, latestMmol: mmol, trend: trend, heartRate: hr, darkMode: dark);
    addTearDown(store.dispose);
    await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: KineticApp(store: store)));
    await tester.pump();
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  NavigatorState get navigator => tester.state<NavigatorState>(find.byType(Navigator).first);

  Future<void> push(String route) async {
    navigator.pushNamed(route);
    await settle();
  }

  Future<void> tab(int index) async {
    store.selectTab(index);
    await settle();
  }

  /// Schrijft `<name>_dark.png` of `<name>_light.png`.
  Future<void> shot(String name) async {
    await settle();
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$shotsDir/${name}_${dark ? 'dark' : 'light'}.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }
}

/// Registreert een screenshot-test per thema.
void shotTest(String name, Future<void> Function(ShotSession s, bool dark) body) {
  for (final dark in shotThemes) {
    testWidgets('$name (${dark ? 'dark' : 'light'})', (tester) async {
      if (!wantShot(name)) return;
      await body(ShotSession(tester), dark);
    });
  }
}
