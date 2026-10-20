// glucose_alarm_snooze_test.dart — na "Ingenomen" mag het alarm 15 minuten
// niet opnieuw afgaan voor dezelfde overschrijding, tenzij de waarde nog
// 0,5 mmol/L of meer verder zakt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/services/alarm_notification_service.dart';
import 'package:kinetic/widgets/glucose_alarm.dart';

/// Neppe notificatiedienst — een test mag het echte platformkanaal niet
/// aanroepen (dat geeft een MissingPluginException, of erger, hangt).
class _FakeNotifier implements GlucoseAlarmNotifier {
  @override
  Future<void> showAlarm({
    required bool withSound,
    required bool breakSilentMode,
    required bool isHigh,
    required double mmol,
  }) async {}

  @override
  Future<void> cancelAlarm() async {}

  @override
  Future<void> showRemeasureReminder({
    required bool withSound,
    required double currentValue,
  }) async {}

  @override
  Future<void> showStaleWarning({required bool withSound}) async {}
}

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
    'binnen 15 minuten met dezelfde (of hogere) waarde: geen nieuw alarm',
    (tester) async {
      final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
      final ctx = await pumpHost(tester);

      guard.check(
        () => ctx,
        GlucoseReading(3.5, Trend.flat, DateTime.now()),
        lowBelow: 3.9,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsOneWidget);

      // "Ingenomen — timer 15 min" indrukken sluit de sheet en start de
      // snooze.
      await tester.tap(find.text('Sluimeren 15 min'));
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsNothing);

      // Nieuwe meting, nog steeds 3,5 (geen verdere daling): geen nieuwe
      // sheet.
      guard.check(
        () => ctx,
        GlucoseReading(3.5, Trend.flat, DateTime.now()),
        lowBelow: 3.9,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsNothing);

      guard.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'binnen 15 minuten maar 0,5 mmol/L of meer verder gezakt: alarm gaat '
    'opnieuw af',
    (tester) async {
      final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
      final ctx = await pumpHost(tester);

      guard.check(
        () => ctx,
        GlucoseReading(3.5, Trend.flat, DateTime.now()),
        lowBelow: 3.9,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsOneWidget);

      await tester.tap(find.text('Sluimeren 15 min'));
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsNothing);

      // 0,5 verder gezakt (3,5 -> 3,0): behandeling hielp niet, alarm mag
      // meteen opnieuw.
      guard.check(
        () => ctx,
        GlucoseReading(3.0, Trend.down, DateTime.now()),
        lowBelow: 3.9,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlucoseAlertSheet), findsOneWidget);

      guard.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('waarde weer boven de grens: snooze vervalt, een latere nieuwe '
      'overschrijding alarmeert weer', (tester) async {
    final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
    final ctx = await pumpHost(tester);

    guard.check(
      () => ctx,
      GlucoseReading(3.5, Trend.flat, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sluimeren 15 min'));
    await tester.pumpAndSettle();

    // Boven de grens: behandeling geslaagd.
    guard.check(
      () => ctx,
      GlucoseReading(5.0, Trend.up, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);

    // Een nieuwe, latere hypo (zonder tussenkomst van "Ingenomen") moet
    // gewoon weer alarmeren.
    guard.check(
      () => ctx,
      GlucoseReading(3.6, Trend.down, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsOneWidget);

    guard.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sluimeren bij hyper: geen nieuw alarm zolang hij hoog blijft, '
      'na herstel ook niet meer', (tester) async {
    final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
    final ctx = await pumpHost(tester);
    AlarmSnooze? reported;
    guard.onSnoozeChanged = (s) => reported = s;

    guard.check(
      () => ctx,
      GlucoseReading(12.0, Trend.up, DateTime.now()),
      lowBelow: 3.9,
      highAbove: 10.0,
      snoozeMinutes: 20,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsOneWidget);

    await tester.tap(find.text('Sluimeren 20 min'));
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);
    expect(reported?.isHigh, isTrue);

    // Nog steeds hoog: stil.
    guard.check(
      () => ctx,
      GlucoseReading(13.0, Trend.up, DateTime.now()),
      lowBelow: 3.9,
      highAbove: 10.0,
      snoozeMinutes: 20,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);

    // Weer binnen de grenzen: sluimeren vervalt.
    guard.check(
      () => ctx,
      GlucoseReading(8.0, Trend.down, DateTime.now()),
      lowBelow: 3.9,
      highAbove: 10.0,
      snoozeMinutes: 20,
    );
    await tester.pumpAndSettle();
    expect(guard.snooze.value, isNull);
    expect(reported, isNull);

    guard.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('wegvegen telt als sluimeren', (tester) async {
    final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
    final ctx = await pumpHost(tester);

    guard.check(
      () => ctx,
      GlucoseReading(3.5, Trend.flat, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsOneWidget);

    // Buiten het paneel tikken sluit hem.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);
    expect(guard.snooze.value, isNotNull);

    guard.check(
      () => ctx,
      GlucoseReading(3.5, Trend.flat, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);

    guard.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sluimeren via de melding sluit het paneel', (tester) async {
    final guard = GlucoseAlarmGuard(notifier: _FakeNotifier());
    final ctx = await pumpHost(tester);

    guard.check(
      () => ctx,
      GlucoseReading(3.5, Trend.flat, DateTime.now()),
      lowBelow: 3.9,
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsOneWidget);

    guard.snoozeFromNotification(isHigh: false, mmol: 3.5);
    await tester.pumpAndSettle();
    expect(find.byType(GlucoseAlertSheet), findsNothing);
    expect(guard.snooze.value?.isHigh, isFalse);

    guard.dispose();
    expect(tester.takeException(), isNull);
  });
}
