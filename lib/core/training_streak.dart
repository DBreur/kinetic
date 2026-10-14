// training_streak.dart — pure berekening van een trainingsstreak, puur op
// basis van de datums waarop sessies zijn opgeslagen (meerdere sessies op
// dezelfde dag tellen als één dag).

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

class TrainingStreak {
  /// Aantal opeenvolgende dagen tot en met vandaag (of tot en met gisteren
  /// als er vandaag nog niet getraind is) waarop minstens één sessie was.
  final int consecutiveDays;

  /// Aantal verschillende dagen met een sessie in de laatste 7 dagen
  /// (inclusief vandaag).
  final int daysInLastWeek;

  const TrainingStreak({
    required this.consecutiveDays,
    required this.daysInLastWeek,
  });

  /// Korte, beschrijvende tekst voor op het Nu-scherm — null als er niets
  /// vermeldenswaardigs is (nog geen streak, deze week nog niet getraind).
  String? get label {
    if (consecutiveDays >= 2) return '$consecutiveDays dagen op rij getraind';
    if (daysInLastWeek >= 1) {
      return '$daysInLastWeek van de 7 dagen deze week getraind';
    }
    return null;
  }

  factory TrainingStreak.compute(List<DateTime> sessionDates, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final days = sessionDates.map(_dateOnly).toSet();

    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var consecutive = 0;
    while (days.contains(cursor)) {
      consecutive++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final windowStart = today.subtract(const Duration(days: 6));
    final inWeek = days
        .where((d) => !d.isBefore(windowStart) && !d.isAfter(today))
        .length;

    return TrainingStreak(consecutiveDays: consecutive, daysInLastWeek: inWeek);
  }
}
