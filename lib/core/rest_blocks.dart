// rest_blocks.dart — rust en blokken bij krachttraining.
//
// Een blok (superset) is een reeks opeenvolgende oefeningen met hetzelfde
// bloknummer: je doet set 1 van elke oefening achter elkaar, dan rust, dan
// set 2 van elke oefening, enzovoort. Een oefening zonder bloknummer staat
// los en krijgt na elke set rust.

/// "45 s", "1:30 min", "2 min".
String formatRest(int seconds) {
  if (seconds < 60) return '$seconds s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m min' : '$m:${s.toString().padLeft(2, '0')} min';
}

/// Letter van het n-de blok in een lijst: A, B, C, …
String blockLetter(int index) =>
    index < 26 ? String.fromCharCode(65 + index) : '${index + 1}';

/// Bereik [start, end) van de oefeningen in hetzelfde blok als [index].
/// Een losse oefening is een blok van één.
({int start, int end}) blockRange(List<int?> blocks, int index) {
  final id = blocks[index];
  if (id == null) return (start: index, end: index + 1);
  var start = index;
  while (start > 0 && blocks[start - 1] == id) {
    start--;
  }
  var end = index + 1;
  while (end < blocks.length && blocks[end] == id) {
    end++;
  }
  return (start: start, end: end);
}

/// Alle blokken in volgorde, als bereiken — ook losse oefeningen (lengte 1).
List<({int start, int end})> blockRanges(List<int?> blocks) {
  final result = <({int start, int end})>[];
  var i = 0;
  while (i < blocks.length) {
    final r = blockRange(blocks, i);
    result.add(r);
    i = r.end;
  }
  return result;
}

/// Nieuw bloknummer dat nog niet in [blocks] voorkomt.
int freshBlockId(List<int?> blocks) {
  var max = 0;
  for (final b in blocks) {
    if (b != null && b > max) max = b;
  }
  return max + 1;
}

/// Na het koppelen/losmaken: blokken van één oefening worden weer los
/// (null), zodat "blok" altijd minstens twee oefeningen betekent.
List<int?> normalizeBlocks(List<int?> blocks) {
  final result = List<int?>.of(blocks);
  for (final r in blockRanges(blocks)) {
    if (r.end - r.start == 1) result[r.start] = null;
  }
  return result;
}

/// Iets in een lijst dat in een blok kan zitten en eigen rust kan hebben —
/// een live oefening of een oefening in de schema-editor.
abstract interface class BlockMember {
  int? get block;
  set block(int? value);
  int? get restSeconds;
  set restSeconds(int? value);
}

/// Rust na een set van [index] (los) of na een ronde van zijn blok: de
/// eerste eigen rust in het blok, anders [defaultRest].
int restAfterIn(List<BlockMember> items, int index, int defaultRest) {
  final r = blockRange([for (final e in items) e.block], index);
  for (var i = r.start; i < r.end; i++) {
    final rest = items[i].restSeconds;
    if (rest != null) return rest;
  }
  return defaultRest;
}

/// Koppelt [index] aan het item erboven: samen één blok, met de rust van
/// wat erboven stond.
void linkWithPreviousIn(List<BlockMember> items, int index) {
  if (index <= 0 || index >= items.length) return;
  final prev = items[index - 1];
  final blocks = [for (final e in items) e.block];
  final prevRange = blockRange(blocks, index - 1);
  int? rest;
  for (var i = prevRange.start; i < prevRange.end; i++) {
    rest ??= items[i].restSeconds;
  }
  final id = prev.block ?? freshBlockId(blocks);
  prev.block = id;
  items[index].block = id;
  normalizeBlocksIn(items);
  final r = blockRange([for (final e in items) e.block], index);
  for (var i = r.start; i < r.end; i++) {
    items[i].restSeconds = rest;
  }
}

/// Haalt [index] uit zijn blok. In het midden van een blok vormen de items
/// eronder een eigen blok, los van die erboven.
void unlinkIn(List<BlockMember> items, int index) {
  final blocks = [for (final e in items) e.block];
  final r = blockRange(blocks, index);
  items[index].block = null;
  if (index > r.start && index + 1 < r.end) {
    final id = freshBlockId(blocks);
    for (var i = index + 1; i < r.end; i++) {
      items[i].block = id;
    }
  }
  normalizeBlocksIn(items);
}

/// Zet de rust van het hele blok waar [index] in zit. Null = standaard.
void setBlockRestIn(List<BlockMember> items, int index, int? seconds) {
  final r = blockRange([for (final e in items) e.block], index);
  for (var i = r.start; i < r.end; i++) {
    items[i].restSeconds = seconds;
  }
}

/// [normalizeBlocks] toegepast op de items zelf (na verwijderen of
/// verslepen).
void normalizeBlocksIn(List<BlockMember> items) {
  final normalized = normalizeBlocks([for (final e in items) e.block]);
  for (var i = 0; i < items.length; i++) {
    items[i].block = normalized[i];
  }
}
