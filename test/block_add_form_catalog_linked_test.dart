import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/technique.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'een techniek die uit de bibliotheek is gekozen blijft catalogLinked na '
    'het toevoegen — voorkomt een dubbele catalogus-aanmaak als je hem later '
    'hernoemt',
    (tester) async {
      TechniqueEntry? added;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockAddForm(
              existingTechniques: [
                Technique(id: '1', name: 'Kesa-gatame', category: 'Grondwerk'),
              ],
              onSubmit: (entry, {required openAfter}) => added = entry,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Kiezen uit de zichtbare lijst — dit moet catalogLinked=true geven.
      await tester.tap(find.text('Kesa-gatame'));
      await tester.pump();
      await tester.tap(find.text('Toevoegen'));
      await tester.pump();

      expect(added, isNotNull);
      expect(added!.catalogLinked, isTrue);

      // Renamen verandert dat niet.
      added!.name = 'Kesa-gatame ontsnapping';
      expect(added!.catalogLinked, isTrue);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('een zelf getypte techniek (niet uit de bibliotheek) is niet '
      'catalogLinked', (tester) async {
    TechniqueEntry? added;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockAddForm(
            existingTechniques: const [],
            onSubmit: (entry, {required openAfter}) => added = entry,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Naam van de techniek — of kies uit je lijst',
      ),
      'Nieuwe eigen techniek',
    );
    await tester.tap(find.text('Toevoegen'));
    await tester.pump();

    expect(added, isNotNull);
    expect(added!.catalogLinked, isFalse);

    expect(tester.takeException(), isNull);
  });
}
