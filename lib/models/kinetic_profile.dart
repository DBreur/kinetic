// kinetic_profile.dart: de profielvelden die Kinetic 2.0 gebruikt. De tabel
// `profiles` heeft veel meer kolommen (alarmen, presets, dashboard...); die
// worden nooit overschreven: we lezen alleen wat hier staat en schrijven via
// gerichte updates van losse kolommen (zie ProfileRepository).

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
  );

  KineticProfile copyWith({
    GlucoseSource? glucoseSource,
    String? dexcomUsername,
    String? dexcomServer,
    String? nightscoutUrl,
    String? nightscoutToken,
    double? weightKg,
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
    dailyLowBelow: dailyLowBelow,
    hyperLimit: hyperLimit,
    correctionFactor: correctionFactor,
  );
}
