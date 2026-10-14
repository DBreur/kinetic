// mat_session_controller_test.dart — elapsed moet uit de kloktijd komen, niet
// uit een Stopwatch: Android pauzeert de monotone klok achter een Stopwatch
// zodra het scherm uit gaat en er geen wakelock is, waardoor de trainingsduur
// dan stopt met lopen in plaats van gewoon door te tellen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/mat_session_controller.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return ctx;
  }

  testWidgets(
    'elapsed loopt door op basis van de kloktijd en pause/resume werkt nog '
    'correct',
    (tester) async {
      final ctx = await pumpHost(tester);
      final controller = MatSessionController(
        title: 'Test',
        appController: AppController(),
        contextOf: () => ctx,
      );

      // Timer.periodic/Future.delayed lopen in testWidgets in een
      // fake-tijd-zone — runAsync breekt daaruit zodat echte wall-clock
      // vertragingen (nodig om elapsed te testen) daadwerkelijk verstrijken.
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
        expect(controller.elapsed.inMilliseconds, greaterThanOrEqualTo(250));

        controller.pause();
        final atPause = controller.elapsed;
        await Future.delayed(const Duration(milliseconds: 300));
        expect(
          controller.elapsed.inMilliseconds,
          closeTo(atPause.inMilliseconds, 30),
        );

        controller.resume();
        await Future.delayed(const Duration(milliseconds: 300));
        expect(controller.elapsed, greaterThan(atPause));
      });

      controller.dispose();
    },
  );
}
