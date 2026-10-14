import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/combination.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'een combinatie loggen maakt één los techniek-blok per techniek in de '
    'combinatie aan',
    (tester) async {
      final submitted = <TechniqueEntry>[];
      const combo = Combination(
        id: 'c1',
        name: 'Jab-cross-takedown',
        type: ComboType.mixed,
        techniques: ['Jab', 'Cross', 'Enkeltackle'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: BlockAddForm(
                onSubmit: (entry, {required openAfter}) => submitted.add(entry),
                onCancel: () {},
                existingCombinations: const [combo],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Standaard sta je in "Losse techniek" — schakel om naar combinatie.
      await tester.tap(find.text('Combinatie'));
      await tester.pump();

      // De naamsinvoer voor losse technieken is nu vervangen door de lijst
      // met opgeslagen combinaties.
      expect(
        find.text('Naam van de techniek — of kies uit je lijst'),
        findsNothing,
      );
      expect(find.text(combo.name), findsOneWidget);

      await tester.tap(find.text(combo.name));
      await tester.pump();

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Combinatie loggen'),
      );
      await tester.pump();

      expect(submitted, hasLength(3));
      expect(submitted.map((e) => e.name), ['Jab', 'Cross', 'Enkeltackle']);
      for (final e in submitted) {
        expect(e.kind, BlockKind.technique);
        expect(e.covered, isTrue);
        expect(e.meta, contains('combo: Jab-cross-takedown'));
      }

      expect(tester.takeException(), isNull);
    },
  );
}
