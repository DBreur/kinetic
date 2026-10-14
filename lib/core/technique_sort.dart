// technique_sort.dart — sorteerregels voor de technieklijst in het tabblad
// Technieken, los van de UI (shell_screen.dart) zodat ze zonder widgets op
// te zetten te testen zijn. Favorieten komen altijd bovenaan, ongeacht de
// gekozen sortering — zie [sortTechniques].

import '../models/technique.dart';

enum TechniqueSort {
  nameAsc,
  nameDesc,
  dateAddedNewest,
  dateAddedOldest,
  lastPracticedNewest,
  learningStatus;

  String get label => switch (this) {
    TechniqueSort.nameAsc => 'Naam (A-Z)',
    TechniqueSort.nameDesc => 'Naam (Z-A)',
    TechniqueSort.dateAddedNewest => 'Datum toegevoegd — nieuwste eerst',
    TechniqueSort.dateAddedOldest => 'Datum toegevoegd — oudste eerst',
    TechniqueSort.lastPracticedNewest => 'Laatst beoefend — nieuwste eerst',
    TechniqueSort.learningStatus => 'Leerstatus',
  };
}

/// Volgorde van leerstatussen binnen de sorteeroptie "Leerstatus" — wat nu
/// aandacht vraagt (bezig) eerst, wat al af is (beheerst) laatst.
int learningSortPriority(LearningStatus s) => switch (s) {
  LearningStatus.learning => 0,
  LearningStatus.planned => 1,
  LearningStatus.none => 2,
  LearningStatus.mastered => 3,
};

/// Minimale gegevens die de sortering nodig heeft — een rij in de
/// technieklijst (`_TechniqueStat`) implementeert dit zonder extra werk,
/// want die heeft deze velden al als gelijknamige getters.
abstract class TechniqueSortable {
  String get name;
  bool get favorite;
  DateTime? get createdAt;
  DateTime? get lastDate;
  LearningStatus get learningStatus;
}

/// De eigenlijke sorteervergelijking, los van de favorieten-eerst-regel —
/// zie [sortTechniques].
int compareTechniqueSortables(
  TechniqueSortable a,
  TechniqueSortable b,
  TechniqueSort sort,
) {
  switch (sort) {
    case TechniqueSort.nameAsc:
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case TechniqueSort.nameDesc:
      return b.name.toLowerCase().compareTo(a.name.toLowerCase());
    case TechniqueSort.dateAddedNewest:
      return (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      );
    case TechniqueSort.dateAddedOldest:
      return (a.createdAt ?? DateTime(1970)).compareTo(
        b.createdAt ?? DateTime(1970),
      );
    case TechniqueSort.lastPracticedNewest:
      return (b.lastDate ?? DateTime(0)).compareTo(a.lastDate ?? DateTime(0));
    case TechniqueSort.learningStatus:
      final cmp = learningSortPriority(
        a.learningStatus,
      ).compareTo(learningSortPriority(b.learningStatus));
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// Sorteert [items] in place: favorieten altijd bovenaan, daarbinnen op
/// [sort].
void sortTechniques<T extends TechniqueSortable>(
  List<T> items,
  TechniqueSort sort,
) {
  items.sort((a, b) {
    if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
    return compareTechniqueSortables(a, b, sort);
  });
}
