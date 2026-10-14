// combination_sort.dart — zoeken, filteren en sorteren van combinaties in de
// lijst. Pure functie zodat de volgorde zonder UI te testen is.

import '../models/combination.dart';

enum ComboSort { az, za }

/// Filtert op zoekterm (naam of een van de technieken), favorieten en type,
/// en sorteert daarna alfabetisch (hoofdletterongevoelig). Standaard A–Z.
List<Combination> sortAndFilterCombos(
  List<Combination> combos, {
  String query = '',
  bool onlyFavorites = false,
  ComboType? type,
  ComboSort sort = ComboSort.az,
}) {
  final q = query.trim().toLowerCase();
  final result = combos.where((c) {
    if (onlyFavorites && !c.favorite) return false;
    if (type != null && c.type != type) return false;
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        c.techniques.any((t) => t.toLowerCase().contains(q));
  }).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return sort == ComboSort.az ? result : result.reversed.toList();
}
