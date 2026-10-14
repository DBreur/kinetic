enum Trend { up, slightUp, flat, slightDown, down, fastDown }

/// Sensors melden in mg/dL; de hele app rekent in mmol/L.
double mgdlToMmol(num mgdl) => mgdl.toDouble() / 18.0;

/// Richting afgeleid uit twee vingerprikwaardes — er is geen sensor die dit
/// vertelt, dus schatten we het uit het verschil met de vorige meting.
Trend trendFromDelta(double delta) {
  if (delta <= -0.6) return Trend.fastDown;
  if (delta <= -0.2) return Trend.down;
  if (delta <= -0.1) return Trend.slightDown;
  if (delta >= 0.3) return Trend.up;
  if (delta >= 0.1) return Trend.slightUp;
  return Trend.flat;
}

class GlucoseReading {
  final double mmol;
  final Trend trend;
  final DateTime at;

  const GlucoseReading(this.mmol, this.trend, this.at);

  /// Waar zodra deze meting 15 minuten of langer geleden is — een sensor
  /// hoort elke 5 minuten te meten, dus dit betekent dat de data niet meer
  /// actueel is (verbinding kwijt, sensor los, telefoon buiten bereik).
  bool get isStale => DateTime.now().difference(at).inMinutes >= 15;
}

/// Eén meting in een korte geschiedenis (bv. de curve op het Nu-scherm) —
/// met tijdstip, zodat een grafiek een gat kan tonen waar metingen ontbreken
/// in plaats van de resterende punten tegen elkaar aan te schuiven.
class GlucosePoint {
  final DateTime at;
  final double mmol;
  const GlucosePoint(this.at, this.mmol);

  factory GlucosePoint.fromJson(Map<String, dynamic> json) => GlucosePoint(
    DateTime.parse(json['at'] as String),
    (json['mmol'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'mmol': mmol,
  };
}

class GlucoseSnapshot {
  final GlucoseReading? reading;
  final List<GlucosePoint> history;
  final bool isLoading;
  final String? message;

  const GlucoseSnapshot({
    required this.reading,
    required this.history,
    this.isLoading = false,
    this.message,
  });

  const GlucoseSnapshot.loading()
    : reading = null,
      history = const [],
      isLoading = true,
      message = null;

  const GlucoseSnapshot.unconfigured()
    : reading = null,
      history = const [],
      isLoading = false,
      message = 'Stel je glucosebron in bij Instellingen.';

  /// Alleen zinvol bij CGM — bij vingerprik is een oude meting normaal
  /// (je meet niet elke 15 minuten), dus daar tonen we dit niet als "oud".
  bool get isStale => reading?.isStale ?? false;

  GlucoseSnapshot copyWith({
    GlucoseReading? reading,
    List<GlucosePoint>? history,
    bool? isLoading,
    String? message,
  }) {
    return GlucoseSnapshot(
      reading: reading ?? this.reading,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      message: message,
    );
  }
}
