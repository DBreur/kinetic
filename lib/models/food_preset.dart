// food_preset.dart — een voedingspreset voor het eetlogboek: enkelvoud en
// meervoud (voor "1 boterham" vs "2 boterhammen") plus koolhydraten per
// stuk, zodat +/− meteen zowel de omschrijving als de koolhydraten bijwerkt.
// Optioneel ook een hoeveelheid per stuk (bv. 250 ml melk, 150 g yoghurt),
// die meeschaalt met het aantal.

/// Presets alfabetisch op naam, ongeacht hoofd-/kleine letters — zodat een
/// groeiende lijst overzichtelijk blijft in plaats van op toevoegvolgorde.
List<FoodPreset> sortedPresets(List<FoodPreset> presets) {
  final sorted = [...presets];
  sorted.sort(
    (a, b) => a.singular.toLowerCase().compareTo(b.singular.toLowerCase()),
  );
  return sorted;
}

class FoodPreset {
  final String singular;
  final String plural;
  final double carbs;
  final double unitAmount; // bv. 250 — 0 betekent: geen hoeveelheid tonen
  final String unitLabel; // bv. "ml", "g"

  const FoodPreset({
    required this.singular,
    required this.plural,
    this.carbs = 0,
    this.unitAmount = 0,
    this.unitLabel = '',
  });

  /// Accepteert ook een kale string, voor items van vóór dit preset-model
  /// (toen de checklist nog losse vinkjes zonder koolhydraten was).
  factory FoodPreset.fromJson(dynamic json) {
    if (json is String) {
      return FoodPreset(singular: json, plural: json, carbs: 0);
    }
    final map = json as Map<String, dynamic>;
    final singular = map['singular'] as String;
    return FoodPreset(
      singular: singular,
      plural: (map['plural'] as String?) ?? singular,
      carbs: (map['carbs'] as num?)?.toDouble() ?? 0,
      unitAmount: (map['unit_amount'] as num?)?.toDouble() ?? 0,
      unitLabel: (map['unit_label'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'singular': singular,
    'plural': plural,
    'carbs': carbs,
    'unit_amount': unitAmount,
    'unit_label': unitLabel,
  };

  FoodPreset copyWith({
    String? singular,
    String? plural,
    double? carbs,
    double? unitAmount,
    String? unitLabel,
  }) => FoodPreset(
    singular: singular ?? this.singular,
    plural: plural ?? this.plural,
    carbs: carbs ?? this.carbs,
    unitAmount: unitAmount ?? this.unitAmount,
    unitLabel: unitLabel ?? this.unitLabel,
  );

  bool get hasUnit => unitAmount > 0 && unitLabel.isNotEmpty;

  /// "1 boterham" of "3 boterhammen".
  String label(int count) => count == 1 ? '1 $singular' : '$count $plural';

  /// Totale hoeveelheid voor [count] stuks, bv. "500 ml" bij 2 glazen van
  /// 250 ml. Leeg als er geen hoeveelheid is ingesteld.
  String amountLabel(int count) {
    if (!hasUnit || count <= 0) return '';
    final total = unitAmount * count;
    final text = total % 1 == 0
        ? total.toInt().toString()
        : total.toStringAsFixed(1).replaceAll('.', ',');
    return '$text $unitLabel';
  }
}
