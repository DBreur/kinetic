// food_preset_usage.dart — maakt een grote presetlijst behapbaar: hoe vaak
// gebruik je elke preset (uit je eigen eetlogboek), welke zijn dus "vaak
// gebruikt", zoeken met de beste treffers eerst, en groeperen per letter.

import '../models/food_log_entry.dart';
import '../models/food_preset.dart';

/// Hoe vaak elke preset (op [FoodPreset.singular]) voorkomt in het
/// eetlogboek van de afgelopen [window]. Telt eetmomenten, niet stuks — twee
/// boterhammen in één keer is één keer gebruikt.
Map<String, int> presetUsage(
  List<FoodLogEntry> entries, {
  required DateTime now,
  Duration window = const Duration(days: 90),
}) {
  final since = now.subtract(window);
  final usage = <String, int>{};
  for (final e in entries) {
    if (e.at.isBefore(since)) continue;
    for (final entry in e.presetCounts.entries) {
      if (entry.value <= 0) continue;
      usage[entry.key] = (usage[entry.key] ?? 0) + 1;
    }
  }
  return usage;
}

/// De [limit] meest gebruikte presets (alleen die je echt gebruikt hebt),
/// bij gelijk gebruik alfabetisch.
List<FoodPreset> frequentPresets(
  List<FoodPreset> presets,
  Map<String, int> usage, {
  int limit = 8,
}) {
  final used = presets.where((p) => (usage[p.singular] ?? 0) > 0).toList()
    ..sort((a, b) {
      final byUse = (usage[b.singular] ?? 0).compareTo(usage[a.singular] ?? 0);
      if (byUse != 0) return byUse;
      return a.singular.toLowerCase().compareTo(b.singular.toLowerCase());
    });
  return used.take(limit).toList();
}

/// Zoekt op enkel- en meervoud. Volgorde: naam begint met de zoekterm, dan
/// een woord in de naam begint ermee, dan "bevat"; binnen elke groep vaakst
/// gebruikt eerst, daarna alfabetisch.
List<FoodPreset> searchPresets(
  List<FoodPreset> presets,
  String query, {
  Map<String, int> usage = const {},
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sortedPresets(presets);
  int rank(FoodPreset p) {
    final names = [p.singular.toLowerCase(), p.plural.toLowerCase()];
    if (names.any((n) => n.startsWith(q))) return 0;
    if (names.any((n) => n.split(RegExp(r'[\s\-/]+')).any((w) => w.startsWith(q)))) {
      return 1;
    }
    if (names.any((n) => n.contains(q))) return 2;
    return 3;
  }

  final hits = presets.where((p) => rank(p) < 3).toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byUse = (usage[b.singular] ?? 0).compareTo(usage[a.singular] ?? 0);
      if (byUse != 0) return byUse;
      return a.singular.toLowerCase().compareTo(b.singular.toLowerCase());
    });
  return hits;
}

/// Alfabetisch gegroepeerd op beginletter ("#" voor cijfers/tekens), voor
/// een lijst met letterkoppen.
List<(String, List<FoodPreset>)> groupByLetter(List<FoodPreset> presets) {
  final groups = <String, List<FoodPreset>>{};
  for (final p in sortedPresets(presets)) {
    final first = p.singular.trim().isEmpty
        ? '#'
        : p.singular.trim()[0].toUpperCase();
    final key = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
    groups.putIfAbsent(key, () => []).add(p);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });
  return [for (final k in keys) (k, groups[k]!)];
}
