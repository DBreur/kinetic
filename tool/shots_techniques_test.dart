// shots_techniques_test.dart: rendert de Technieken-tab (Vault, Systemen,
// Ontdekken), de systeem-editor en de bijbehorende sheets naar PNG.
//
//   flutter test tool/shots_techniques_test.dart --dart-define=SHOTS_DIR=<map>
//     --dart-define=THEME=both

// ignore_for_file: use_build_context_synchronously

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/screens/techniques/system_editor_screen.dart';
import 'package:kinetic/state/kinetic_store.dart';
import 'package:material_ui/material_ui.dart';

import 'shots_support.dart';

void main() {
  setUpAll(loadShotFonts);

  Future<void> openTab(ShotSession s, String sub) async {
    await s.tab(KTab.technieken);
    if (sub != 'Technieken') {
      await s.tester.tap(find.text(sub).first);
      await s.settle();
    }
  }

  shotTest('t_vault', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1900);
    await openTab(s, 'Technieken');
    await s.shot('t1_vault');
  });

  shotTest('t_vault_phone', (s, dark) async {
    await s.pumpApp(dark: dark);
    await openTab(s, 'Technieken');
    await s.shot('t1b_vault_phone');
  });

  shotTest('t_vault_group', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1900);
    await openTab(s, 'Technieken');
    // Throws en Striking dichtklappen, Submissions openen (bibliotheek).
    await s.tester.tap(find.textContaining('Worpen & takedowns'));
    await s.settle();
    await s.tester.tap(find.textContaining('Stoten, trappen'));
    await s.settle();
    await s.tester.tap(find.textContaining('Klemmen, armbars'));
    await s.settle();
    await s.shot('t2_vault_submissions');
  });

  shotTest('t_vault_search', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1200);
    await openTab(s, 'Technieken');
    await s.tester.enterText(find.byType(TextField).first, 'arm');
    await s.settle();
    await s.shot('t3_vault_search');
  });

  shotTest('t_vault_new', (s, dark) async {
    await s.pumpApp(dark: dark);
    await openTab(s, 'Technieken');
    await s.tester.tap(find.text('Techniek').first);
    await s.settle();
    await s.shot('t4_new_technique');
  });

  shotTest('t_vault_sheet', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1000);
    await openTab(s, 'Technieken');
    await s.tester.tap(find.text('Harai Goshi').first);
    await s.settle();
    await s.shot('t5_technique_sheet');
  });

  shotTest('t_systems', (s, dark) async {
    await s.pumpApp(dark: dark);
    await openTab(s, 'Systemen');
    await s.shot('t6_systems');
  });

  shotTest('t_editor', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1600);
    s.navigator.push(MaterialPageRoute<void>(builder: (_) => const SystemEditorScreen(systemId: 'sys1')));
    await s.settle();
    await s.shot('t7_system_editor');
  });

  shotTest('t_editor_node', (s, dark) async {
    await s.pumpApp(dark: dark);
    s.navigator.push(MaterialPageRoute<void>(builder: (_) => const SystemEditorScreen(systemId: 'sys1')));
    await s.settle();
    await s.tester.tap(find.text('Harai Goshi').first);
    await s.settle();
    await s.shot('t8_node_actions');
  });

  shotTest('t_editor_add', (s, dark) async {
    await s.pumpApp(dark: dark);
    s.navigator.push(MaterialPageRoute<void>(builder: (_) => const SystemEditorScreen(systemId: 'sys1')));
    await s.settle();
    await s.tester.tap(find.text('Stap').first);
    await s.settle();
    await s.tester.enterText(find.byType(TextField).last, 'Uchi');
    await s.settle();
    await s.shot('t9_node_add');
  });

  shotTest('t_discover', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1600);
    await openTab(s, 'Ontdekken');
    await s.shot('t10_discover');
  });

  shotTest('t_discover_sheet', (s, dark) async {
    await s.pumpApp(dark: dark, height: 1000);
    await openTab(s, 'Ontdekken');
    await s.tester.tap(find.text('Armbar from guard').first);
    await s.settle();
    await s.shot('t11_discover_sheet');
  });
}
