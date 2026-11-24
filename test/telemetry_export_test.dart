import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/meal_impact.dart';
import 'package:kinetic/models/food_log_entry.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/weigh_in.dart';
import 'package:kinetic/services/telemetry_export.dart';

void main() {
  final data = ExportData(
    meals: [
      FoodLogEntry(
        id: 'm2',
        at: DateTime(2026, 11, 24, 12, 30),
        description: 'Brood, "kaas", ham',
        carbs: 60,
        protein: 25,
        context: MealContext.recovery,
      ),
      FoodLogEntry(id: 'm1', at: DateTime(2026, 11, 23, 7, 5), description: 'Dextrose', carbs: 15),
    ],
    weighIns: [WeighIn(id: 'w1', measuredAt: DateTime(2026, 11, 23, 7, 0), weightKg: 86.7)],
    glucose: [GlucosePoint(DateTime(2026, 11, 23, 7, 0), 6.44)],
  );

  test('CSV escapet komma\'s en aanhalingstekens', () {
    final csv = tableToCsv(buildExportTables(data)['meals']!);
    final lines = csv.trim().split('\n');
    expect(lines.first, startsWith('id,tijd,omschrijving,koolhydraten_g'));
    expect(lines.length, 3);
    expect(csv, contains('"Brood, ""kaas"", ham"'));
  });

  test('anonimiseren haalt id\'s en vrije tekst weg en maakt tijden relatief', () {
    final t = buildExportTables(data, anonymize: true);
    final json = tablesToJson(t, anonymize: true);
    expect(json, isNot(contains('m1')));
    expect(json, isNot(contains('Brood')));
    expect(json, isNot(contains('2026')));
    final meals = (jsonDecode(json) as Map)['meals'] as List;
    expect(meals.first['tijd'], 'dag 0 07:05');
    expect(meals.last['tijd'], 'dag 1 12:30');
    expect(meals.last['context'], 'recovery');
  });

  test('glucose wordt op 1 decimaal afgerond', () {
    final t = buildExportTables(data);
    expect(t['glucose']!.single['mmol'], 6.4);
  });
}
