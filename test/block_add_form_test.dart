import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'BlockAddForm rendert zonder layout-crash (Annuleer-knop in een Row)',
    (tester) async {
      // De globale knoppen-thema's zetten minimumSize op Size.fromHeight(N),
      // dus oneindige breedte — elke kale OutlinedButton/FilledButton in een
      // Row zonder Expanded crasht de layout. Dit rendert het hele formulier
      // (inclusief de knoppenrij onderaan) zodat zo'n regressie hier opvalt.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: BlockAddForm(
                onSubmit: (_, {required openAfter}) {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(OutlinedButton, 'Annuleer'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Toevoegen'), findsOneWidget);
    },
  );
}
