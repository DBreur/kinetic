import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'sparren: rondes zijn los aanpasbaar/verwijderbaar en doelen toevoegen werkt zonder layout-crash',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlockAddForm(
                onSubmit: (_, {required openAfter}) {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Sparren'));
      await tester.pump();

      // Standaard 3 rondes van 3 minuten.
      expect(find.text('Ronde 1'), findsOneWidget);
      expect(find.text('Ronde 3'), findsOneWidget);
      expect(find.text('Ronde 4'), findsNothing);

      // Ronde toevoegen.
      await tester.ensureVisible(find.text('+ ronde'));
      await tester.tap(find.text('+ ronde'));
      await tester.pump();
      expect(find.text('Ronde 4'), findsOneWidget);

      // Eén ronde verwijderen.
      await tester.ensureVisible(find.byIcon(Icons.close).first);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      expect(find.text('Ronde 4'), findsNothing);

      // Een algemeen doel toevoegen.
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Bijv. Tempo hoog houden'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Bijv. Tempo hoog houden'),
        'Tempo hoog houden',
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('Tempo hoog houden'), findsOneWidget);

      // Dat doel als bereikt afvinken.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await tester.ensureVisible(find.byIcon(Icons.circle_outlined));
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Een doel voor ronde 1 toevoegen via de dialoog.
      await tester.ensureVisible(find.text('+ doel voor deze ronde').first);
      await tester.tap(find.text('+ doel voor deze ronde').first);
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).last,
        'Alleen guard passing',
      );
      await tester.tap(find.text('Toevoegen').last);
      await tester.pump();
      expect(find.text('Alleen guard passing'), findsOneWidget);

      // Dat rondedoel weer verwijderen via het kruisje op de rij.
      final goalRow = find.ancestor(
        of: find.text('Alleen guard passing'),
        matching: find.byType(GoalRow),
      );
      await tester.ensureVisible(
        find.descendant(of: goalRow, matching: find.byIcon(Icons.close)),
      );
      await tester.tap(
        find.descendant(of: goalRow, matching: find.byIcon(Icons.close)),
      );
      await tester.pump();
      expect(find.text('Alleen guard passing'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sparren: de tekst van een bestaand doel kan aangepast worden, ook '
    'per-ronde',
    (tester) async {
      var goals = <SparGoal>[SparGoal(text: 'Tempo hoog houden')];
      var minutes = [3];
      var roundGoals = <List<SparGoal>>[
        [SparGoal(text: 'Alleen guard passing')],
      ];
      var rest = [60];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Column(
                  children: [
                    GoalsEditor(
                      goals: goals,
                      onChanged: (g) => setState(() => goals = g),
                    ),
                    RoundsEditor(
                      roundMinutes: minutes,
                      roundGoals: roundGoals,
                      restSeconds: rest,
                      onChanged: (m, g) => setState(() {
                        minutes = m;
                        roundGoals = g;
                      }),
                      onRestChanged: (r) => setState(() => rest = r),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Algemeen doel aanpassen via het potloodje.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Tempo laag houden');
      await tester.tap(find.text('Opslaan'));
      await tester.pump();
      expect(find.text('Tempo laag houden'), findsOneWidget);
      expect(find.text('Tempo hoog houden'), findsNothing);
      expect(goals.single.text, 'Tempo laag houden');

      // Rondedoel aanpassen via het potloodje op die rij.
      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Alleen takedowns');
      await tester.tap(find.text('Opslaan'));
      await tester.pump();
      expect(find.text('Alleen takedowns'), findsOneWidget);
      expect(find.text('Alleen guard passing'), findsNothing);
      expect(roundGoals.single.single.text, 'Alleen takedowns');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sparren: rust na een ronde is per ronde instelbaar', (
    tester,
  ) async {
    var minutes = [3, 3];
    var goals = <List<SparGoal>>[[], []];
    var rest = [60, 60];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: RoundsEditor(
                roundMinutes: minutes,
                roundGoals: goals,
                restSeconds: rest,
                onChanged: (m, g) => setState(() {
                  minutes = m;
                  goals = g;
                }),
                onRestChanged: (r) => setState(() => rest = r),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('60s'), findsNWidgets(2));

    // Rust van ronde 1 ophogen met 15s — de rust-rij herkennen via het
    // label "Rust na deze ronde" binnen ronde 1's eigen container.
    final round1 = find.ancestor(
      of: find.text('Ronde 1'),
      matching: find.byType(Container),
    );
    final restLabelInRound1 = find.descendant(
      of: round1.first,
      matching: find.text('Rust na deze ronde'),
    );
    final restRow = find
        .ancestor(of: restLabelInRound1, matching: find.byType(Row))
        .first;
    await tester.tap(find.descendant(of: restRow, matching: find.text('+')));
    await tester.pump();

    expect(rest, [75, 60]);
    expect(find.text('75s'), findsOneWidget);
    expect(find.text('60s'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
