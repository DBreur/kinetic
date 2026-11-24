// library.dart: de gedeelde technieken-bibliotheek (`technique_library`,
// 134 technieken, alleen-lezen) en de "vault": alle technieken samen,
// bibliotheek + eigen technieken, zodat de Technieken-tab alles toont.

import 'dart:convert';

import 'technique.dart';

/// Discipline-codes uit de database → leesbare naam.
const kDisciplineLabels = {
  'sambo': 'Sambo',
  'bjj': 'BJJ',
  'judo': 'Judo',
  'mma': 'MMA',
  'wrestling': 'Worstelen',
  'boxing': 'Boksen',
  'kickboxing': 'Kickboksen',
  'muay_thai': 'Muay Thai',
  'karate': 'Karate',
};

String disciplineLabel(String code) => kDisciplineLabels[code] ?? code;

String difficultyLabel(int d) => switch (d) {
  1 => 'Beginner',
  2 => 'Gevorderd',
  _ => 'Expert',
};

/// De bibliotheek is ooit geseed met dubbel-gecodeerde UTF-8 ("KnieÃ«n").
/// Dit draait dat terug; correcte tekst blijft ongewijzigd.
String repairMojibake(String s) {
  if (!s.contains('Ã') && !s.contains('Â')) return s;
  var current = s;
  for (var i = 0; i < 3; i++) {
    try {
      final bytes = latin1.encode(current);
      final next = utf8.decode(bytes);
      if (next == current) break;
      current = next;
    } catch (_) {
      break;
    }
    if (!current.contains('Ã') && !current.contains('Â')) break;
  }
  return current;
}

List<String> _strings(Object? v) =>
    ((v as List?) ?? const []).map((e) => repairMojibake(e as String)).toList();

class LibraryTechnique {
  final String id;
  final String name;

  /// Takedown / Submission / Strike / Overig.
  final String category;

  /// Throw, Takedown, Choke, Armlock, Leglock, Sweep, Pass, Punch, Kick, ...
  final String subcategory;
  final String transition;
  final List<String> disciplines;
  final List<String> tags;
  final String description;
  final List<String> videoUrls;
  final int difficulty;

  /// Alleen bij strikes: telcode zoals "1" (jab) of "LK".
  final String? strikeCode;

  const LibraryTechnique({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory = '',
    this.transition = '',
    this.disciplines = const [],
    this.tags = const [],
    this.description = '',
    this.videoUrls = const [],
    this.difficulty = 1,
    this.strikeCode,
  });

  factory LibraryTechnique.fromJson(Map<String, dynamic> j) => LibraryTechnique(
    id: j['id'] as String,
    name: repairMojibake(j['name'] as String),
    category: (j['category'] as String?) ?? 'Overig',
    subcategory: repairMojibake((j['subcategory'] as String?) ?? ''),
    transition: repairMojibake((j['transition'] as String?) ?? ''),
    disciplines: _strings(j['disciplines']),
    tags: _strings(j['tags']),
    description: repairMojibake((j['description'] as String?) ?? ''),
    videoUrls: _strings(j['video_urls']),
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 1,
    strikeCode: j['strike_code'] as String?,
  );

  TechniqueGroup get group => TechniqueGroup.classify(category, subcategory);

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        subcategory.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        (strikeCode?.toLowerCase() == q) ||
        tags.any((t) => t.toLowerCase().contains(q)) ||
        disciplines.any((d) => disciplineLabel(d).toLowerCase().contains(q));
  }
}

/// Eén regel in de Technieken-vault: een eigen techniek, een
/// bibliotheektechniek, of beide (eigen kopie van een bibliotheektechniek).
class VaultEntry {
  final Technique? own;
  final LibraryTechnique? library;

  const VaultEntry({this.own, this.library}) : assert(own != null || library != null);

  /// Stabiele sleutel: eigen id, anders `lib:<library id>`.
  String get key => own?.id ?? 'lib:${library!.id}';

  bool get isOwn => own != null;
  String get name => own?.name ?? library!.name;

  TechniqueGroup get group =>
      library?.group ?? TechniqueGroup.classify(own!.category);

  bool get isStriking => group.isStriking;
  bool get inFocus => own?.isInFocus ?? false;
  bool get favorite => own?.favorite ?? false;

  /// "Throw • Sambo, Judo" of de eigen categorie.
  String get subtitle {
    final lib = library;
    if (lib != null) {
      final disc = lib.disciplines.take(3).map(disciplineLabel).join(', ');
      return [if (lib.subcategory.isNotEmpty) lib.subcategory, if (disc.isNotEmpty) disc].join(' • ');
    }
    return own!.category;
  }

  String get description {
    final d = own?.description.trim() ?? '';
    return d.isNotEmpty ? d : (library?.description ?? '');
  }

  List<String> get disciplines => library?.disciplines ?? const [];
  int? get difficulty => library?.difficulty;
  int get loggedReps => own?.loggedReps ?? 0;
  int? get masteryPercent => own?.masteryPercent;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (own != null && own!.category.toLowerCase().contains(q)) return true;
    return library?.matches(q) ?? false;
  }
}

/// Voegt bibliotheek en eigen technieken samen. Een eigen techniek hoort bij
/// een bibliotheektechniek via library_id, of (oudere rijen) via exact
/// dezelfde naam.
List<VaultEntry> buildVault(List<Technique> own, List<LibraryTechnique> library) {
  final byLibId = {for (final l in library) l.id: l};
  final byName = {for (final l in library) l.name.toLowerCase().trim(): l};
  final claimed = <String>{};
  final entries = <VaultEntry>[];
  for (final t in own) {
    LibraryTechnique? lib;
    final libId = t.libraryId;
    if (libId != null) lib = byLibId[libId];
    lib ??= byName[t.name.toLowerCase().trim()];
    if (lib != null && claimed.contains(lib.id)) lib = null;
    if (lib != null) claimed.add(lib.id);
    entries.add(VaultEntry(own: t, library: lib));
  }
  for (final l in library) {
    if (!claimed.contains(l.id)) entries.add(VaultEntry(library: l));
  }
  entries.sort((a, b) {
    if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return entries;
}
