// technique.dart: een techniek uit de bestaande tabel `techniques`, met
// alleen de velden die de Technieken Vault en de live mat-tellers gebruiken.

/// Hoofdcategorieën van de Technique Vault (namen volgens kinetic-design:
/// expliciet "Striking", niet "Strikes").
enum TechniqueGroup {
  throws('Throws', 'Worpen & takedowns'),
  striking('Striking', 'Stoten, trappen & combinaties'),
  submissions('Submissions & Locks', 'Klemmen, armbars & chokes'),
  sweeps('Sweeps & Guard Passes', 'Reversals & passes'),
  control('Controle & Pins', 'Posities en houdgrepen'),
  defense('Verdediging & Counters', 'Escapes, sprawls & counters'),
  other('Overig', 'Overige technieken');

  const TechniqueGroup(this.label, this.description);
  final String label;
  final String description;

  /// Striking telt op de mat als "Clean Hit / Geblokt / Tegenstoot", de rest
  /// als "Geslaagd / Poging / Gecounterd".
  bool get isStriking => this == TechniqueGroup.striking;

  /// Indeling op basis van categorie (Takedown/Submission/Strike/Overig) en
  /// subcategorie uit de bibliotheek, of vrije tekst uit de oude app.
  static TechniqueGroup classify(String category, [String subcategory = '']) {
    final c = category.toLowerCase();
    final sub = subcategory.toLowerCase();
    bool has(String s, List<String> words) => words.any(s.contains);
    if (sub.isNotEmpty) {
      if (has(sub, ['defense', 'escape', 'counter'])) return TechniqueGroup.defense;
      if (has(sub, ['sweep', 'pass'])) return TechniqueGroup.sweeps;
      if (has(sub, ['control', 'pin', 'hold'])) return TechniqueGroup.control;
    }
    if (has(c, ['strike', 'stoot', 'trap', 'kick', 'punch', 'combo', 'combinat', 'elleboog', 'knie', 'boks'])) {
      return TechniqueGroup.striking;
    }
    if (has(c, ['takedown', 'throw', 'worp', 'judo', 'leg entry', 'clinch'])) return TechniqueGroup.throws;
    if (has(c, ['submission', 'choke', 'lock', 'armbar', 'wurg', 'klem'])) return TechniqueGroup.submissions;
    if (has(c, ['sweep', 'pass', 'guard'])) return TechniqueGroup.sweeps;
    if (has(c, ['verdedig', 'defen', 'counter', 'sprawl', 'escape', 'ontsnap'])) return TechniqueGroup.defense;
    if (has(c, ['control', 'pin', 'hold', 'grond', 'mount'])) return TechniqueGroup.control;
    return TechniqueGroup.other;
  }

  /// Alias voor oudere code.
  static TechniqueGroup fromCategory(String category) => classify(category);

  /// Categorie die we opslaan als je in deze groep een techniek toevoegt.
  String get defaultCategory => switch (this) {
    TechniqueGroup.striking => 'Strike',
    TechniqueGroup.throws => 'Takedown',
    TechniqueGroup.submissions => 'Submission',
    TechniqueGroup.sweeps => 'Sweep',
    TechniqueGroup.control => 'Control',
    TechniqueGroup.defense => 'Verdediging',
    TechniqueGroup.other => 'Overig',
  };
}

/// Eén beoordeling/notitie van een techniek (kolom `updates`, zelfde formaat
/// als de oude app: {at, rating, note, positions:[{reps, went_well, to_improve}]}).
class TechniqueUpdate {
  const TechniqueUpdate({
    required this.at,
    this.rating = 0,
    this.note = '',
    this.wentWell = '',
    this.toImprove = '',
    this.reps = 0,
  });

  final DateTime at;

  /// 1-5, 0 = geen beoordeling.
  final int rating;
  final String note;
  final String wentWell;
  final String toImprove;
  final int reps;

  bool get isReview => rating > 0 || note.trim().isNotEmpty || wentWell.trim().isNotEmpty || toImprove.trim().isNotEmpty;

  factory TechniqueUpdate.fromJson(Map<dynamic, dynamic> j) {
    var wentWell = '';
    var toImprove = '';
    var reps = 0;
    for (final p in (j['positions'] as List?) ?? const []) {
      if (p is! Map) continue;
      reps += (p['reps'] as num?)?.toInt() ?? 0;
      final w = (p['went_well'] as String?)?.trim() ?? '';
      final t = (p['to_improve'] as String?)?.trim() ?? '';
      if (w.isNotEmpty) wentWell = wentWell.isEmpty ? w : '$wentWell\n$w';
      if (t.isNotEmpty) toImprove = toImprove.isEmpty ? t : '$toImprove\n$t';
    }
    return TechniqueUpdate(
      at: DateTime.tryParse((j['at'] as String?) ?? '')?.toLocal() ?? DateTime(2000),
      rating: (j['rating'] as num?)?.toInt() ?? 0,
      note: (j['note'] as String?) ?? '',
      wentWell: wentWell,
      toImprove: toImprove,
      reps: reps,
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'rating': rating,
    'note': note,
    'positions': [
      {'position': '', 'rating': rating, 'reps': reps, 'went_well': wentWell, 'to_improve': toImprove},
    ],
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

  /// Bibliotheektechniek waar deze eigen techniek een kopie van is.
  final String? libraryId;

  /// Video's: links (YouTube, Instagram, TikTok...) of eigen uploads
  /// (`storage://technique-videos/...`).
  final List<String> videoUrls;

  /// Volledige historie (beoordelingen, notities, reps), oudste eerst.
  final List<TechniqueUpdate> updates;

  /// Alleen de echte beoordelingen/notities, nieuwste eerst.
  List<TechniqueUpdate> get reviews => updates.where((u) => u.isReview).toList().reversed.toList();

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
    this.libraryId,
    this.videoUrls = const [],
    this.updates = const [],
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
      libraryId: j['library_id'] as String?,
      videoUrls: [
        for (final v in (j['video_urls'] as List?) ?? const [])
          if (v is String && v.trim().isNotEmpty) v,
        if (((j['video_url'] as String?) ?? '').trim().isNotEmpty && !((j['video_urls'] as List?) ?? const []).contains(j['video_url']))
          j['video_url'] as String,
      ],
      updates: [
        for (final u in updates)
          if (u is Map) TechniqueUpdate.fromJson(u),
      ],
    );
  }

  TechniqueGroup get group => TechniqueGroup.classify(category);

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

  Technique copyWith({
    String? focusMode,
    bool? favorite,
    int? loggedReps,
    String? description,
    List<String>? videoUrls,
    List<TechniqueUpdate>? updates,
  }) => Technique(
    id: id,
    name: name,
    category: category,
    description: description ?? this.description,
    learningGoal: learningGoal,
    transition: transition,
    favorite: favorite ?? this.favorite,
    sortOrder: sortOrder,
    focusMode: focusMode ?? this.focusMode,
    ratings: updates == null ? ratings : [for (final u in updates) if (u.rating > 0) u.rating],
    loggedReps: loggedReps ?? this.loggedReps,
    libraryId: libraryId,
    videoUrls: videoUrls ?? this.videoUrls,
    updates: updates ?? this.updates,
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
