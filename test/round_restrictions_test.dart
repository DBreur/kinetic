// round_restrictions_test.dart — beperkingen per sparronde (startpositie of
// wat niet mag): bewaard in dezelfde blocks-JSON als de rondedoelen, en
// lopen bij het toevoegen/verwijderen van rondes gelijk op met die rondes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/theme/kinetic_theme.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  test('beperkingen overleven toJson/fromJson en de werkkopie', () {
    const block = SessionBlock(
      kind: BlockKind.sparring,
      name: 'Randori',
      roundMinutes: [3, 3],
      roundRestrictions: [
        [SparGoal(text: 'Start: grond onder', achieved: true)],
        [SparGoal(text: 'Geen klemmen')],
      ],
    );
    final back = SessionBlock.fromJson(block.toJson());
    expect(back.roundRestrictions.length, 2);
    expect(back.roundRestrictions[0].single.text, 'Start: grond onder');
    expect(back.roundRestrictions[0].single.achieved, isTrue);
    expect(back.roundRestrictions[1].single.text, 'Geen klemmen');

    final roundTrip = TechniqueEntry.fromBlock(back).toBlock();
    expect(roundTrip.roundRestrictions[1].single.text, 'Geen klemmen');
  });

  test('oude sessies zonder beperkingen laden gewoon (lege lijst)', () {
    final block = SessionBlock.fromJson({
      'kind': 'sparring',
      'name': 'Randori',
      'round_minutes': [3],
    });
    expect(block.roundRestrictions, isEmpty);
  });

  Widget host(Widget child) => MaterialApp(
    theme: KineticTheme.dark,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('ronde verwijderen haalt ook de beperkingen van die ronde weg', (
    tester,
  ) async {
    var minutes = [3, 4];
    var restrictions = [
      [const SparGoal(text: 'Start: staand')],
      [const SparGoal(text: 'Geen worpen')],
    ];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => host(
          RoundsEditor(
            roundMinutes: minutes,
            restSeconds: const [60, 60],
            roundRestrictions: restrictions,
            onRestrictionsChanged: (r) => setState(() => restrictions = r),
            onChanged: (m, _) => setState(() => minutes = m),
            onRestChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Start: staand'), findsOneWidget);
    expect(find.text('+ beperking / startpositie'), findsNWidgets(2));

    // Het eerste kruisje in de rondekop = ronde 1 verwijderen.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(minutes, [4]);
    expect(restrictions.length, 1);
    expect(restrictions.single.single.text, 'Geen worpen');
    expect(find.text('Start: staand'), findsNothing);
  });

  testWidgets('een preset kiezen voegt de beperking toe aan die ronde', (
    tester,
  ) async {
    var restrictions = <List<SparGoal>>[[]];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => host(
          RoundsEditor(
            roundMinutes: const [3],
            restSeconds: const [60],
            roundRestrictions: restrictions,
            onRestrictionsChanged: (r) => setState(() => restrictions = r),
            onChanged: (_, _) {},
            onRestChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('+ beperking / startpositie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geen verwurgingen'));
    await tester.pumpAndSettle();

    expect(restrictions.single.single.text, 'Geen verwurgingen');
    expect(find.text('Geen verwurgingen'), findsOneWidget);
  });

  testWidgets('zonder beperkingen-callback geen knop (bestaand gedrag)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        RoundsEditor(
          roundMinutes: const [3],
          onChanged: (_, _) {},
          onRestChanged: (_) {},
        ),
      ),
    );
    expect(find.text('+ beperking / startpositie'), findsNothing);
    expect(find.text('+ doel voor deze ronde'), findsOneWidget);
  });
}
