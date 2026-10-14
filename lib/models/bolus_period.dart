// bolus_period.dart — een tijdvak voor de bolus-calculator (bv. "Ochtend"
// vanaf 00:00), met een eigen koolhydraatratio. Een tijdvak loopt tot de
// starttijd van het eerstvolgende tijdvak (op koolhydraatratio gesorteerd,
// met wrap-around om middernacht) — er zijn dus geen losse eindtijden nodig.

class BolusPeriod {
  final String label;
  final String startTime; // "HH:mm"
  final double carbRatio; // gram koolhydraten per 1 eenheid insuline

  const BolusPeriod({
    required this.label,
    required this.startTime,
    required this.carbRatio,
  });

  factory BolusPeriod.fromJson(Map<String, dynamic> json) => BolusPeriod(
    label: json['label'] as String? ?? '',
    startTime: json['start_time'] as String? ?? '00:00',
    carbRatio: (json['carb_ratio'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'start_time': startTime,
    'carb_ratio': carbRatio,
  };

  BolusPeriod copyWith({String? label, String? startTime, double? carbRatio}) =>
      BolusPeriod(
        label: label ?? this.label,
        startTime: startTime ?? this.startTime,
        carbRatio: carbRatio ?? this.carbRatio,
      );

  /// Minuten sinds middernacht, voor het sorteren/vergelijken van tijdvakken.
  int get startMinutes {
    final parts = startTime.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }
}
