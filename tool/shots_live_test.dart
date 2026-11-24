// shots_live_test.dart: rendert de live sessie en de ronde rust naar PNG
// (zie shots_support.dart voor de opties).
//
//   flutter test tool/shots_live_test.dart --dart-define=SHOTS_DIR=<map> --dart-define=THEME=both

// ignore_for_file: use_build_context_synchronously

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/technique.dart';

import '../test/support/seed_data.dart';
import 'shots_support.dart';

void main() {
  setUpAll(loadShotFonts);

  /// Ronde 3 / 5 op 03:18, 12 minuten na de start, met tellers.
  /// [workBpm] is de hartslag aan het einde van de ronde (voor het herstel).
  Future<void> startLive(ShotSession s, {int? workBpm}) async {
    final store = s.store;
    final end = s.clock;
    s.clock = end.subtract(const Duration(minutes: 12));
    store.startSparring(title: 'Combat Sambo');
    store.advanceToRestPhase();
    store.startNextRound();
    store.advanceToRestPhase();
    s.clock = end.subtract(const Duration(seconds: 102));
    store.startNextRound();
    s.clock = end;
    if (workBpm != null) (store.heartRate as FixedHeartRate).bpm = workBpm;
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
    await s.pumpApp(dark: dark, height: 1800, mmol: 6.8, trend: Trend.slightUp);
    await startLive(s);
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('live_session_full');
  });

  shotTest('live_fold', (s, dark) async {
    await s.pumpApp(dark: dark, mmol: 6.8, trend: Trend.slightUp);
    await startLive(s);
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('live_session_fold');
  });

  shotTest('live_paused', (s, dark) async {
    await s.pumpApp(dark: dark, mmol: 5.6, trend: Trend.slightDown);
    await startLive(s);
    s.store.toggleSparringTimer();
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('live_session_paused');
  });

  shotTest('picker', (s, dark) async {
    await s.pumpApp(dark: dark, mmol: 6.8, trend: Trend.slightUp);
    await startLive(s);
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.settle();
    final row = find.text('Focus wisselen of toevoegen');
    await s.tester.ensureVisible(row);
    await s.settle();
    await s.tester.tap(row);
    await s.settle();
    await s.shot('live_session_picker');
  });

  shotTest('rust', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2200, mmol: 6.7, trend: Trend.slightUp, hr: 167);
    await startLive(s);
    s.store.advanceToRestPhase();
    (s.store.heartRate as FixedHeartRate).bpm = 137;
    s.clock = s.clock.add(const Duration(seconds: 15));
    s.navigator.pushNamed('/ronde-rust');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('ronde_rust_full');
  });

  shotTest('rust_fold', (s, dark) async {
    await s.pumpApp(dark: dark, mmol: 6.7, trend: Trend.slightUp, hr: 167);
    await startLive(s);
    s.store.advanceToRestPhase();
    (s.store.heartRate as FixedHeartRate).bpm = 137;
    s.clock = s.clock.add(const Duration(seconds: 15));
    s.navigator.pushNamed('/ronde-rust');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('ronde_rust_fold');
  });

  shotTest('hypo', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500, mmol: 3.7, trend: Trend.down, hr: 171);
    await startLive(s);
    s.store.advanceToRestPhase();
    (s.store.heartRate as FixedHeartRate).bpm = 141;
    s.clock = s.clock.add(const Duration(seconds: 61));
    s.navigator.pushNamed('/ronde-rust');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('ronde_rust_hypo');
  });

  shotTest('live_hypo', (s, dark) async {
    await s.pumpApp(dark: dark, mmol: 3.7, trend: Trend.down);
    await startLive(s);
    s.navigator.pushNamed('/live-session');
    await s.tester.pump(const Duration(seconds: 1));
    await s.shot('live_session_hypo');
  });
}
