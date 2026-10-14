import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  testWidgets(
    'een zelf toegevoegde techniek is meteen covered, anders valt hij stil '
    'uit de opgeslagen sessie én uit de techniekencatalogus',
    (tester) async {
      TechniqueEntry? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: BlockAddForm(
                onSubmit: (entry, {required openAfter}) => submitted = entry,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Nieuwe techniek');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Toevoegen'));
      await tester.pump();

      expect(submitted, isNotNull);
      expect(submitted!.kind, BlockKind.technique);
      expect(submitted!.covered, isTrue);
    },
  );
}
