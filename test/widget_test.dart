// Doorloopt de belangrijkste flows met een geseede store (zonder Supabase).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/sparring_timer.dart';
import 'package:kinetic/main.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:material_ui/material_ui.dart';

import 'support/seed_data.dart';

/// De verticale lijst van het zichtbare scherm (niet de horizontale chiprij).
final vertical = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

void main() {
  late DateTime clock;
  late KineticStore store;

  Future<void> pumpApp(WidgetTester tester, {double mmol = 6.5, Trend trend = Trend.flat}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    clock = seedNow;
    store = seededStore(clock: () => clock, latestMmol: mmol, trend: trend);
    addTearDown(store.dispose);
    await tester.pumpWidget(KineticApp(store: store));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    // Live-schermen hebben oneindige animaties; daarom vaste stappen.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('Vandaag toont fight prep, Dexcom en de sparring-CTA', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Combat Sambo Open • Nog 18 dagen'), findsOneWidget);
    expect(find.textContaining('78.4 kg (-1.4 kg target)'), findsOneWidget);
    expect(find.text('Start Live Sparring'), findsOneWidget);
    expect(find.text('6.5'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Tik voor +250ml'), 200, scrollable: vertical);
    expect(find.text('3.2L'), findsOneWidget);

    await tester.ensureVisible(find.text('Tik voor +250ml'));
    await settle(tester);
    await tester.tap(find.text('Tik voor +250ml'));
    await settle(tester);
    expect(store.waterMlToday, 3450);
    expect(find.text('3.45L'), findsOneWidget);
  });

  testWidgets('5-tabs navigatie en carb-preset werkt de barometer bij', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Eten'));
    await settle(tester);
    expect(find.text('Eet Logboek'), findsOneWidget);
    expect(store.carbsToday, 165);
    expect(find.text('45g resterend'), findsOneWidget);

    await tester.tap(find.text('+15g Dextrose'));
    await settle(tester);
    expect(store.carbsToday, 180);
    expect(find.text('30g resterend'), findsOneWidget);

    await tester.tap(find.text('Technieken'));
    await settle(tester);
    expect(find.text('Strikes & Combinaties'), findsOneWidget);
    expect(find.text('Liver Punch Setup'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Harai Goshi'), 300, scrollable: vertical);
    expect(find.text('Throws & Takedowns'), findsOneWidget);

    await tester.tap(find.text('Training'));
    await settle(tester);
    expect(find.text('Training Historie'), findsOneWidget);
  });

  testWidgets('centrale + opent het actiemenu', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Snelle actie'));
    await settle(tester);
    expect(find.text('Start Sparring'), findsOneWidget);
    expect(find.text('Sensor Kalibratie'), findsOneWidget);
  });

  testWidgets('maaltijd-modal voorspelt impact en slaat op', (tester) async {
    await pumpApp(tester);
    store.requestMealSheet();
    await settle(tester);
    expect(find.text('Maaltijd of snelle carbs'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Maaltijd / brandstof'), 'Banaan + Dextrose Gel');
    await tester.enterText(find.widgetWithText(TextField, 'Koolh. (g)'), '30');
    await tester.tap(find.text('⚡ Vóór Training / Sparring (~30m)'));
    await settle(tester);
    expect(find.text('+1.2 tot +1.8 mmol/L'), findsOneWidget);
    await tester.ensureVisible(find.text('Opslaan in Dagoverzicht'));
    await tester.tap(find.text('Opslaan in Dagoverzicht'));
    await settle(tester);
    expect(store.carbsToday, 195);
    expect(store.todayEntries.first.description, 'Banaan + Dextrose Gel');
  });

  testWidgets('live sessie: tellers, rust, volgende ronde en opslaan', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Start Live Sparring'));
    await settle(tester);
    expect(find.text('Ronde 1 / 5'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('ACTIEVE SPARRING • LIVE'), findsOneWidget);

    // Tijd laten lopen: wandklok vooruit, ticker pakt het op.
    clock = clock.add(const Duration(seconds: 102));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('03:18'), findsOneWidget);

    final geslaagd = find.text('Geslaagd');
    await tester.ensureVisible(geslaagd);
    await tester.tap(geslaagd);
    await tester.tap(geslaagd);
    await tester.longPress(geslaagd);
    await settle(tester);
    expect(store.sessionCounts['harai-goshi']!.success, 1);
    expect(find.text('Clean Hit'), findsOneWidget);

    await tester.tap(find.text('VOLGENDE'));
    await settle(tester);
    expect(store.sparring!.phase, SparringPhase.rest);
    expect(find.text('HERSTELTIJD'), findsOneWidget);
    expect(find.text('Veilig voor R2'), findsWidgets);

    await tester.tap(find.text('+30s Rust'));
    await settle(tester);
    expect(store.roundSecondsRemaining, 90);

    await tester.tap(find.textContaining('KLAAR VOOR RONDE 2'));
    await settle(tester);
    expect(find.text('Ronde 2 / 5'), findsOneWidget);

    await tester.tap(find.byTooltip('Sessie afronden'));
    await settle(tester);
    await tester.tap(find.text('Opslaan'));
    await settle(tester);
    expect(store.sparring, isNull);
    expect(store.sessions.first.title, 'Live sparring');
    final tech = store.sessions.first.blocks.firstWhere((b) => b['name'] == 'Harai Goshi');
    expect((tech['counts'] as Map)['success'], 1);
    expect(find.text('Start Live Sparring'), findsOneWidget);
  });

  testWidgets('hypo houdt de volgende ronde tegen', (tester) async {
    await pumpApp(tester, mmol: 3.6, trend: Trend.down);
    expect(find.textContaining('HYPO 3.6'), findsOneWidget);
    store.startSparring();
    store.advanceToRestPhase();
    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/ronde-rust');
    await settle(tester);
    expect(find.text('Hypo: niet starten'), findsWidgets);

    // Rust loopt af: de ronde start NIET vanzelf.
    clock = clock.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(store.sparring!.phase, SparringPhase.rest);
    expect(find.text('WACHT'), findsOneWidget);

    await tester.tap(find.textContaining('KLAAR VOOR RONDE 2'));
    await settle(tester);
    expect(find.text('Toch starten'), findsOneWidget);
    await tester.tap(find.text('Nee, wachten'));
    await settle(tester);
    expect(store.sparring!.phase, SparringPhase.rest);
    await store.finishSparring(save: false);
    await settle(tester);
  });

  testWidgets('inwegen met ±0.1 kg en registreren', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Inwegen & Prep ⚖️'));
    await settle(tester);
    expect(find.text('Wedstrijden & Gewicht'), findsOneWidget);
    expect(find.text('Nog af te vallen: -1.4 kg naar doel'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await settle(tester);
    expect(find.text('Nog af te vallen: -1.2 kg naar doel'), findsOneWidget);
    await tester.tap(find.text('Gewicht Registreren'));
    await settle(tester);
    expect(store.weighIns.first.weightKg, 78.2);
    expect(store.currentWeightKg, 78.2);

    await tester.scrollUntilVisible(find.textContaining('Geen Extreme Uitdroging'), 200, scrollable: vertical);
    await tester.ensureVisible(find.textContaining('Geen Extreme Uitdroging'));
    await settle(tester);
    expect(store.checklistCount, 0);
    await tester.tap(find.textContaining('Geen Extreme Uitdroging'));
    await settle(tester);
    expect(store.checklistCount, 1);
    expect(store.checklistDone('hydration'), isTrue);
  });
}
