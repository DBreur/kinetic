import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/screens/food_log_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('nl_NL'));

  testWidgets('open blad neemt een nieuwere live meting over', (tester) async {
    final now = DateTime.now();
    final live = ValueNotifier<GlucoseSnapshot?>(
      GlucoseSnapshot(
        reading: GlucoseReading(
          5.2,
          Trend.flat,
          now.subtract(const Duration(minutes: 12)),
        ),
        history: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFoodLogEntrySheet(
              context,
              presets: const [],
              profile: AppProfile.defaults('u'),
              latestReading: live.value!.reading,
              liveGlucose: live,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '5,2'), findsOneWidget);

    live.value = GlucoseSnapshot(
      reading: GlucoseReading(6.1, Trend.slightUp, now),
      history: const [],
    );
    await tester.pump();
    expect(find.widgetWithText(TextField, '6,1'), findsOneWidget);

    // Zelf iets ingevuld? Dan niet meer overschrijven.
    await tester.enterText(find.widgetWithText(TextField, '6,1'), '7,0');
    live.value = GlucoseSnapshot(
      reading: GlucoseReading(
        6.4,
        Trend.flat,
        now.add(const Duration(minutes: 1)),
      ),
      history: const [],
    );
    await tester.pump();
    expect(find.widgetWithText(TextField, '7,0'), findsOneWidget);

    // Blad sluiten zodat de 30s-ticker stopt.
    Navigator.of(tester.element(find.text('7,0'))).pop();
    await tester.pumpAndSettle();
  });
}
