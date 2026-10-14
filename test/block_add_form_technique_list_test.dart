import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/technique.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'bestaande technieken staan meteen zichtbaar in de toevoeg-tab, niet '
    'pas als je gaat typen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: BlockAddForm(
                onSubmit: (_, {required openAfter}) {},
                onCancel: () {},
                existingTechniques: const [
                  Technique(
                    id: '1',
                    name: 'Kesa-gatame ontsnapping',
                    category: 'Grondwerk',
                  ),
                  Technique(
                    id: '2',
                    name: 'Heupworp uit clinch',
                    category: 'Staand',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zonder iets te typen of het veld te focussen staan beide al in beeld.
      expect(find.text('Kesa-gatame ontsnapping'), findsOneWidget);
      expect(find.text('Heupworp uit clinch'), findsOneWidget);

      await tester.tap(find.text('Heupworp uit clinch'));
      await tester.pump();

      expect(
        find.widgetWithText(TextField, 'Heupworp uit clinch'),
        findsOneWidget,
      );
    },
  );
}
