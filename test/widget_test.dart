// Doorloopt de belangrijkste flows met een geseede store (zonder Supabase).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/sparring_timer.dart';
import 'package:kinetic/main.dart';
import 'package:kinetic/models/combination.dart';
import 'package:kinetic/models/competition.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/models/live_training.dart';
import 'package:kinetic/models/technique_system.dart';
import 'package:kinetic/screens/techniques/system_editor_screen.dart';
import 'package:kinetic/screens/techniques/technique_ui.dart';
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
    expect(find.text('COMBAT SAMBO OPEN'), findsOneWidget);
    expect(find.text('Nog 18 dagen'), findsOneWidget);
    expect(find.textContaining('78.4 kg'), findsOneWidget);
    expect(find.textContaining('-1.4 kg target'), findsOneWidget);
    expect(find.text('6.5'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Training starten'), 200, scrollable: vertical);
    await tester.scrollUntilVisible(find.text('Tik voor +250ml'), 200, scrollable: vertical);
    expect(find.text('3.2 L'), findsOneWidget);

    await tester.ensureVisible(find.text('Tik voor +250ml'));
    await settle(tester);
    await tester.tap(find.text('Tik voor +250ml'));
    await settle(tester);
    expect(store.waterMlToday, 3450);
    expect(find.text('3.45 L'), findsOneWidget);
  });

  testWidgets('5-tabs navigatie en de barometer', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Eten'));
    await settle(tester);
    expect(find.text('Eet Logboek'), findsOneWidget);
    expect(store.carbsToday, 165);
    expect(find.text('Resterend'), findsOneWidget);
    expect(find.text('45g'), findsOneWidget);

    // Snelle-carbs-knoppen zijn weg; loggen gaat via de maaltijd-sheet.
    expect(find.text('+15g Dextrose'), findsNothing);
    expect(find.text('+ Maaltijd of correctie toevoegen'), findsOneWidget);

    await tester.tap(find.text('Technieken'));
    await settle(tester);
    expect(find.text('Striking'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Harai Goshi'), 300, scrollable: vertical);
    // Accordeon: Striking openen klapt Throws dicht.
    expect(find.text('Liver Punch Setup'), findsNothing);
    final strikingHeader = find.descendant(of: find.byType(GroupHeader), matching: find.text('Striking'));
    await tester.scrollUntilVisible(strikingHeader, 300, scrollable: vertical);
    // Bovenaan in beeld zetten, zodat de tik niet op de navigatiebalk valt.
    await tester.ensureVisible(strikingHeader);
    await settle(tester);
    await tester.tap(strikingHeader);
    await settle(tester);
    expect(find.text('Liver hook'), findsOneWidget);
    expect(find.text('Harai Goshi'), findsNothing);

    await tester.tap(find.text('Training'));
    await settle(tester);
    expect(find.text('Sessie Historie'), findsOneWidget);
  });

  testWidgets('centrale + opent het actiemenu', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Snelle actie'));
    await settle(tester);
    expect(find.text('Start training'), findsOneWidget);
    expect(find.text('Maaltijd of correctie'), findsOneWidget);
    expect(find.text('Sensor Kalibratie'), findsOneWidget);
  });

  testWidgets('maaltijd-modal voorspelt impact en slaat op', (tester) async {
    await pumpApp(tester);
    store.requestMealSheet();
    await settle(tester);
    expect(find.text('Maaltijd of correctie'), findsOneWidget);
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

  testWidgets('maaltijd met presets: −/+ werkt omschrijving en koolhydraten bij', (tester) async {
    await pumpApp(tester);
    store.requestMealSheet();
    await settle(tester);
    expect(find.text('Maaltijd of correctie'), findsOneWidget);

    // Volledige lijst: alfabetisch.
    await tester.tap(find.text('Alle presets (3)'));
    await settle(tester);
    final names = tester.widgetList<Text>(find.text('Appel').hitTestable()).length;
    expect(names, 1);
    await tester.tap(find.bySemanticsLabel('Appel plus'));
    await tester.tap(find.bySemanticsLabel('Appel plus'));
    await tester.tap(find.bySemanticsLabel('Banaan plus'));
    await settle(tester);
    await tester.tap(find.text('Klaar'));
    await settle(tester);

    final desc = find.widgetWithText(TextField, 'Maaltijd / brandstof');
    expect(tester.widget<TextField>(desc).controller!.text, '2 Appels, 1 Banaan');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Koolh. (g)')).controller!.text, '55');

    // Eigen tekst blijft vooraan; min haalt de preset weer weg.
    tester.widget<TextField>(desc).controller!.text = 'Yoghurt, 2 Appels, 1 Banaan';
    await tester.tap(find.bySemanticsLabel('Banaan min'));
    await settle(tester);
    expect(tester.widget<TextField>(desc).controller!.text, 'Yoghurt, 2 Appels');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Koolh. (g)')).controller!.text, '32');

    await tester.ensureVisible(find.text('Opslaan in Dagoverzicht'));
    await tester.tap(find.text('Opslaan in Dagoverzicht'));
    await settle(tester);
    expect(store.todayEntries.first.description, 'Yoghurt, 2 Appels');
    expect(store.todayEntries.first.presetCounts, {'Appel': 2});
  });

  testWidgets('training: klok start op de begintijd, sparren met doelen en opslaan', (tester) async {
    await pumpApp(tester);
    await tester.scrollUntilVisible(find.text('Training starten'), 200, scrollable: vertical);
    await settle(tester);
    await tester.tap(find.text('Training starten'));
    await settle(tester);
    // Training is geen sparren: geen format, wel begin- en eindtijd.
    expect(find.text('FORMAT'), findsNothing);
    expect(find.text('TIJDEN'), findsOneWidget);
    expect(find.text('18:30'), findsWidgets);
    expect(find.text('19:45'), findsOneWidget);
    await tester.ensureVisible(find.text('Start training'));
    await tester.tap(find.text('Start training'));
    await settle(tester);

    // 17:50: de training is open, maar de klok telt af naar 18:30.
    expect(store.training!.discipline, 'Combat Sambo');
    expect(find.text('BEGINT OVER'), findsOneWidget);
    expect(find.text('START OM 18:30'), findsOneWidget);
    clock = clock.add(const Duration(minutes: 41));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('TRAININGSTIJD'), findsOneWidget);
    expect(find.text('Voeding'), findsOneWidget);

    // Warming-up: standaard 15 min, met −/+ aan te passen.
    await tester.tap(find.text('Warming-up'));
    await settle(tester);
    expect(find.text('15 min'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Warming-up plus'));
    await settle(tester);
    await tester.tap(find.text('Warming-up toevoegen').last);
    await settle(tester);
    expect(store.training!.warmups.single.minutes, 20);

    // Sparren instellen: doel voor het geheel en voor ronde 1.
    await tester.tap(find.text('Sparren'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Doel voor het sparren (optioneel)'), 'Zet minimaal 5 worpen in');
    await tester.enterText(find.widgetWithText(TextField, 'Doel ronde 1 (optioneel)'), 'Zet Harai Goshi in');
    await tester.ensureVisible(find.text('Start sparren'));
    await tester.tap(find.text('Start sparren'));
    await settle(tester);
    expect(store.isSparringActive, isTrue);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Zet Harai Goshi in'), findsOneWidget);
    expect(find.text('Zet minimaal 5 worpen in'), findsOneWidget);

    // Rondedoel afvinken.
    await tester.tap(find.text('Zet Harai Goshi in'));
    await settle(tester);
    expect(store.training!.activeSparring!.rounds.first.goalDone, isTrue);

    // Tellers alleen tijdens het sparren.
    final geslaagd = find.text('Geslaagd');
    await tester.ensureVisible(geslaagd);
    await tester.tap(geslaagd);
    await tester.tap(geslaagd);
    await tester.longPress(geslaagd);
    await settle(tester);
    expect(store.sessionCounts['harai-goshi']!.success, 1);

    await tester.tap(find.text('VOLGENDE'));
    await settle(tester);
    expect(store.sparring!.phase, SparringPhase.rest);
    expect(find.text('HERSTELTIJD'), findsOneWidget);
    await tester.tap(find.text('+30s Rust'));
    await settle(tester);
    expect(store.roundSecondsRemaining, 90);
    await tester.tap(find.textContaining('KLAAR VOOR RONDE 2'));
    await settle(tester);
    expect(store.sparring!.round, 2);

    // Sparren stoppen: de training loopt door.
    await tester.tap(find.text('STOP'));
    await settle(tester);
    await tester.tap(find.text('Stop sparren'));
    await settle(tester);
    expect(store.isSparringActive, isFalse);
    expect(store.isTrainingActive, isTrue);
    expect(find.text('Geslaagd'), findsNothing);

    await tester.tap(find.byTooltip('Training afronden'));
    await settle(tester);
    await tester.tap(find.text('Opslaan'));
    await settle(tester);
    expect(store.training, isNull);
    final saved = store.sessions.first;
    expect(saved.title, 'Combat Sambo');
    expect(saved.blocks.where((b) => b['kind'] == 'warmup').single['minutes'], 20);
    final spar = saved.blocks.firstWhere((b) => b['kind'] == 'sparring');
    expect(spar['goal'], 'Zet minimaal 5 worpen in');
    expect(spar['rounds'], 2);
    expect((spar['round_goals'] as List).first, {'goal': 'Zet Harai Goshi in', 'done': true});
    final tech = saved.blocks.firstWhere((b) => b['name'] == 'Harai Goshi');
    expect((tech['counts'] as Map)['success'], 1);
  });

  testWidgets('voeding tijdens training: presets loggen, aanpassen en verwijderen', (tester) async {
    await pumpApp(tester);
    store.startTraining(discipline: 'BJJ', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/live-session');
    await settle(tester);
    expect(find.text('+15g'), findsNothing);

    await tester.tap(find.text('Voeding'));
    await settle(tester);
    // Trainingspresets, niet de maaltijdpresets.
    expect(find.text('Trainingspresets'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Alle presets (2)'));
    await settle(tester);
    expect(find.text('Appel'), findsNothing);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Dextro plus'));
    }
    await tester.tap(find.bySemanticsLabel('Sportdrank plus'));
    await settle(tester);
    await tester.tap(find.text('Klaar'));
    await settle(tester);
    await tester.ensureVisible(find.textContaining('Loggen •'));
    await tester.tap(find.textContaining('Loggen •'));
    await settle(tester);

    final logs = store.training!.nutrition;
    expect(logs.map((n) => (n.label, n.count, n.carbs)), containsAll([("4 Dextro's", 4, 12.0), ('1 Sportdrank', 1, 30.0)]));
    expect(logs.every((n) => n.at == clock), isTrue);

    final dextro = logs.firstWhere((n) => n.preset == 'Dextro');
    store.updateNutrition(dextro.id, count: 3);
    expect(store.training!.nutrition.firstWhere((n) => n.id == dextro.id).label, "3 Dextro's");
    store.deleteNutrition(dextro.id);
    expect(store.training!.nutrition.single.label, '1 Sportdrank');

    // Na de training blijft het aanpasbaar.
    final saved = await store.finishTraining();
    expect(saved!.nutrition.single.label, '1 Sportdrank');
    final id = saved.nutrition.single.id;
    expect(await store.updateSessionNutrition(saved.id, id: id, count: 2), isTrue);
    expect(store.sessions.first.nutrition.single.label, '2 Sportdranken');
    expect(await store.updateSessionNutrition(saved.id, id: id, delete: true), isTrue);
    expect(store.sessions.first.nutrition, isEmpty);
    await settle(tester);
  });

  testWidgets('tijdens sparren terug naar de training en technieken weghalen', (tester) async {
    await pumpApp(tester);
    store.startTraining(discipline: 'Sport Sambo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.startSparringBlock(rounds: const [SparRound(), SparRound()]);
    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/live-session');
    await settle(tester);
    expect(find.text('Geslaagd'), findsWidgets);

    // Naar de trainingspagina: sparren blijft lopen als balk bovenaan.
    await tester.tap(find.text('Training'));
    await settle(tester);
    expect(find.text('Geslaagd'), findsNothing);
    expect(find.textContaining('Sparren • ronde 1/2'), findsOneWidget);
    expect(find.text('Warming-up'), findsOneWidget);
    expect(store.isSparringActive, isTrue);

    // Pauze stopt alleen de rondeklok; de trainingstijd loopt door.
    store.toggleSparringTimer();
    clock = clock.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(store.training!.elapsedSeconds(clock), 180);
    expect(store.roundSecondsRemaining, 300);

    // Techniek wegvegen, en ongedaan maken.
    store.setTechniqueLog('liver-punch', const TechniqueLog(reps: 12, note: 'goed'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Liver Punch Setup'), 200, scrollable: vertical);
    await tester.drag(find.text('Liver Punch Setup'), const Offset(-500, 0));
    await settle(tester);
    expect(store.sessionTechniqueIds.contains('liver-punch'), isFalse);
    expect(store.training!.techniqueLogs.containsKey('liver-punch'), isFalse);
    await tester.tap(find.text('Ongedaan'));
    await settle(tester);
    expect(store.techniqueLog('liver-punch').reps, 12);

    // Terug naar de spar-weergave via de balk.
    await tester.scrollUntilVisible(find.textContaining('Sparren • ronde'), -200, scrollable: vertical);
    await tester.tap(find.textContaining('Sparren • ronde'));
    await settle(tester);
    expect(find.text('Geslaagd'), findsWidgets);
    await store.finishTraining(save: false);
    await settle(tester);
  });

  testWidgets('sparren aanpassen tijdens en na het sparren, focus weghalen, presets op slot', (tester) async {
    await pumpApp(tester);
    store.startTraining(discipline: 'Sport Sambo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.startSparringBlock(rounds: const [SparRound(), SparRound(), SparRound()]);
    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/live-session');
    await settle(tester);

    // Lopend: ronde 1 van 5:00 naar 4:00 haalt een minuut van de klok af.
    clock = clock.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(store.roundSecondsRemaining, 270);
    await tester.tap(find.text('Rondes aanpassen'));
    await settle(tester);
    expect(find.text('Ronde 1 • nu'), findsOneWidget);
    expect(find.byTooltip('Ronde 1 verwijderen'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Ronde 1 werk min').first);
    await tester.tap(find.bySemanticsLabel('Ronde 1 werk min').first);
    await tester.tap(find.byTooltip('Ronde 3 verwijderen'));
    await settle(tester);
    await tester.ensureVisible(find.text('Opslaan'));
    await tester.tap(find.text('Opslaan'));
    await settle(tester);
    expect(store.roundSecondsRemaining, 210);
    expect(store.sparring!.config.rounds, 2);
    expect(store.training!.activeSparring!.rounds.length, 2);

    // Focus-techniek weghalen met het kruisje (Harai Goshi staat in focus).
    store.finishSparringBlock();
    await settle(tester);
    await tester.scrollUntilVisible(find.byTooltip('Harai Goshi uit de training halen'), 200, scrollable: vertical);
    await tester.tap(find.byTooltip('Harai Goshi uit de training halen'));
    await settle(tester);
    expect(store.sessionTechniqueIds.contains('harai-goshi'), isFalse);

    // Gelogd sparblok: gedane rondes aanpassen en daarna verwijderen.
    final id = store.training!.sparrings.single.id;
    expect(store.training!.sparrings.single.roundsDone, 1);
    store.updateSparringBlock(id, rounds: store.training!.sparrings.single.rounds, goal: 'Afstand houden', roundsDone: 2);
    expect(store.training!.sparrings.single.roundsDone, 2);
    expect(store.training!.sparrings.single.goal, 'Afstand houden');
    store.removeSparringBlock(id);
    expect(store.training!.sparrings, isEmpty);

    // Trainingspresets: tellen ja, bewerken/maken niet (dat kan in Instellingen).
    await tester.ensureVisible(find.text('Voeding'));
    await settle(tester);
    await tester.tap(find.text('Voeding'));
    await settle(tester);
    await tester.tap(find.text('Alle presets (2)'));
    await settle(tester);
    expect(find.text('Nieuw'), findsNothing);
    expect(find.byTooltip('Dextro bewerken'), findsNothing);
    await tester.tap(find.text('Klaar'));
    await settle(tester);
    await store.finishTraining(save: false);
    await settle(tester);
  });

  testWidgets('opnieuw sparren en hartslag standaard verborgen', (tester) async {
    await pumpApp(tester);
    store.startTraining(discipline: 'Judo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.startSparringBlock(rounds: const [SparRound(workSeconds: 120, goal: 'Grip winnen'), SparRound()], goal: 'Afstand');
    store.toggleRoundGoal(store.training!.activeSparring!.id, 0);
    store.finishSparringBlock();
    store.repeatSparringBlock(store.training!.sparrings.single.id);
    final blocks = store.training!.sparrings;
    expect(blocks.length, 2);
    expect(blocks.last.goal, 'Afstand');
    expect(blocks.last.rounds.first.goal, 'Grip winnen');
    expect(blocks.last.rounds.first.goalDone, isFalse);
    expect(store.roundSecondsRemaining, 120);

    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/live-session');
    await settle(tester);
    expect(find.text('POLAR H10'), findsNothing);
    await store.setShowHeartRate(true);
    await settle(tester);
    expect(find.text('POLAR H10'), findsOneWidget);
    await store.finishTraining(save: false);
    await settle(tester);
  });

  testWidgets("technieken: video's, notities, beoordeling en combinaties", (tester) async {
    await pumpApp(tester);

    // Video's: titel of "Video N".
    expect(await store.addTechniqueVideo('harai-goshi', 'https://youtu.be/abc', label: 'Gripping'), isTrue);
    expect(await store.addTechniqueVideo('harai-goshi', 'https://www.instagram.com/reel/xyz'), isTrue);
    final t = store.techniques.firstWhere((x) => x.id == 'harai-goshi');
    expect(t.videoUrls, hasLength(2));
    expect(store.videoTitle(t.videoUrls[0], 0), 'Gripping');
    expect(store.videoTitle(t.videoUrls[1], 1), 'Video 2');

    // Notities en beoordeling met wat ging goed / minder.
    await store.setTechniqueNotes('harai-goshi', 'Eerst kraag, dan mouw');
    await store.addTechniqueReview(
      'harai-goshi',
      TechniqueUpdate(at: clock, rating: 4, wentWell: 'Kuzushi', toImprove: 'Heupinzet te laat'),
    );
    final after = store.techniques.firstWhere((x) => x.id == 'harai-goshi');
    expect(after.description, 'Eerst kraag, dan mouw');
    expect(after.reviews.first.toImprove, 'Heupinzet te laat');
    expect(after.updates.last.toJson()['positions'][0]['went_well'], 'Kuzushi');

    // In de techniek-sheet: uitklapbare video's met titel.
    await tester.tap(find.text('Technieken'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Harai Goshi'), 200, scrollable: vertical);
    await tester.tap(find.text('Harai Goshi'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Gripping'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Video 2'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.textContaining('Heupinzet te laat'), findsOneWidget);
    Navigator.of(tester.element(find.text('Gripping'))).pop();
    await settle(tester);

    // Combinatie opslaan en tijdens een training met één tik loggen.
    final combo = await store.saveCombination(
      const Combination(id: '', name: 'Heupworp-ketting', techniques: ['Harai Goshi', 'O-soto-gari']),
    );
    expect(combo, isNotNull);
    store.startTraining(discipline: 'Judo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.logCombo(combo!.techniques, combinationId: combo.id);
    store.logCombo(combo.techniques, combinationId: combo.id);
    expect(store.training!.combos.single.count, 2);
    expect(store.training!.combos.single.label, 'Harai Goshi → O-soto-gari');
    await store.finishTraining(save: false);
  });

  testWidgets('hypo houdt de volgende ronde tegen', (tester) async {
    await pumpApp(tester, mmol: 3.6, trend: Trend.down);
    expect(find.textContaining('HYPO 3.6'), findsOneWidget);
    store.startTraining(discipline: 'Combat Sambo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.startSparringBlock(rounds: const [SparRound(), SparRound(), SparRound()]);
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
    await store.finishTraining(save: false);
    await settle(tester);
  });

  testWidgets('zonder rusttimer wacht de rust op een handmatige start', (tester) async {
    await pumpApp(tester);
    await store.setRestTimerEnabled(false);
    store.startTraining(discipline: 'Judo', startsAt: clock, endsAt: clock.add(const Duration(hours: 1)));
    store.startSparringBlock(rounds: const [SparRound(workSeconds: 120), SparRound(workSeconds: 180)]);
    store.advanceToRestPhase();
    await tester.pumpWidget(KineticApp(store: store));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/ronde-rust');
    await settle(tester);
    clock = clock.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(store.sparring!.phase, SparringPhase.rest);
    expect(find.text('RUST • GEEN TIMER'), findsOneWidget);
    expect(find.text('WACHT'), findsNothing);
    expect(find.text('+30s Rust'), findsNothing);
    await tester.tap(find.textContaining('KLAAR VOOR RONDE 2'));
    await settle(tester);
    // Eigen duur per ronde: ronde 2 duurt 3 minuten.
    expect(store.roundSecondsRemaining, 180);
    await store.finishTraining(save: false);
    await settle(tester);
  });

  testWidgets('wedstrijd plannen, aanpassen en verwijderen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Inwegen & Prep'));
    await settle(tester);
    final add = find.widgetWithText(TextButton, 'Wedstrijd');
    await tester.scrollUntilVisible(add, 300, scrollable: vertical);
    await tester.ensureVisible(add);
    await settle(tester);
    await tester.tap(add);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Naam'), 'Lichtstad Open');
    await tester.enterText(find.widgetWithText(TextField, 'Maximaal gewicht (kg)'), '82');
    await tester.ensureVisible(find.text('Wedstrijd plannen').last);
    await tester.tap(find.text('Wedstrijd plannen').last);
    await settle(tester);
    final added = store.allCompetitions.firstWhere((c) => c.name == 'Lichtstad Open');
    expect(added.weightClass, '-82,0 kg');
    expect(added.weightLimitType, WeightLimitType.under);
    expect(added.startsAt.isAfter(clock), isTrue);

    // Aanpassen: minimumklasse +88.
    final edited = await store.saveCompetition(
      added.copyWith(weightLimitType: WeightLimitType.over, weightLimitKg: 88, weightClass: '+88.0 kg'),
    );
    expect(edited!.isMinimumClass, isTrue);
    expect(store.allCompetitions.where((c) => c.name == 'Lichtstad Open').single.weightLimitKg, 88);

    expect(await store.deleteCompetition(edited), isTrue);
    expect(store.allCompetitions.any((c) => c.name == 'Lichtstad Open'), isFalse);
    expect(store.competitions.any((c) => c.name == 'Lichtstad Open'), isFalse);
  });

  testWidgets('systemen: transities op pijlen en technieken aanvinken', (tester) async {
    await pumpApp(tester);
    final sys = store.systems.single;
    await store.saveSystem(sys.withEdgeLabel(const SystemEdge(from: 'n1', to: 'n2'), 'Tegenstander leunt naar voren'));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(builder: (_) => const SystemEditorScreen(systemId: 'sys1')),
    );
    await settle(tester);

    // Transitie staat als label op de pijl en is aan te tikken.
    expect(find.text('Tegenstander leunt naar voren'), findsWidgets);
    await tester.tap(find.text('Tegenstander leunt naar voren').first);
    await settle(tester);
    expect(find.text('Transitie'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Wat gebeurt er?'), 'Kraag-mouw grip gewonnen');
    await tester.tap(find.text('Opslaan'));
    await settle(tester);
    expect(store.systems.single.edges.firstWhere((e) => e.to == 'n2').label, 'Kraag-mouw grip gewonnen');

    // Technieken aanvinken: rondje → vinkje = stap in het systeem.
    await tester.dragUntilVisible(find.text('Technieken kiezen'), find.byType(ListView).last, const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.text('Technieken kiezen'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Liver');
    await settle(tester);
    await tester.tap(find.text('Liver Punch Setup'));
    await settle(tester);
    expect(store.systems.single.nodeForTechnique('liver-punch'), isNotNull);
    expect(store.systems.single.nodes, hasLength(5));
    // De sheet ligt bovenop de graaf (waar de nieuwe stap nu ook staat).
    await tester.tap(find.text('Liver Punch Setup').last);
    await settle(tester);
    expect(store.systems.single.nodeForTechnique('liver-punch'), isNull);
    expect(store.systems.single.nodes, hasLength(4));
  });

  testWidgets('dagdoel voeding en vocht aan/uit', (tester) async {
    await pumpApp(tester);
    await tester.scrollUntilVisible(find.text('Tik voor +250ml'), 200, scrollable: vertical);
    expect(find.text('165/210g'), findsOneWidget);

    await store.setWaterEnabled(false);
    await store.setNutritionGoalsEnabled(false);
    await settle(tester);
    expect(find.text('Tik voor +250ml'), findsNothing);
    expect(find.text('165g'), findsOneWidget);

    await tester.tap(find.text('Eten'));
    await settle(tester);
    expect(find.text('Resterend'), findsNothing);
    await tester.tap(find.text('Dagdoel aanzetten'));
    await settle(tester);
    expect(store.nutritionGoalsEnabled, isTrue);
    expect(find.text('Resterend'), findsOneWidget);
  });

  testWidgets('inwegen met ±0.1 kg en registreren', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Inwegen & Prep'));
    await settle(tester);
    expect(find.text('Wedstrijden & Gewicht'), findsOneWidget);
    expect(find.text('Nog af te vallen: -1.4 kg naar doel'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.remove));
    await settle(tester);
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
