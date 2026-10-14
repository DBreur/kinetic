// combination.dart — een combinatie van meerdere technieken die je als één
// geheel oefent (bv. alleen strikes, alleen takedowns, of gemixed).

enum ComboType {
  strikes,
  takedowns,
  mixed;

  static ComboType fromName(String? name) => switch (name) {
    'strikes' => ComboType.strikes,
    'takedowns' => ComboType.takedowns,
    _ => ComboType.mixed,
  };

  String get label => switch (this) {
    ComboType.strikes => 'Strikes',
    ComboType.takedowns => 'Takedowns',
    ComboType.mixed => 'Gemixed',
  };
}

class Combination {
  final String id;
  final String name;
  final ComboType type;

  /// Namen van technieken, in volgorde van uitvoering. Mag leeg zijn — een
  /// combinatie is al bruikbaar met alleen een naam, bv. als plekhouder die
  /// je later aanvult.
  final List<String> techniques;
  final String note;

  /// Links naar video's van de combinatie als geheel, zoals bij
  /// [Technique.videoUrls] — meerdere video's toegestaan.
  final List<String> videoUrls;

  /// Favoriet — bovenaan te filteren in de combinatielijst, net als bij
  /// [Technique.favorite].
  final bool favorite;

  const Combination({
    required this.id,
    required this.name,
    this.type = ComboType.mixed,
    this.techniques = const [],
    this.note = '',
    this.videoUrls = const [],
    this.favorite = false,
  });

  factory Combination.fromJson(Map<String, dynamic> json) => Combination(
    id: json['id'] as String,
    name: json['name'] as String,
    type: ComboType.fromName(json['type'] as String?),
    techniques: ((json['techniques'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    note: (json['note'] as String?) ?? '',
    videoUrls: ((json['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    favorite: (json['favorite'] as bool?) ?? false,
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'type': type.name,
    'techniques': techniques,
    'note': note,
    'video_urls': videoUrls,
    'favorite': favorite,
  };

  Combination copyWith({
    String? name,
    ComboType? type,
    List<String>? techniques,
    String? note,
    List<String>? videoUrls,
    bool? favorite,
  }) => Combination(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    techniques: techniques ?? this.techniques,
    note: note ?? this.note,
    videoUrls: videoUrls ?? this.videoUrls,
    favorite: favorite ?? this.favorite,
  );
}
