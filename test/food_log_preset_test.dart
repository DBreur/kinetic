import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/bolus_period.dart';
import 'package:kinetic/models/food_log_entry.dart';
import 'package:kinetic/models/food_preset.dart';
import 'package:kinetic/screens/food_log_screen.dart';

final _testProfile = AppProfile.defaults('u1');

/// Het zoekveld van de presetkiezer.
final _presetSearch = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Zoek een preset…',
);

/// Zoekt [query] en tikt "+" bij de eerste treffer.
Future<void> _addViaSearch(WidgetTester tester, String query) async {
  await tester.enterText(_presetSearch, query);
  await tester.pump();
  await tester.tap(find.byTooltip('Eén meer').first);
  await tester.pump();
}

/// "+" / "−" bij een al gekozen preset (staat bovenaan in de kiezer).
Future<void> _step(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).first);
  await tester.pump();
}

final _descriptionField = find.byWidgetPredicate(
  (w) => w is TextField && w.maxLines == 3,
);
final _carbsField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.suffixText == 'g',
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('nl_NL');
  });

  testWidgets(
    'eetlogboek: +/- op een preset telt aantal en koolhydraten op/af en '
    'gebruikt het juiste enkelvoud/meervoud',
    (tester) async {
      FoodLogEntryResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFoodLogEntrySheet(
                    context,
                    presets: const [
                      FoodPreset(
                        singular: 'boterham',
                        plural: 'boterhammen',
                        carbs: 15,
                      ),
                    ],
                    profile: _testProfile,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      String description() => tester
          .widget<TextField>(
            find.byWidgetPredicate((w) => w is TextField && w.maxLines == 3),
          )
          .controller!
          .text;

      String carbs() =>
          tester.widget<TextField>(_carbsField).controller!.text;

      // Eén keer + (via zoeken): "1 boterham" · 15 g.
      await _addViaSearch(tester, 'boter');
      expect(description(), '1 boterham');
      expect(carbs(), '15');

      // Nog een keer +: "2 boterhammen" · 30 g, niet "1 boterham, 1 boterham".
      await _step(tester, 'Eén meer');
      expect(description(), '2 boterhammen');
      expect(carbs(), '30');

      // Eén keer -: terug naar "1 boterham" · 15 g.
      await _step(tester, 'Eén minder');
      expect(description(), '1 boterham');
      expect(carbs(), '15');

      await tester.ensureVisible(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.description, '1 boterham');
      expect(result!.carbs, 15);
      expect(result!.presetCounts, {'boterham': 1});

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: handmatig getypte tekst en koolhydraten blijven staan na '
    'een preset-tik (wordt niet overschreven)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFoodLogEntrySheet(
                  context,
                  presets: const [
                    FoodPreset(
                      singular: 'boterham',
                      plural: 'boterhammen',
                      carbs: 15,
                    ),
                  ],
                  profile: _testProfile,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(_descriptionField, 'Zelfgemaakte soep');
      await tester.enterText(_carbsField, '20');
      await tester.pump();

      String description() => tester
          .widget<TextField>(
            find.byWidgetPredicate((w) => w is TextField && w.maxLines == 3),
          )
          .controller!
          .text;
      String carbs() => tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.suffixText == 'g',
            ),
          )
          .controller!
          .text;

      await _addViaSearch(tester, 'boter');
      expect(description(), 'Zelfgemaakte soep, 1 boterham');
      expect(carbs(), '35');

      // Nog een keer +: eigen tekst blijft staan, alleen het preset-stukje
      // en de koolhydraten passen zich aan.
      await _step(tester, 'Eén meer');
      expect(description(), 'Zelfgemaakte soep, 2 boterhammen');
      expect(carbs(), '50');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: presets staan alfabetisch en het zoekveld filtert live',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFoodLogEntrySheet(
                  context,
                  presets: const [
                    FoodPreset(singular: 'Pizza', plural: 'Pizza'),
                    FoodPreset(singular: 'appel', plural: 'appels'),
                    FoodPreset(singular: 'boterham', plural: 'boterhammen'),
                  ],
                  profile: _testProfile,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      const labels = {'appel', 'boterham', 'Pizza'};
      List<String> presetLabels() => tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .where(labels.contains)
          .toList();

      // "Alle presets": alfabetisch (hoofdletterongevoelig), niet in
      // toevoegvolgorde.
      await tester.tap(find.text('Alle 3'));
      await tester.pumpAndSettle();
      expect(presetLabels(), ['appel', 'boterham', 'Pizza']);
      await tester.tap(find.text('Klaar'));
      await tester.pumpAndSettle();

      // Zoeken filtert live.
      await tester.enterText(_presetSearch, 'app');
      await tester.pump();
      expect(presetLabels(), ['appel']);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: hoeveelheid per stuk (ml/g) telt mee op en staat in een '
    'lichtere tint tussen haakjes bij de preset',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFoodLogEntrySheet(
                  context,
                  presets: const [
                    FoodPreset(
                      singular: 'glas melk',
                      plural: 'glazen melk',
                      carbs: 12,
                      unitAmount: 250,
                      unitLabel: 'ml',
                    ),
                  ],
                  profile: _testProfile,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Nog niets gekozen: geen totaal tussen haakjes.
      expect(find.textContaining('(250 ml)'), findsNothing);

      await _addViaSearch(tester, 'melk');
      final firstSpan = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .firstWhere((t) => t.contains('glas melk'));
      expect(firstSpan, '1 glas melk (250 ml)');

      await _step(tester, 'Eén meer');
      final secondSpan = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .firstWhere(
            (t) => t.contains('glas melk') || t.contains('glazen melk'),
          );
      expect(secondSpan, '2 glazen melk (500 ml)');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: insuline-eenheden, voor/na eten en notitie komen terug in '
    'het resultaat',
    (tester) async {
      FoodLogEntryResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFoodLogEntrySheet(
                    context,
                    presets: const [],
                    profile: _testProfile,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Boterham met kaas');
      await tester.pump();

      // Insuline-sectie: eerst geen voor/na-keuze zichtbaar tot er een
      // aantal eenheden is ingevuld.
      expect(find.text('Voor het eten'), findsNothing);
      await tester.enterText(fields.at(3), '4');
      await tester.pump();
      expect(find.text('Voor het eten'), findsOneWidget);

      await tester.tap(find.text('Na het eten'));
      await tester.pump();

      await tester.enterText(fields.at(4), 'Bloedsuiker was al hoog');
      await tester.pump();

      await tester.ensureVisible(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.insulinUnits, 4);
      expect(result!.insulinTiming, InsulinTiming.after);
      expect(result!.insulinNote, 'Bloedsuiker was al hoog');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: wachttijd voor het eten stapt in stappen van 2,5 minuut en '
    'is alleen zichtbaar/opgeslagen bij "voor het eten"',
    (tester) async {
      FoodLogEntryResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFoodLogEntrySheet(
                    context,
                    presets: const [],
                    profile: _testProfile,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Boterham met kaas');
      await tester.enterText(fields.at(3), '4');
      await tester.pump();

      // Geen wachttijd-optie te zien vóór er een voor/na-keuze is gemaakt.
      expect(find.text('WACHTTIJD VOOR HET ETEN (OPTIONEEL)'), findsNothing);

      await tester.tap(find.text('Voor het eten'));
      await tester.pump();
      expect(find.text('WACHTTIJD VOOR HET ETEN (OPTIONEEL)'), findsOneWidget);
      expect(find.text('Geen'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('5 min'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(find.text('2,5 min'), findsOneWidget);

      await tester.ensureVisible(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.insulinWaitMinutes, 2.5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: wachttijd terug naar 0 verwijdert hem weer (optioneel '
    'blijft optioneel)',
    (tester) async {
      FoodLogEntryResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFoodLogEntrySheet(
                    context,
                    presets: const [],
                    profile: _testProfile,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Boterham met kaas');
      await tester.enterText(fields.at(3), '4');
      await tester.pump();
      await tester.tap(find.text('Voor het eten'));
      await tester.pump();

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(find.text('Geen'), findsOneWidget);

      await tester.ensureVisible(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.insulinWaitMinutes, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eetlogboek: bolus-calculator toont een live berekend totaal en '
    'gebruikt het voorstel als je zelf niets intypt',
    (tester) async {
      FoodLogEntryResult? result;
      final profile = AppProfile.defaults('u1').copyWith(
        bolusCalculatorEnabled: true,
        bolusPeriods: const [
          BolusPeriod(label: 'Dag', startTime: '00:00', carbRatio: 10),
        ],
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFoodLogEntrySheet(
                    context,
                    presets: const [],
                    profile: profile,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test');
      await tester.enterText(fields.at(1), '80'); // koolhydraten
      await tester.enterText(fields.at(2), '14'); // glucose
      await tester.pump();

      // voeding 80/10=8, correctie (14-8)/2=3, totaal 11 — zonder dat de
      // voedings-/correctievakjes zelf zijn ingevuld.
      expect(find.text('11 E'), findsOneWidget);

      await tester.ensureVisible(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.insulinFoodUnits, 8);
      expect(result!.insulinCorrectionUnits, 3);
      expect(result!.insulinUnits, 11);
      expect(tester.takeException(), isNull);
    },
  );
}
