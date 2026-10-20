// number_input_test.dart — gewicht zelf typen: komma én punt werken, en
// een ongeldige waarde verandert niets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/widgets/number_input.dart';

void main() {
  Future<double?> type(WidgetTester tester, String text) async {
    double? result = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showNumberInput(
                context,
                title: 'Gewicht',
                initial: 20,
                decimal: true,
                max: 500,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return result;
  }

  testWidgets('komma', (tester) async {
    expect(await type(tester, '22,5'), 22.5);
  });

  testWidgets('punt', (tester) async {
    expect(await type(tester, '17.5'), 17.5);
  });

  testWidgets('te groot: geen waarde', (tester) async {
    expect(await type(tester, '900'), isNull);
  });
}
