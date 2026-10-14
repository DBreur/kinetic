import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/screens/mat_mode_screen.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/mat_session_controller.dart';

void main() {
  testWidgets(
    'technieken kunnen verwijderd worden ook nu ze in een ReorderableListView '
    'staan (swipe botste eerder met het sleepgebaar)',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final controller = MatSessionController(
        title: 'Combat sambo',
        appController: AppController(),
        contextOf: () => navigatorKey.currentContext!,
        planned: [
          TechniqueEntry(name: 'Kesa-gatame ontsnapping', meta: 'Grondwerk'),
          TechniqueEntry(name: 'Heupworp uit clinch', meta: 'Staand'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: MatModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.text('Kesa-gatame ontsnapping'), findsOneWidget);
      expect(find.text('Heupworp uit clinch'), findsOneWidget);

      // Verwijderen via het kruisje (geen swipe: die botst met het
      // sleepgebaar van de ReorderableListView).
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('Kesa-gatame ontsnapping'), findsNothing);
      expect(find.text('Heupworp uit clinch'), findsOneWidget);
      expect(find.text('Ongedaan maken'), findsOneWidget);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
