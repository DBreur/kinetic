// preset_text.dart: de omschrijving van een maaltijd bijwerken als je met
// −/+ een voedingspreset toevoegt of weghaalt. Alleen het stukje tekst van
// déze preset verandert ("1 Appel" → "2 Appels"); wat je zelf typte blijft
// vooraan staan en items worden met komma's gescheiden.

import '../models/food_preset.dart';

/// Resultaat van één −/+ tik: nieuwe tekst, nieuwe tellers en hoeveel
/// koolhydraten erbij (of eraf) moeten.
typedef PresetChange = ({String text, Map<String, int> counts, double carbsDelta});

String appendListItem(String text, String item) {
  final t = text.trim();
  if (t.isEmpty) return item;
  // Eindigt al op een komma (bv. "Brood, ")? Dan alleen een spatie ertussen.
  if (t.endsWith(',')) return '$t $item';
  return '$t, $item';
}

String removeListItem(String text, String item) {
  var result = text;
  if (result.contains('$item, ')) {
    result = result.replaceFirst('$item, ', '');
  } else if (result.contains(', $item')) {
    result = result.replaceFirst(', $item', '');
  } else {
    result = result.replaceFirst(item, '');
  }
  return result.trim();
}

/// Past [text] en [counts] aan voor [delta] stuks van [preset].
PresetChange applyPresetChange({
  required String text,
  required Map<String, int> counts,
  required FoodPreset preset,
  required int delta,
}) {
  final oldCount = counts[preset.singular] ?? 0;
  final newCount = (oldCount + delta).clamp(0, 999);
  final next = Map<String, int>.of(counts);
  if (newCount == oldCount) return (text: text, counts: next, carbsDelta: 0);

  final oldLabel = oldCount > 0 ? preset.label(oldCount) : null;
  final newLabel = newCount > 0 ? preset.label(newCount) : null;
  var out = text;
  if (oldLabel != null && out.contains(oldLabel)) {
    out = newLabel != null ? out.replaceFirst(oldLabel, newLabel) : removeListItem(out, oldLabel);
  } else if (newLabel != null) {
    out = appendListItem(out, newLabel);
  }
  if (newCount == 0) {
    next.remove(preset.singular);
  } else {
    next[preset.singular] = newCount;
  }
  return (text: out, counts: next, carbsDelta: preset.carbs * (newCount - oldCount));
}

/// Hoe vaak elke preset (enkelvoud) in eerdere maaltijden is gebruikt,
/// voor de snelknoppen buiten de lijst.
Map<String, int> presetUsage(Iterable<Map<String, int>> history) {
  final usage = <String, int>{};
  for (final counts in history) {
    for (final e in counts.entries) {
      usage[e.key] = (usage[e.key] ?? 0) + 1;
    }
  }
  return usage;
}

/// De [max] meest gebruikte presets (minstens 2× gebruikt), anders leeg.
List<FoodPreset> frequentPresets(List<FoodPreset> presets, Map<String, int> usage, {int max = 4}) {
  final used = presets.where((p) => (usage[p.singular] ?? 0) >= 2).toList()
    ..sort((a, b) => (usage[b.singular] ?? 0).compareTo(usage[a.singular] ?? 0));
  return used.take(max).toList();
}
