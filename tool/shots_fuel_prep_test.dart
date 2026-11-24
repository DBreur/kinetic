// shots_fuel_prep_test.dart: rendert Eten, Fight Prep (/competitions),
// Telemetrie & Instellingen en het inlogscherm naar PNG (zie
// shots_support.dart voor de opties).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/main.dart';
import 'package:kinetic/models/competition.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/seed_data.dart';
import 'shots_support.dart';

void main() {
  setUpAll(loadShotFonts);

  shotTest('fp_eten', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2300);
    await s.tab(KTab.eten);
    await s.shot('fp_eten');
  });

  shotTest('fp_eten_top', (s, dark) async {
    await s.pumpApp(dark: dark);
    await s.tab(KTab.eten);
    await s.shot('fp_eten_top');
  });

  shotTest('fp_eten_empty', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1300);
    s.store.foodEntries = const [];
    await s.tab(KTab.eten);
    await s.shot('fp_eten_empty');
  });

  shotTest('fp_competitions', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2900);
    await s.push('/competitions');
    await s.shot('fp_competitions');
  });

  shotTest('fp_competitions_top', (s, dark) async {
    await s.pumpApp(dark: dark);
    await s.push('/competitions');
    await s.shot('fp_competitions_top');
  });

  // +88 kg-klasse: hier moet de atleet juist aankomen.
  shotTest('fp_competitions_over', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500);
    final now = s.clock;
    final over = Competition(
      id: 'c88',
      name: 'Open Zwaargewicht Cup',
      startsAt: DateTime(now.year, now.month, now.day).add(const Duration(days: 30, hours: 10)),
      discipline: 'sport',
      weightClass: '+88 kg',
      weightLimitType: WeightLimitType.over,
      weightLimitKg: 88.0,
    );
    s.store.competitions = [over];
    s.store.allCompetitions = [over, ...s.store.allCompetitions.where((c) => c.id != 'c1')];
    s.store.adjustWeight(0); // notify
    await s.push('/competitions');
    await s.shot('fp_competitions_over');
  });

  shotTest('fp_settings', (s, dark) async {
    await s.pumpApp(dark: dark, height: 3300);
    await s.push('/telemetrie-export');
    await s.shot('fp_settings');
  });

  shotTest('fp_settings_top', (s, dark) async {
    await s.pumpApp(dark: dark);
    await s.push('/telemetrie-export');
    await s.shot('fp_settings_top');
  });

  shotTest('fp_auth', (s, dark) async {
    final tester = s.tester;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 48 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 24 * 3, bottom: 48 * 3);
    addTearDown(tester.view.reset);
    s.dark = dark;
    final store = seededStore(darkMode: dark);
    store.state = BootState.signedOut;
    addTearDown(store.dispose);
    await tester.pumpWidget(RepaintBoundary(key: s.boundaryKey, child: KineticApp(store: store)));
    await tester.pump();
    await s.shot('fp_auth');
  });
}
