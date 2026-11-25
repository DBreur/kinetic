// kinetic_profile.dart: de profielvelden die Kinetic 2.0 gebruikt. De tabel
// `profiles` heeft veel meer kolommen (alarmen, presets, dashboard...); die
// worden nooit overschreven: we lezen alleen wat hier staat en schrijven via
// gerichte updates van losse kolommen (zie ProfileRepository).

import 'bolus_period.dart';
import 'food_preset.dart';

enum GlucoseSource {
  dexcomShare('dexcomShare', 'Dexcom Share'),
  nightscout('nightscout', 'Nightscout'),
  finger('finger', 'Vingerprik');

  const GlucoseSource(this.dbName, this.label);
  final String dbName;
  final String label;

  static GlucoseSource fromName(String? name) => switch (name) {
    'finger' => GlucoseSource.finger,
    'dexcomShare' => GlucoseSource.dexcomShare,
    // ook de oude waarde 'cgm' betekent Nightscout
    _ => GlucoseSource.nightscout,
  };
}

class KineticProfile {
  final String id;
  final String username;
  final GlucoseSource glucoseSource;
  final String dexcomUsername;
  final String dexcomServer;
  final String nightscoutUrl;

  /// Staat alleen in versleutelde opslag op het toestel, niet in de database.
  final String nightscoutToken;

  final double? weightKg;

  /// Eigen ondergrens om te (blijven) trainen.
  final double trainingLimit;
  final double dailyLowBelow;
  final double hyperLimit;

  /// mmol/L daling per eenheid insuline.
  final double correctionFactor;

  /// Bolus-calculator: tijdvakken met elk een KH-ratio (g per E), en de
  /// streefwaarde voor correcties overdag en 's nachts.
  final bool bolusCalculatorEnabled;
  final List<BolusPeriod> bolusPeriods;
  final double correctionTargetDay;
  final double correctionTargetNight;

  /// Nachtvenster "HH:mm" (mag over middernacht lopen, bv. 19:00-05:00).
  final String correctionNightStart;
  final String correctionNightEnd;

  /// Eigen voedingspresets (kolom `food_checklist`).
  final List<FoodPreset> foodPresets;

  /// Presets voor voeding tijdens een training (kolom `carb_presets`), los
  /// van de maaltijdpresets (bv. "Dextro", "Sportdrank").
  final List<FoodPreset> trainingPresets;

  /// Eigen titels voor video's (videolink → titel, kolom `video_labels`).
  final Map<String, String> videoLabels;

  const KineticProfile({
    required this.id,
    this.username = '',
    this.glucoseSource = GlucoseSource.dexcomShare,
    this.dexcomUsername = '',
    this.dexcomServer = 'shareous1.dexcom.com',
    this.nightscoutUrl = '',
    this.nightscoutToken = '',
    this.weightKg,
    this.trainingLimit = 5.0,
    this.dailyLowBelow = 3.9,
    this.hyperLimit = 10.0,
    this.correctionFactor = 2.0,
    this.bolusCalculatorEnabled = false,
    this.bolusPeriods = const [],
    this.correctionTargetDay = 8.0,
    this.correctionTargetNight = 10.0,
    this.correctionNightStart = '19:00',
    this.correctionNightEnd = '05:00',
    this.foodPresets = const [],
    this.trainingPresets = const [],
    this.videoLabels = const {},
  });

  factory KineticProfile.fromJson(Map<String, dynamic> j) => KineticProfile(
    id: j['id'] as String,
    username: (j['username'] as String?) ?? '',
    glucoseSource: GlucoseSource.fromName(j['glucose_source'] as String?),
    dexcomUsername: (j['dexcom_username'] as String?) ?? '',
    dexcomServer: (j['dexcom_server'] as String?) ?? 'shareous1.dexcom.com',
    nightscoutUrl: (j['nightscout_url'] as String?) ?? '',
    nightscoutToken: (j['nightscout_token'] as String?) ?? '',
    weightKg: (j['weight_kg'] as num?)?.toDouble(),
    trainingLimit: ((j['training_limit'] as num?) ?? 5.0).toDouble(),
    dailyLowBelow: ((j['daily_low_below'] as num?) ?? 3.9).toDouble(),
    hyperLimit: ((j['hyper_limit'] as num?) ?? 10.0).toDouble(),
    correctionFactor: ((j['correction_factor'] as num?) ?? 2.0).toDouble(),
    bolusCalculatorEnabled: (j['bolus_calculator_enabled'] as bool?) ?? false,
    bolusPeriods: [
      for (final x in (j['bolus_periods'] as List?) ?? const [])
        if (x is Map) BolusPeriod.fromJson(Map<String, dynamic>.from(x)),
    ],
    correctionTargetDay: ((j['correction_target_day'] as num?) ?? 8.0).toDouble(),
    correctionTargetNight: ((j['correction_target_night'] as num?) ?? 10.0).toDouble(),
    correctionNightStart: (j['correction_night_start'] as String?) ?? '19:00',
    correctionNightEnd: (j['correction_night_end'] as String?) ?? '05:00',
    foodPresets: ((j['food_checklist'] as List?) ?? const []).map(FoodPreset.fromJson).toList(),
    trainingPresets: ((j['carb_presets'] as List?) ?? const []).map(FoodPreset.fromJson).toList(),
    videoLabels: {
      for (final e in ((j['video_labels'] as Map?) ?? const {}).entries)
        if (e.value is String) e.key as String: e.value as String,
    },
  );

  KineticProfile copyWith({
    GlucoseSource? glucoseSource,
    String? dexcomUsername,
    String? dexcomServer,
    String? nightscoutUrl,
    String? nightscoutToken,
    double? weightKg,
    double? dailyLowBelow,
    double? hyperLimit,
    double? correctionFactor,
    bool? bolusCalculatorEnabled,
    List<BolusPeriod>? bolusPeriods,
    double? correctionTargetDay,
    double? correctionTargetNight,
    String? correctionNightStart,
    String? correctionNightEnd,
    List<FoodPreset>? foodPresets,
    List<FoodPreset>? trainingPresets,
    Map<String, String>? videoLabels,
  }) => KineticProfile(
    id: id,
    username: username,
    glucoseSource: glucoseSource ?? this.glucoseSource,
    dexcomUsername: dexcomUsername ?? this.dexcomUsername,
    dexcomServer: dexcomServer ?? this.dexcomServer,
    nightscoutUrl: nightscoutUrl ?? this.nightscoutUrl,
    nightscoutToken: nightscoutToken ?? this.nightscoutToken,
    weightKg: weightKg ?? this.weightKg,
    trainingLimit: trainingLimit,
    dailyLowBelow: dailyLowBelow ?? this.dailyLowBelow,
    hyperLimit: hyperLimit ?? this.hyperLimit,
    correctionFactor: correctionFactor ?? this.correctionFactor,
    bolusCalculatorEnabled: bolusCalculatorEnabled ?? this.bolusCalculatorEnabled,
    bolusPeriods: bolusPeriods ?? this.bolusPeriods,
    correctionTargetDay: correctionTargetDay ?? this.correctionTargetDay,
    correctionTargetNight: correctionTargetNight ?? this.correctionTargetNight,
    correctionNightStart: correctionNightStart ?? this.correctionNightStart,
    correctionNightEnd: correctionNightEnd ?? this.correctionNightEnd,
    foodPresets: foodPresets ?? this.foodPresets,
    trainingPresets: trainingPresets ?? this.trainingPresets,
    videoLabels: videoLabels ?? this.videoLabels,
  );
}
