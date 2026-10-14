// exercise.dart — een zelfgemaakte oefening voor krachttraining, los van de
// vaste lijst in exercise_library.dart. Naam + optionele beschrijving (hoe
// voer je 'm uit, waar let je op) en video's, zoals bij technieken.

class Exercise {
  final String id;
  final String name;
  final String description;
  final List<String> videoUrls;

  const Exercise({
    required this.id,
    required this.name,
    this.description = '',
    this.videoUrls = const [],
  });

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    videoUrls: ((json['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'description': description,
    'video_urls': videoUrls,
  };

  Exercise copyWith({
    String? name,
    String? description,
    List<String>? videoUrls,
  }) => Exercise(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    videoUrls: videoUrls ?? this.videoUrls,
  );
}
