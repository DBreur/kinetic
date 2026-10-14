// exercise.dart — een zelfgemaakte oefening voor krachttraining, los van de
// vaste lijst in exercise_library.dart. Naam + optionele beschrijving (hoe
// voer je 'm uit, waar let je op), video's zoals bij technieken, en de
// spiergroepen die hij traint (geen, één of meer — zie muscle_groups.dart).

class Exercise {
  final String id;
  final String name;
  final String description;
  final List<String> videoUrls;
  final List<String> muscleGroups;

  const Exercise({
    required this.id,
    required this.name,
    this.description = '',
    this.videoUrls = const [],
    this.muscleGroups = const [],
  });

  /// Nog niet opgeslagen (bv. een oefening uit de vaste lijst die je nog
  /// nooit hebt aangepast).
  bool get isSaved => id.isNotEmpty;

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    videoUrls: ((json['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    muscleGroups: ((json['muscle_groups'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
  );

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'description': description,
    'video_urls': videoUrls,
    'muscle_groups': muscleGroups,
  };

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    ...toUpdateJson(),
  };

  Exercise copyWith({
    String? name,
    String? description,
    List<String>? videoUrls,
    List<String>? muscleGroups,
  }) => Exercise(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    videoUrls: videoUrls ?? this.videoUrls,
    muscleGroups: muscleGroups ?? this.muscleGroups,
  );
}
