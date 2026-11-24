// telemetry_export.dart: zet maaltijden, wegingen, sessies en glucose om
// naar CSV/JSON, optioneel geanonimiseerd. Pure functies: de data komt van
// de store, het delen gebeurt in het scherm.
//
// Anonimiseren betekent hier: geen id's of e-mail, geen vrije tekst
// (omschrijvingen en notities kunnen persoonlijke info bevatten), en
// tijdstippen als "dag N, uu:mm" relatief aan de eerste regel in plaats van
// een echte datum.

import 'dart:convert';

import '../core/formatters.dart';
import '../models/food_log_entry.dart';
import '../models/glucose.dart';
import '../models/training_session.dart';
import '../models/weigh_in.dart';

typedef ExportTable = List<Map<String, Object?>>;

class ExportData {
  final List<FoodLogEntry> meals;
  final List<WeighIn> weighIns;
  final List<TrainingSession> sessions;
  final List<GlucosePoint> glucose;

  const ExportData({
    this.meals = const [],
    this.weighIns = const [],
    this.sessions = const [],
    this.glucose = const [],
  });

  bool get isEmpty => meals.isEmpty && weighIns.isEmpty && sessions.isEmpty && glucose.isEmpty;
}

Map<String, ExportTable> buildExportTables(ExportData d, {bool anonymize = false}) {
  final all = <DateTime>[
    ...d.meals.map((e) => e.at),
    ...d.weighIns.map((e) => e.measuredAt),
    ...d.sessions.map((e) => e.startedAt),
    ...d.glucose.map((e) => e.at),
  ];
  final origin = all.isEmpty ? DateTime.now() : all.reduce((a, b) => a.isBefore(b) ? a : b);
  String time(DateTime t) {
    if (!anonymize) return t.toUtc().toIso8601String();
    final days = dayStart(t).difference(dayStart(origin)).inDays;
    return 'dag $days ${hhmm(t)}';
  }

  return {
    'meals': [
      for (final m in d.meals.reversed)
        {
          if (!anonymize) 'id': m.id,
          'tijd': time(m.at),
          if (!anonymize) 'omschrijving': m.description,
          'koolhydraten_g': m.carbs,
          'eiwit_g': m.protein,
          'vet_g': m.fat,
          'insuline_e': m.insulinUnits,
          'context': m.context?.dbName,
          'glucose_mmol': m.mmol,
        },
    ],
    'weigh_ins': [
      for (final w in d.weighIns.reversed)
        {
          if (!anonymize) 'id': w.id,
          'tijd': time(w.measuredAt),
          'gewicht_kg': w.weightKg,
        },
    ],
    'sessions': [
      for (final s in d.sessions.reversed)
        {
          if (!anonymize) 'id': s.id,
          'tijd': time(s.startedAt),
          'soort': s.kind,
          if (!anonymize) 'titel': s.title,
          'duur_min': s.durationMinutes,
          'sparringrondes': s.sparringRounds,
          'glucose_start': s.glucoseStart,
          'glucose_eind': s.glucoseEnd,
          'glucose_laagste': s.glucoseLowest,
          'safe_zone_pct': s.glucoseSafeZone == null ? null : (s.glucoseSafeZone! * 100).round(),
          if (!anonymize) 'notitie': s.note,
        },
    ],
    'glucose': [
      for (final g in d.glucose)
        {'tijd': time(g.at), 'mmol': double.parse(g.mmol.toStringAsFixed(1))},
    ],
  };
}

String tablesToJson(Map<String, ExportTable> tables, {required bool anonymize}) =>
    const JsonEncoder.withIndent('  ').convert({
      'app': 'Kinetic',
      'formaat': 1,
      'geanonimiseerd': anonymize,
      ...tables,
    });

/// RFC 4180: velden met komma, aanhalingsteken of regeleinde tussen quotes.
String tableToCsv(ExportTable rows) {
  if (rows.isEmpty) return '';
  final headers = <String>[];
  for (final r in rows) {
    for (final k in r.keys) {
      if (!headers.contains(k)) headers.add(k);
    }
  }
  String cell(Object? v) {
    if (v == null) return '';
    final s = v is double ? v.toString() : '$v';
    if (s.contains(RegExp('[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  final b = StringBuffer()..writeln(headers.join(','));
  for (final r in rows) {
    b.writeln(headers.map((h) => cell(r[h])).join(','));
  }
  return b.toString();
}
