// combination.dart: een combinatie van technieken in volgorde (bv. Harai
// Goshi → O-soto-gari), uit de bestaande tabel `combinations` (zelfde
// formaat als de oude app). Te loggen tijdens trainingen.

enum ComboType {
  strikes('Strikes'),
  takedowns('Takedowns'),
  mixed('Gemixed');

  const ComboType(this.label);
  final String label;

  static ComboType fromName(String? name) => switch (name) {
    'strikes' => ComboType.strikes,
    'takedowns' => ComboType.takedowns,
    _ => ComboType.mixed,
  };
}

class Combination {
  const Combination({
    required this.id,
    required this.name,
    this.type = ComboType.mixed,
    this.techniques = const [],
    this.note = '',
    this.videoUrls = const [],
    this.favorite = false,
  });

  final String id;
  final String name;
  final ComboType type;

  /// Techniek-namen in volgorde van uitvoering.
  final List<String> techniques;
  final String note;
  final List<String> videoUrls;
  final bool favorite;

  /// "Harai Goshi → O-soto-gari", of de naam als er geen stappen zijn.
  String get sequence => techniques.isEmpty ? name : techniques.join(' → ');

  factory Combination.fromJson(Map<String, dynamic> j) => Combination(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    type: ComboType.fromName(j['type'] as String?),
    techniques: [for (final t in (j['techniques'] as List?) ?? const []) if (t is String) t],
    note: (j['note'] as String?) ?? '',
    videoUrls: [for (final v in (j['video_urls'] as List?) ?? const []) if (v is String) v],
    favorite: (j['favorite'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'techniques': techniques,
    'note': note,
    'video_urls': videoUrls,
    'favorite': favorite,
  };

  Combination copyWith({
    String? id,
    String? name,
    ComboType? type,
    List<String>? techniques,
    String? note,
    List<String>? videoUrls,
    bool? favorite,
  }) => Combination(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    techniques: techniques ?? this.techniques,
    note: note ?? this.note,
    videoUrls: videoUrls ?? this.videoUrls,
    favorite: favorite ?? this.favorite,
  );
}
