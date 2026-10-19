// technique.dart — een techniek die je los van een training kunt bijhouden:
// naam, categorie en een logboek van updates (hoe ging het, wanneer).

/// Eén update over een techniek: een moment waarop je noteerde hoe het ging.
/// Los toegevoegd (vanuit het Technieken-tabblad) of automatisch aangemaakt
/// bij het opslaan van een sambo-sessie waarin de techniek behandeld werd.
class TechniqueUpdate {
  final DateTime at;
  final int rating; // 0 = geen beoordeling, alleen een notitie
  final String note;

  const TechniqueUpdate({required this.at, this.rating = 0, this.note = ''});

  factory TechniqueUpdate.fromJson(Map<String, dynamic> json) =>
      TechniqueUpdate(
        at: DateTime.parse(json['at'] as String).toLocal(),
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        note: (json['note'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'rating': rating,
    'note': note,
  };
}

/// Hoever je bent met het leren van een techniek — los van de losse
/// updates/beoordelingen hieronder, die blijven gewoon bestaan.
enum LearningStatus {
  none,
  planned,
  learning,
  mastered;

  static LearningStatus fromName(String? name) => switch (name) {
    'planned' => LearningStatus.planned,
    'learning' => LearningStatus.learning,
    'mastered' => LearningStatus.mastered,
    _ => LearningStatus.none,
  };

  String get label => switch (this) {
    LearningStatus.none => '—',
    LearningStatus.planned => 'Gepland',
    LearningStatus.learning => 'Bezig met leren',
    LearningStatus.mastered => 'Beheerst',
  };
}

/// Technieken die van `planned` naar `learning` gaan omdat hun naam
/// voorkomt tussen de behandelde technieken van een sessie — losse, pure
/// functie zodat deze regel apart van de opslaglogica (en zonder netwerk)
/// te testen is. Vergelijkt namen hoofdletterongevoelig.
List<Technique> techniquesToStartLearning(
  List<Technique> knownTechniques,
  List<String> coveredNames,
) {
  final covered = coveredNames.map((n) => n.toLowerCase()).toSet();
  return knownTechniques
      .where(
        (t) =>
            t.learningStatus == LearningStatus.planned &&
            covered.contains(t.name.toLowerCase()),
      )
      .toList();
}

class Technique {
  final String id;
  final String name;
  final String category;

  /// Bijv. "Staand -> Grond" — de positiewisseling die de techniek maakt.
  /// Leeg als er geen transitie van toepassing is.
  final String transition;
  final bool favorite;

  /// Uitleg over de techniek — hoe voer je hem uit, waar let je op.
  final String description;

  /// Links naar video's van de techniek, te bekijken binnen de app (zowel
  /// bij het aanpassen van de techniek als tijdens een sessie) — meerdere
  /// video's per techniek toegestaan.
  final List<String> videoUrls;
  final List<TechniqueUpdate> updates;

  /// Volgorde in het tabblad Technieken en de "Lijst aanpassen"-weergave van
  /// de techniekkaart — lager eerst. Los van `name`, zodat je zelf kunt
  /// herordenen.
  final int sortOrder;

  final LearningStatus learningStatus;

  /// Datum waarop je gepland hebt deze techniek te oefenen — zetten terwijl
  /// [learningStatus] nog `none` is, zet die status automatisch op `planned`.
  final DateTime? plannedFor;

  /// Wat je met deze techniek wil bereiken — alleen relevant bij `planned`/
  /// `learning`.
  final String learningGoal;

  /// Moment waarop de status `learning` werd (bv. doordat de techniek
  /// "behandeld" is in een sessie terwijl hij gepland stond).
  final DateTime? learningStartedAt;

  /// Wanneer deze techniek is aangemaakt — voor het sorteren op "datum
  /// toegevoegd" in het tabblad Technieken. Komt rechtstreeks uit de
  /// database (`created_at`, al aanwezig sinds de eerste migratie), dus
  /// alleen gezet bij het inlezen — niet handmatig aan te passen.
  final DateTime? createdAt;

  /// Specifiekere grondposities (bv. "Half guard", "Mount") waarvandaan deze
  /// techniek werkt — alleen relevant bij een techniek die naar "Submission"
  /// gaat, en altijd optioneel: leeg is een geldige, bewust gekozen waarde
  /// ("niet gespecificeerd"). Meerdere mogelijk, want eenzelfde afwerking
  /// lukt vaak vanuit meer dan één positie.
  final List<String> groundPositions;

  /// "Oefenen bij de eerstvolgende training" — ook als die niet gepland is.
  /// Wordt gewist zodra er een training met deze techniek is opgeslagen.
  final bool practiceNext;

  const Technique({
    required this.id,
    required this.name,
    this.category = 'Overig',
    this.transition = '',
    this.favorite = false,
    this.description = '',
    this.videoUrls = const [],
    this.updates = const [],
    this.sortOrder = 0,
    this.learningStatus = LearningStatus.none,
    this.plannedFor,
    this.groundPositions = const [],
    this.practiceNext = false,
    this.learningGoal = '',
    this.learningStartedAt,
    this.createdAt,
  });

  factory Technique.fromJson(Map<String, dynamic> json) => Technique(
    id: json['id'] as String,
    name: json['name'] as String,
    category: (json['category'] as String?) ?? 'Overig',
    transition: (json['transition'] as String?) ?? '',
    favorite: (json['favorite'] as bool?) ?? false,
    description: (json['description'] as String?) ?? '',
    videoUrls: ((json['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    updates: ((json['updates'] as List?) ?? [])
        .map((e) => TechniqueUpdate.fromJson(e as Map<String, dynamic>))
        .toList(),
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    learningStatus: LearningStatus.fromName(
      json['learning_status'] as String?,
    ),
    plannedFor: json['planned_for'] == null
        ? null
        : DateTime.parse(json['planned_for'] as String).toLocal(),
    learningGoal: (json['learning_goal'] as String?) ?? '',
    learningStartedAt: json['learning_started_at'] == null
        ? null
        : DateTime.parse(json['learning_started_at'] as String).toLocal(),
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String).toLocal(),
    groundPositions: ((json['ground_positions'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    practiceNext: (json['practice_next'] as bool?) ?? false,
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'category': category,
    'transition': transition,
    'favorite': favorite,
    'description': description,
    'video_urls': videoUrls,
    'updates': updates.map((u) => u.toJson()).toList(),
    'sort_order': sortOrder,
    'learning_status': learningStatus.name,
    'planned_for': plannedFor?.toUtc().toIso8601String(),
    'learning_goal': learningGoal,
    'learning_started_at': learningStartedAt?.toUtc().toIso8601String(),
    'ground_positions': groundPositions,
  };

  Technique copyWith({
    String? name,
    String? category,
    String? transition,
    bool? favorite,
    String? description,
    List<String>? videoUrls,
    List<TechniqueUpdate>? updates,
    int? sortOrder,
    LearningStatus? learningStatus,
    DateTime? plannedFor,
    bool clearPlannedFor = false,
    String? learningGoal,
    DateTime? learningStartedAt,
    bool clearLearningStartedAt = false,
    List<String>? groundPositions,
    bool? practiceNext,
  }) => Technique(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    transition: transition ?? this.transition,
    favorite: favorite ?? this.favorite,
    description: description ?? this.description,
    videoUrls: videoUrls ?? this.videoUrls,
    updates: updates ?? this.updates,
    sortOrder: sortOrder ?? this.sortOrder,
    learningStatus: learningStatus ?? this.learningStatus,
    plannedFor: clearPlannedFor ? null : (plannedFor ?? this.plannedFor),
    groundPositions: groundPositions ?? this.groundPositions,
    practiceNext: practiceNext ?? this.practiceNext,
    learningGoal: learningGoal ?? this.learningGoal,
    learningStartedAt: clearLearningStartedAt
        ? null
        : (learningStartedAt ?? this.learningStartedAt),
    createdAt: createdAt,
  );
}
