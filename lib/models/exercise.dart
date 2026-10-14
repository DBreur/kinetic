// exercise.dart — een zelfgemaakte oefening voor krachttraining, los van de
// vaste lijst in exercise_library.dart. Naam + optionele beschrijving (hoe
// voer je 'm uit, waar let je op).

class Exercise {
  final String id;
  final String name;
  final String description;

  const Exercise({required this.id, required this.name, this.description = ''});

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'description': description,
  };

  Exercise copyWith({String? name, String? description}) => Exercise(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
  );
}
