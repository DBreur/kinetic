// design_shots_test.dart: rendert de hoofdschermen naar PNG (zie
// shots_support.dart voor de opties). Elk deelgebied kan een eigen
// tool/shots_<gebied>_test.dart hebben met dezelfde helpers.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/live_training.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:kinetic/widgets/sheets.dart';

import 'shots_support.dart';

void main() {
  setUpAll(loadShotFonts);

  shotTest('vandaag', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1700);
    await s.shot('01_vandaag');
  });

  shotTest('training', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1700);
    await s.tab(KTab.training);
    await s.shot('02_training');
  });

  shotTest('technieken', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1700);
    await s.tab(KTab.technieken);
    await s.shot('03_technieken');
  });

  shotTest('eten', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500);
    await s.tab(KTab.eten);
    await s.shot('04_eten');
  });

  shotTest('meal', (s, dark) async {
    await s.pumpApp(dark: dark);
    await s.tab(KTab.eten);
    s.store.requestMealSheet();
    await s.settle();
    await s.shot('05_maaltijd_modal');
  });

  shotTest('plus', (s, dark) async {
    await s.pumpApp(dark: dark);
    showQuickActions(s.navigator.context);
    await s.shot('06_quick_actions');
  });

  Future<void> startLive(ShotSession s) async {
    final store = s.store;
    store.startTraining(discipline: 'Combat Sambo', startsAt: store.now(), endsAt: store.now().add(const Duration(minutes: 90)));
    store.startSparringBlock(rounds: List.filled(5, const SparRound()), goal: 'Zet minimaal 5 worpen in');
    // Ronde 3 / 5 op 03:18, zoals in de spec.
    store.advanceToRestPhase();
    store.startNextRound();
    store.advanceToRestPhase();
    store.startNextRound();
    s.clock = s.clock.add(const Duration(seconds: 102));
    void tap(String id, TechniqueStat stat, int n) {
      for (var i = 0; i < n; i++) {
        store.incrementTechniqueStat(id, stat);
      }
    }

    tap('harai-goshi', TechniqueStat.success, 4);
    tap('harai-goshi', TechniqueStat.attempt, 7);
    tap('harai-goshi', TechniqueStat.countered, 1);
    tap('liver-punch', TechniqueStat.success, 3);
    tap('liver-punch', TechniqueStat.attempt, 5);
    tap('liver-punch', TechniqueStat.countered, 2);
  }

  shotTest('live', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1400);
    await startLive(s);
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('07_live_session');
  });

  shotTest('rust', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1600, mmol: 6.7, trend: Trend.slightUp, hr: 137);
    await startLive(s);
    s.store.advanceToRestPhase();
    s.clock = s.clock.add(const Duration(seconds: 15));
    s.navigator.pushNamed('/ronde-rust');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('08_ronde_rust');
  });

  shotTest('hypo', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1100, mmol: 3.7, trend: Trend.down, hr: 141);
    await startLive(s);
    s.store.advanceToRestPhase();
    s.clock = s.clock.add(const Duration(seconds: 61));
    s.navigator.pushNamed('/ronde-rust');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('09_ronde_rust_hypo');
  });

  shotTest('comp', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2400);
    await s.push('/competitions');
    await s.shot('10_competitions');
  });

  shotTest('export', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2200);
    await s.push('/telemetrie-export');
    await s.shot('11_telemetrie_export');
  });
}
