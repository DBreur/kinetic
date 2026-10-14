// workout_template.dart — een opgeslagen trainingsschema voor krachttraining
// ("Dag 1", "Push day", ...): een naam plus een vaste lijst oefeningen met
// vaste sets (kg/reps). Gebruikt als startpunt voor een nieuwe sessie — de
// sets blijven daarna gewoon aanpasbaar, precies zoals handmatig toegevoegde
// oefeningen.

import 'circuit.dart';
import 'training_session.dart' show ExerciseEntry;

export 'circuit.dart';
export 'training_session.dart' show ExerciseEntry, ExerciseSet;

class WorkoutTemplate {
  final String id;
  final String name;
  final List<ExerciseEntry> exercises;

  /// Circuits die in dit schema zijn opgenomen — embedded kopieën, geen
  /// live referentie naar de opgeslagen circuits in Instellingen.
  final List<Circuit> circuits;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    this.exercises = const [],
    this.circuits = const [],
  });

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      WorkoutTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        exercises: ((json['exercises'] as List?) ?? [])
            .map((e) => ExerciseEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        circuits: ((json['circuits'] as List?) ?? [])
            .map((e) => Circuit.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'circuits': circuits.map((c) => c.toJson()).toList(),
  };

  WorkoutTemplate copyWith({
    String? name,
    List<ExerciseEntry>? exercises,
    List<Circuit>? circuits,
  }) => WorkoutTemplate(
    id: id,
    name: name ?? this.name,
    exercises: exercises ?? this.exercises,
    circuits: circuits ?? this.circuits,
  );
}
