// food_log_entry.dart — een regel in het eetlogboek: wat je hebt gegeten,
// wanneer, welke presets met welk aantal je hebt gebruikt (om de +/-
// tellers bij bewerken weer goed te tonen), hoeveel koolhydraten, hoeveel
// insuline en of dat voor of na het eten was, en optioneel je glucosewaarde
// op dat moment.

enum InsulinTiming {
  before,
  after;

  static InsulinTiming? fromName(String? name) => switch (name) {
    'before' => InsulinTiming.before,
    'after' => InsulinTiming.after,
    _ => null,
  };

  String get label =>
      this == InsulinTiming.before ? 'Voor het eten' : 'Na het eten';
}

class FoodLogEntry {
  final String id;
  final DateTime at;
  final String description;

  /// Preset-enkelvoud → aantal, zoals gekozen met +/− in het toevoegformulier.
  /// Puur om die tellers te herstellen bij het bewerken; de omschrijving en
  /// koolhydraten hieronder zijn de bron van waarheid voor wat je ziet.
  final Map<String, int> presetCounts;

  final double? carbs;
  final double? mmol;

  final double? insulinUnits;
  final InsulinTiming? insulinTiming;

  /// Opsplitsing van [insulinUnits] door de bolus-calculator — alleen gezet
  /// als die aan stond toen je dit regel logde. [insulinUnits] blijft het
  /// gezaghebbende totaal, ook voor regels van vóór deze functie.
  final double? insulinFoodUnits;
  final double? insulinCorrectionUnits;

  /// Waarom het voor of na het eten was (bv. "bloedsuiker was al hoog").
  final String insulinNote;

  /// Hoeveel minuten je liet inwerken vóór het eten (optioneel, alleen
  /// zinvol als [insulinTiming] "voor het eten" is) — in stappen van 2,5
  /// minuut. Bij het opslaan plant de app hiervoor een eenmalige melding in.
  final double? insulinWaitMinutes;

  const FoodLogEntry({
    required this.id,
    required this.at,
    required this.description,
    this.presetCounts = const {},
    this.carbs,
    this.mmol,
    this.insulinUnits,
    this.insulinTiming,
    this.insulinFoodUnits,
    this.insulinCorrectionUnits,
    this.insulinNote = '',
    this.insulinWaitMinutes,
  });

  factory FoodLogEntry.fromJson(Map<String, dynamic> json) => FoodLogEntry(
    id: json['id'] as String,
    at: DateTime.parse(json['at'] as String).toLocal(),
    description: (json['description'] as String?) ?? '',
    presetCounts: ((json['preset_counts'] as Map?) ?? {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    carbs: (json['carbs'] as num?)?.toDouble(),
    mmol: (json['mmol'] as num?)?.toDouble(),
    insulinUnits: (json['insulin_units'] as num?)?.toDouble(),
    insulinTiming: InsulinTiming.fromName(json['insulin_timing'] as String?),
    insulinFoodUnits: (json['insulin_food_units'] as num?)?.toDouble(),
    insulinCorrectionUnits:
        (json['insulin_correction_units'] as num?)?.toDouble(),
    insulinNote: (json['insulin_note'] as String?) ?? '',
    insulinWaitMinutes: (json['insulin_wait_minutes'] as num?)?.toDouble(),
  );

  FoodLogEntry copyWith({
    DateTime? at,
    String? description,
    Map<String, int>? presetCounts,
    double? carbs,
    bool clearCarbs = false,
    double? mmol,
    bool clearMmol = false,
    double? insulinUnits,
    bool clearInsulinUnits = false,
    InsulinTiming? insulinTiming,
    bool clearInsulinTiming = false,
    double? insulinFoodUnits,
    bool clearInsulinFoodUnits = false,
    double? insulinCorrectionUnits,
    bool clearInsulinCorrectionUnits = false,
    String? insulinNote,
    double? insulinWaitMinutes,
    bool clearInsulinWaitMinutes = false,
  }) => FoodLogEntry(
    id: id,
    at: at ?? this.at,
    description: description ?? this.description,
    presetCounts: presetCounts ?? this.presetCounts,
    carbs: clearCarbs ? null : (carbs ?? this.carbs),
    mmol: clearMmol ? null : (mmol ?? this.mmol),
    insulinUnits: clearInsulinUnits
        ? null
        : (insulinUnits ?? this.insulinUnits),
    insulinTiming: clearInsulinTiming
        ? null
        : (insulinTiming ?? this.insulinTiming),
    insulinFoodUnits: clearInsulinFoodUnits
        ? null
        : (insulinFoodUnits ?? this.insulinFoodUnits),
    insulinCorrectionUnits: clearInsulinCorrectionUnits
        ? null
        : (insulinCorrectionUnits ?? this.insulinCorrectionUnits),
    insulinNote: insulinNote ?? this.insulinNote,
    insulinWaitMinutes: clearInsulinWaitMinutes
        ? null
        : (insulinWaitMinutes ?? this.insulinWaitMinutes),
  );
}
