import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/dashboard_config.dart';
import 'package:kinetic/widgets/dashboard_editor.dart';

void main() {
  group('DashboardConfig', () {
    test('leeg of ontbrekend = standaard, op slot', () {
      final c = DashboardConfig.fromJson(null);
      expect(c.visibleSections, DashSection.values);
      expect(c.visibleActions, [
        QuickAction.finger,
        QuickAction.meal,
        QuickAction.planTraining,
        QuickAction.techniques,
      ]);
      expect(c.locked, isTrue);
      expect(DashboardConfig.fromJson(const {}).sections, hasLength(5));
    });

    test('bewaarde volgorde blijft, onbekend eruit, nieuw achteraan', () {
      final c = DashboardConfig.fromJson({
        'sections': [
          {'id': 'recent', 'on': true},
          {'id': 'quickActions', 'on': false},
          {'id': 'bestaatNiet', 'on': true},
          {'id': 'recent', 'on': false},
        ],
        'actions': [
          {'id': 'startStrength', 'on': true},
        ],
        'locked': false,
      });
      expect(c.sections.map((s) => s.id).take(2), [
        DashSection.recent,
        DashSection.quickActions,
      ]);
      expect(c.sections, hasLength(DashSection.values.length));
      expect(c.visibleSections.first, DashSection.recent);
      expect(c.visibleSections, isNot(contains(DashSection.quickActions)));
      expect(c.actions.first.id, QuickAction.startStrength);
      expect(c.visibleActions.first, QuickAction.startStrength);
      expect(c.visibleActions, contains(QuickAction.meal));
      expect(c.locked, isFalse);

      final back = DashboardConfig.fromJson(c.toJson());
      expect(back.toJson(), c.toJson());
    });

    test('zit in het profiel', () {
      final p = AppProfile.fromJson({
        ...AppProfile.defaults('u').toJson(),
        'dashboard': {
          'sections': [
            {'id': 'recent', 'on': true},
          ],
        },
      });
      expect(p.dashboard.sections.first.id, DashSection.recent);
      expect(
        (p.toJson()['dashboard'] as Map)['sections'],
        isA<List>().having((l) => l.first['id'], 'eerste', 'recent'),
      );
    });
  });

  testWidgets('slot verbergt de sleepgrepen, schakelaar zet uit', (
    tester,
  ) async {
    var config = DashboardConfig.standard;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: DashboardEditor(
                config: config,
                onChanged: (c) => setState(() => config = c),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();
    expect(config.locked, isFalse);
    expect(find.byIcon(Icons.drag_handle), findsWidgets);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(config.visibleSections, isNot(contains(DashSection.competition)));
  });
}
