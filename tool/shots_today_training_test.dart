// shots_today_training_test.dart: Vandaag, Training, de start-sheet, de
// techniekkiezer en Training loggen naar PNG (zie shots_support.dart).

// ignore_for_file: use_build_context_synchronously

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/screens/log_training_screen.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:kinetic/widgets/start_training_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'shots_support.dart';

void main() {
  setUpAll(loadShotFonts);

  shotTest('tt_vandaag', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2300);
    await s.shot('tt_vandaag');
  });

  shotTest('tt_vandaag_fold', (s, dark) async {
    await s.pumpApp(dark: dark);
    await s.shot('tt_vandaag_fold');
  });

  shotTest('tt_vandaag_hypo', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500, mmol: 3.6, trend: Trend.down);
    await s.shot('tt_vandaag_hypo');
  });

  shotTest('tt_vandaag_active', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500);
    s.store.plannedTrainings = const [];
    s.store.startSparring(title: 'Combat Sambo');
    await s.settle();
    await s.shot('tt_vandaag_active');
    await s.store.finishSparring(save: false);
  });

  shotTest('tt_training', (s, dark) async {
    await s.pumpApp(dark: dark, height: 2600);
    await s.tab(KTab.training);
    await s.shot('tt_training');
  });

  shotTest('tt_training_month', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1300);
    await s.tab(KTab.training);
    await s.tester.tap(find.text('Maand'));
    await s.settle();
    await s.tester.tap(find.text('Sport sambo'));
    await s.shot('tt_training_month');
  });

  shotTest('tt_session_details', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1100);
    await s.tab(KTab.training);
    await s.tester.tap(find.text('Details').first);
    await s.shot('tt_session_details');
  });

  shotTest('tt_start_sheet', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1500);
    showStartTrainingSheet(s.navigator.context, planned: s.store.nextPlannedTraining);
    await s.shot('tt_start_sheet');
  });

  shotTest('tt_start_custom', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1700);
    showStartTrainingSheet(s.navigator.context);
    await s.settle();
    await s.tester.tap(find.text('Eigen'));
    await s.settle();
    await s.tester.tap(find.text('Overig'));
    await s.shot('tt_start_custom');
  });

  shotTest('tt_picker', (s, dark) async {
    await s.pumpApp(dark: dark);
    showStartTrainingSheet(s.navigator.context);
    await s.settle();
    await s.tester.ensureVisible(find.text('Uit de vault'));
    await s.settle();
    await s.tester.tap(find.text('Uit de vault'));
    await s.settle();
    await s.tester.tap(find.text('Seoi Nage'));
    await s.shot('tt_picker');
    await s.tester.tap(find.textContaining('Klaar'));
    await s.settle();
    expect(s.store.techniques.any((t) => t.name == 'Seoi Nage'), isTrue);
    await s.shot('tt_picker_after');
    await s.tester.tap(find.text('Start training'));
    await s.settle();
    expect(s.store.isSparringActive, isTrue);
    expect(s.store.sessionTitle, 'Combat Sambo');
    expect(s.store.sessionTechniques.map((t) => t.name), contains('Seoi Nage'));
    await s.shot('tt_started');
    await s.store.finishSparring(save: false);
  });

  shotTest('tt_log', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1900);
    s.navigator.push(MaterialPageRoute<void>(builder: (_) => const LogTrainingScreen()));
    await s.settle();
    await s.tester.tap(find.text('4'));
    await s.shot('tt_log');
  });

  shotTest('tt_log_save', (s, dark) async {
    await s.pumpApp(dark: dark);
    s.navigator.push(MaterialPageRoute<void>(builder: (_) => const LogTrainingScreen()));
    await s.settle();
    await s.tester.tap(find.text('+15m'));
    await s.tester.tap(find.text('Drilling'));
    await s.tester.tap(find.text('3'));
    await s.settle();
    await s.shot('tt_log_fold');
    await s.tester.tap(find.text('Sessie opslaan'));
    await s.settle();
    final saved = s.store.sessions.first;
    expect(saved.durationMinutes, 90);
    expect(saved.note, startsWith('Focus: Drilling • RPE 3/5'));
    await s.shot('tt_log_saved');
  });
}
