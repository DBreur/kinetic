import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/screens/mat_mode_screen.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/mat_session_controller.dart';

void main() {
  testWidgets(
    'toevoegformulier scrolt in beeld op een klein scherm met volle lijst',
    (tester) async {
      // Zoals een telefoon: klein genoeg dat 4 geplande blokken + de
      // "+"-knop de hele hoogte al vullen, precies het scenario waarin de
      // knop verdween zonder dat er iets zichtbaars bijkwam.
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final navigatorKey = GlobalKey<NavigatorState>();
      final controller = MatSessionController(
        title: 'Combat sambo',
        appController: AppController(),
        contextOf: () => navigatorKey.currentContext!,
        planned: [
          TechniqueEntry(name: 'Kesa-gatame ontsnapping', meta: 'Grondwerk'),
          TechniqueEntry(name: 'Beenschaar -> armklem', meta: 'Grondwerk'),
          TechniqueEntry(name: 'Heupworp uit clinch', meta: 'Staand'),
          TechniqueEntry(
            kind: BlockKind.sparring,
            name: 'Randori',
            minutes: 16,
            rounds: 3,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: MatModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      // Met de Kinetic-rijen staat de knop op dit kleine scherm onder de
      // vouw — eerst ernaartoe scrollen zoals een gebruiker zou doen.
      final addButton = find.text('Techniek, warming-up of sparren toevoegen');
      await tester.scrollUntilVisible(
        addButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(addButton);
      // Eén frame voor de setState, daarna wachten tot de post-frame
      // scroll-animatie helemaal is uitgetikt.
      await tester.pump();
      await tester.pumpAndSettle();

      const hint = 'Naam van de techniek — of kies uit je lijst';
      expect(find.text(hint), findsOneWidget);

      final hintCenter = tester.getCenter(find.text(hint));
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      expect(
        hintCenter.dy,
        lessThan(screenHeight),
        reason: 'Het naamveld van het toevoegformulier valt buiten beeld',
      );

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
