// technique.dart: een techniek uit de bestaande tabel `techniques`, met
// alleen de velden die de Technieken Vault en de live mat-tellers gebruiken.

enum TechniqueGroup {
  strikes('Strikes & Combinaties'),
  throws('Throws & Takedowns'),
  submissions('Submissions & Grondwerk'),
  defense('Verdediging & Counters'),
  other('Overig');

  const TechniqueGroup(this.label);
  final String label;

  /// Strikes tellen in de mat-teller als "Clean Hit / Geblokt / Tegenstoot",
  /// de rest als "Geslaagd / Poging / Gecounterd".
  bool get isStriking => this == TechniqueGroup.strikes;

  /// Wat in het categorieveld staat, vrij ingevuld in de oude app
  /// (Takedown, Submission, Worp, Stoot...).
  static TechniqueGroup fromCategory(String category) {
    final c = category.toLowerCase();
    bool has(List<String> words) => words.any(c.contains);
    if (has(['strike', 'stoot', 'trap', 'kick', 'punch', 'combo', 'combinat', 'elleboog', 'knie'])) {
      return TechniqueGroup.strikes;
    }
    if (has(['takedown', 'throw', 'worp', 'judo', 'leg', 'clinch'])) {
      return TechniqueGroup.throws;
    }
    if (has(['submission', 'grond', 'choke', 'lock', 'armbar', 'guard', 'wurg', 'klem', 'pin', 'hold'])) {
      return TechniqueGroup.submissions;
    }
    if (has(['verdedig', 'defen', 'counter', 'sprawl', 'escape', 'ontsnap'])) {
      return TechniqueGroup.defense;
    }
    return TechniqueGroup.other;
  }

  /// Categorie die we opslaan als je in deze groep een techniek toevoegt.
  String get defaultCategory => switch (this) {
    TechniqueGroup.strikes => 'Strike',
    TechniqueGroup.throws => 'Takedown',
    TechniqueGroup.submissions => 'Submission',
    TechniqueGroup.defense => 'Verdediging',
    TechniqueGroup.other => 'Overig',
  };
}

class Technique {
  final String id;
  final String name;
  final String category;
  final String description;
  final String learningGoal;
  final String transition;
  final bool favorite;
  final int sortOrder;

  /// 'none' | 'next' | 'count' | 'until' (bestaande kolom focus_mode).
  final String focusMode;

  /// Beoordelingen (1-5) uit de updates-historie, oudste eerst.
  final List<int> ratings;

  /// Totaal getelde herhalingen uit de updates-historie.
  final int loggedReps;

  const Technique({
    required this.id,
    required this.name,
    this.category = 'Overig',
    this.description = '',
    this.learningGoal = '',
    this.transition = '',
    this.favorite = false,
    this.sortOrder = 0,
    this.focusMode = 'none',
    this.ratings = const [],
    this.loggedReps = 0,
  });

  factory Technique.fromJson(Map<String, dynamic> j) {
    final updates = (j['updates'] as List?) ?? const [];
    final ratings = <int>[];
    var reps = 0;
    for (final u in updates) {
      if (u is! Map) continue;
      final r = (u['rating'] as num?)?.toInt() ?? 0;
      if (r > 0) ratings.add(r);
      for (final p in (u['positions'] as List?) ?? const []) {
        if (p is Map) reps += (p['reps'] as num?)?.toInt() ?? 0;
      }
    }
    final practiceNext = (j['practice_next'] as bool?) ?? false;
    var focus = (j['focus_mode'] as String?) ?? 'none';
    if (focus == 'none' && practiceNext) focus = 'next';
    return Technique(
      id: j['id'] as String,
      name: j['name'] as String,
      category: (j['category'] as String?) ?? 'Overig',
      description: (j['description'] as String?) ?? '',
      learningGoal: (j['learning_goal'] as String?) ?? '',
      transition: (j['transition'] as String?) ?? '',
      favorite: (j['favorite'] as bool?) ?? false,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      focusMode: focus,
      ratings: ratings,
      loggedReps: reps,
    );
  }

  TechniqueGroup get group => TechniqueGroup.fromCategory(category);

  bool get isInFocus => focusMode != 'none';

  /// Mastery Index (0..100): gemiddelde van de laatste 5 beoordelingen,
  /// of null als je de techniek nog nooit beoordeeld hebt.
  int? get masteryPercent {
    if (ratings.isEmpty) return null;
    final recent = ratings.length > 5
        ? ratings.sublist(ratings.length - 5)
        : ratings;
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    return (avg / 5 * 100).round();
  }

  /// "Target / Doelwit": je leerdoel, anders de overgang of de categorie.
  String get targetLabel {
    if (learningGoal.trim().isNotEmpty) return learningGoal.trim();
    if (transition.trim().isNotEmpty) return transition.trim();
    return category;
  }

  Technique copyWith({String? focusMode, bool? favorite}) => Technique(
    id: id,
    name: name,
    category: category,
    description: description,
    learningGoal: learningGoal,
    transition: transition,
    favorite: favorite ?? this.favorite,
    sortOrder: sortOrder,
    focusMode: focusMode ?? this.focusMode,
    ratings: ratings,
    loggedReps: loggedReps,
  );
}

/// De drie tellers per techniek tijdens een live sessie.
class TechniqueCounts {
  final int success;
  final int attempts;
  final int countered;
  const TechniqueCounts({this.success = 0, this.attempts = 0, this.countered = 0});

  TechniqueCounts add(TechniqueStat stat, int delta) {
    int f(int v) => (v + delta).clamp(0, 9999);
    return switch (stat) {
      TechniqueStat.success => TechniqueCounts(success: f(success), attempts: attempts, countered: countered),
      TechniqueStat.attempt => TechniqueCounts(success: success, attempts: f(attempts), countered: countered),
      TechniqueStat.countered => TechniqueCounts(success: success, attempts: attempts, countered: f(countered)),
    };
  }

  int operator [](TechniqueStat s) => switch (s) {
    TechniqueStat.success => success,
    TechniqueStat.attempt => attempts,
    TechniqueStat.countered => countered,
  };

  int get total => success + attempts + countered;

  Map<String, dynamic> toJson() => {
    'success': success,
    'attempts': attempts,
    'countered': countered,
  };

  factory TechniqueCounts.fromJson(Map<String, dynamic> j) => TechniqueCounts(
    success: (j['success'] as num?)?.toInt() ?? 0,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    countered: (j['countered'] as num?)?.toInt() ?? 0,
  );
}

enum TechniqueStat { success, attempt, countered }

String statLabel(TechniqueStat stat, {required bool striking}) => switch (stat) {
  TechniqueStat.success => striking ? 'Clean Hit' : 'Geslaagd',
  TechniqueStat.attempt => striking ? 'Geblokt' : 'Poging',
  TechniqueStat.countered => striking ? 'Tegenstoot' : 'Gecounterd',
};
