// exercise_library.dart — de lijst met oefeningen voor krachttraining.
//
// Vervang deze lijst door je eigen oefeningen; alle schermen die oefeningen
// laten kiezen (live krachttraining, circuits, schema's, training achteraf
// aanpassen) lezen uit deze ene plek, aangevuld met je eigen oefeningen.

import '../models/exercise.dart';

/// Leeg: alleen je eigen oefeningen staan in de lijst. Zet hier namen neer
/// als je toch een vaste startlijst wilt.
const kExerciseLibrary = <String>[];

/// De spiergroepen die je aan een oefening kunt hangen — ook de vlakken van
/// het spierfiguurtje (zie widgets/muscle_figure.dart).
const kMuscleGroups = [
  'Nek',
  'Schouders',
  'Borst',
  'Biceps',
  'Triceps',
  'Onderarmen',
  'Buik',
  'Bovenrug',
  'Lats',
  'Onderrug',
  'Billen',
  'Quadriceps',
  'Hamstrings',
  'Kuiten',
];

/// Standaard spiergroepen voor de vaste lijst — tot je ze zelf aanpast.
const kLibraryMuscleGroups = <String, List<String>>{};

/// Alle oefeningen om uit te kiezen: je eigen oefeningen plus de vaste lijst
/// (die nog geen eigen versie heeft), A–Z. Een vaste oefening zonder eigen
/// versie krijgt zijn standaard spiergroepen en een leeg id.
List<Exercise> allExercises(List<Exercise> custom) {
  final byName = {for (final e in custom) e.name.toLowerCase(): e};
  final result = <Exercise>[...custom];
  for (final name in kExerciseLibrary) {
    if (!byName.containsKey(name.toLowerCase())) {
      result.add(
        Exercise(
          id: '',
          name: name,
          muscleGroups: kLibraryMuscleGroups[name] ?? const [],
        ),
      );
    }
  }
  return sortExercises(result);
}

/// A–Z (of Z–A), zonder op hoofdletters te letten.
List<Exercise> sortExercises(List<Exercise> list, {bool ascending = true}) {
  final sorted = List.of(list)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return ascending ? sorted : sorted.reversed.toList();
}

/// Zoeken op naam en filteren op spiergroepen: een oefening telt mee als hij
/// minstens één van de gekozen [groups] traint (leeg = geen filter).
List<Exercise> filterExercises(
  List<Exercise> list, {
  String query = '',
  Set<String> groups = const {},
  bool ascending = true,
}) {
  final q = query.trim().toLowerCase();
  return sortExercises(
    list
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
        .where(
          (e) => groups.isEmpty || e.muscleGroups.any(groups.contains),
        )
        .toList(),
    ascending: ascending,
  );
}
