// meal_reminder.dart — een vast eetmoment ("Ontbijt", 07:30) waarvoor je
// elke dag een herinnering krijgt.

class MealReminder {
  final String label;

  /// "HH:mm"
  final String time;

  const MealReminder({required this.label, required this.time});

  factory MealReminder.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MealReminder(
      label: (map['label'] as String?) ?? 'Eten',
      time: (map['time'] as String?) ?? '12:00',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'time': time};

  int get minutesOfDay {
    final parts = time.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }
}

/// Standaard eetmomenten als je ze voor het eerst aanzet.
const kDefaultMealReminders = [
  MealReminder(label: 'Ontbijt', time: '07:30'),
  MealReminder(label: 'Lunch', time: '12:30'),
  MealReminder(label: 'Avondeten', time: '18:00'),
];
