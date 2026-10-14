import 'meal_reminder.dart';
import 'bolus_period.dart';
import 'food_preset.dart';
import 'prep_item.dart';

/// `cgm` bestond vroeger als enige sensor-optie — nu gesplitst in
/// `nightscout` en `dexcomShare`. Oude opgeslagen waarde `'cgm'` wordt in
/// [AppProfile.fromJson] en de migratie gelezen als `nightscout`.
enum GlucoseSource { nightscout, dexcomShare, finger }

/// De trainingsgrens moet nooit onder de dagelijkse grens liggen — anders
/// zou een sessie een lagere ondergrens kunnen hebben dan daarbuiten, wat
/// geen zinnig alarmgedrag oplevert.
bool isValidAlarmLimits({
  required double trainingLimit,
  required double dailyLowBelow,
}) => trainingLimit >= dailyLowBelow;

/// Instelling van de gebruiker voor het hypo-alarm — de enige plek waar dit
/// aan/uit staat. Zie `AppController.alarmDecision()`.
enum AlarmMode {
  sound,
  silent,
  off;

  static AlarmMode fromName(String? name) => switch (name) {
    'silent' => AlarmMode.silent,
    'off' => AlarmMode.off,
    _ => AlarmMode.sound,
  };
}

/// Onder welke glucosebron je de vingerprik-herinnering wilt krijgen —
/// bv. alleen als je zelf prikt, ook als je een sensor gebruikt, of altijd.
enum FingerReminderScope {
  fingerOnly,
  sensorOnly,
  both;

  static FingerReminderScope fromName(String? name) => switch (name) {
    'sensorOnly' => FingerReminderScope.sensorOnly,
    'both' => FingerReminderScope.both,
    _ => FingerReminderScope.fingerOnly,
  };

  bool matches(GlucoseSource source) => switch (this) {
    FingerReminderScope.fingerOnly => source == GlucoseSource.finger,
    FingerReminderScope.sensorOnly => source != GlucoseSource.finger,
    FingerReminderScope.both => true,
  };
}

class AppProfile {
  final String id;
  final GlucoseSource glucoseSource;

  /// Ondergrens tijdens een sambo- of krachtsessie (rule 3 in alarmDecision).
  final double trainingLimit;

  /// Ondergrens buiten een sessie (rule 4 in alarmDecision) — "geldt als je
  /// niet traint".
  final double dailyLowBelow;
  final bool dailyLowEnabled;

  /// Master-instelling: bepaalt of en hoe er ooit een hypo-alarm afgaat.
  /// Zie `AppController.alarmDecision()` — dit is de enige plek die dit
  /// vastlegt; nergens anders in de app staat nog een eigen aan/uit-check.
  final AlarmMode alarmMode;

  /// Of het alarmgeluid over de stille modus/DND heen mag gaan (via het
  /// alarm-volume in plaats van het gewone notificatievolume).
  final bool breakSilentMode;

  final double hyperLimit;
  final bool hyperAlarmEnabled;

  /// Herinnering om handmatig te meten (los van het hypo-alarm) — komt ook
  /// binnen als de app gesloten is, en is geen alarm.
  final bool fingerReminderEnabled;
  final FingerReminderScope fingerReminderScope;
  final int fingerReminderIntervalMinutes;

  final bool onboardingCompleted;
  final String nightscoutUrl;
  final String nightscoutToken;

  /// Alleen gebruikersnaam en server gaan naar Supabase — het wachtwoord
  /// staat los, in `flutter_secure_storage` (zie `DexcomCredentials`), nooit
  /// in het profiel of de database.
  final String dexcomUsername;
  final String dexcomServer;

  /// Weergavenaam (max. 40 tekens) — leeg = afgeleid van het e-mailadres.
  final String username;

  /// Openbare URL van de profielfoto in de storage-bucket `avatars`, of
  /// leeg als er geen foto is.
  final String avatarUrl;

  /// Lichaamsgegevens — optioneel. Gewicht in kg (1 decimaal), lengte in
  /// cm, geslacht 'male' / 'female' / 'other' of leeg.
  final double? weightKg;
  final int? heightCm;
  final String sex;

  /// Eerste dag van de week in kalenders: 0 = zondag, 1 = maandag,
  /// 6 = zaterdag (zoals MaterialLocalizations.firstDayOfWeekIndex).
  final int weekStart;

  /// Systeembalken van de telefoon automatisch verbergen in de hele app
  /// (tijdens een live training gebeurt dat altijd).
  final bool hideSystemBars;

  /// Vaste eetmomenten met een dagelijkse herinnering (apart aan/uit), en
  /// hoeveel minuten vóór het eetmoment die melding komt.
  final bool mealRemindersEnabled;
  final List<MealReminder> mealReminders;
  final int mealReminderOffset;

  /// Knop "Herinner me om …" op de Eten-pagina (apart aan/uit).
  final bool mealOneOffEnabled;

  /// Voedingspresets die je tijdens een training met één tik kunt loggen
  /// (bv. "AA", "Melk", "Ontbijtkoek"). Zelf samengesteld in de instellingen.
  final List<String> carbPresets;

  /// Voorbereidingsacties voor een training ("30 g koolhydraten om 18:30"),
  /// zelf toegevoegd — geen vaste lijst.
  final List<PrepItem> prepItems;

  /// Toont de pauzeknop tijdens een live sessie. Uitzetten haalt hem weg
  /// voor wie er niet per ongeluk op wil tikken.
  final bool showPauseButton;

  /// Presets voor het eetlogboek (bv. "boterham" / "boterhammen" · 15 g) —
  /// +/− in het eetlogboek telt op/af in aantal én koolhydraten.
  final List<FoodPreset> foodPresets;

  /// Of de "tijd om te eten"-melding (na de ingestelde wachttijd na
  /// insuline) geluid mag maken. Uitzetten laat 'm alleen trillen/tonen.
  final bool foodWaitReminderSound;

  /// Bolus-calculator: zet de live voedings-/correctie-insuline-voorstellen
  /// in het eetlogboek aan of uit.
  final bool bolusCalculatorEnabled;

  /// Tijdvakken met elk een eigen koolhydraatratio (bv. "Ochtend" vanaf
  /// 00:00 · 1 E per 10 g) — zelf samengesteld in de instellingen.
  final List<BolusPeriod> bolusPeriods;

  /// Hoeveel mmol/L 1 eenheid correctie-insuline laat zakken.
  final double correctionFactor;

  /// Streefwaarde voor de correctieberekening overdag, resp. 's nachts
  /// (binnen [correctionNightStart]–[correctionNightEnd]) — 's nachts vaak
  /// hoger om nachtelijke hypo's te vermijden.
  final double correctionTargetDay;
  final double correctionTargetNight;
  final String correctionNightStart; // "HH:mm"
  final String correctionNightEnd; // "HH:mm"

  const AppProfile({
    required this.id,
    required this.glucoseSource,
    required this.trainingLimit,
    required this.onboardingCompleted,
    this.dailyLowBelow = 3.9,
    this.dailyLowEnabled = true,
    this.alarmMode = AlarmMode.sound,
    this.breakSilentMode = true,
    this.hyperLimit = 10.0,
    this.hyperAlarmEnabled = true,
    this.fingerReminderEnabled = false,
    this.fingerReminderScope = FingerReminderScope.fingerOnly,
    this.fingerReminderIntervalMinutes = 120,
    this.nightscoutUrl = '',
    this.nightscoutToken = '',
    this.dexcomUsername = '',
    this.dexcomServer = 'shareous1.dexcom.com',
    this.username = '',
    this.avatarUrl = '',
    this.weightKg,
    this.heightCm,
    this.sex = '',
    this.weekStart = 1,
    this.hideSystemBars = false,
    this.mealRemindersEnabled = false,
    this.mealReminders = const [],
    this.mealReminderOffset = 0,
    this.mealOneOffEnabled = true,
    this.carbPresets = const [],
    this.prepItems = const [],
    this.showPauseButton = true,
    this.foodPresets = const [],
    this.foodWaitReminderSound = true,
    this.bolusCalculatorEnabled = false,
    this.bolusPeriods = const [],
    this.correctionFactor = 2.0,
    this.correctionTargetDay = 8.0,
    this.correctionTargetNight = 10.0,
    this.correctionNightStart = '19:00',
    this.correctionNightEnd = '05:00',
  });

  factory AppProfile.defaults(String id) => AppProfile(
    id: id,
    glucoseSource: GlucoseSource.nightscout,
    trainingLimit: 5.0,
    hyperLimit: 10.0,
    hyperAlarmEnabled: true,
    onboardingCompleted: false,
    carbPresets: const ['AA', 'Melk', 'Ontbijtkoek'],
    foodPresets: const [
      FoodPreset(singular: 'boterham', plural: 'boterhammen', carbs: 15),
      FoodPreset(singular: 'appel', plural: 'appels', carbs: 20),
    ],
  );

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      id: json['id'] as String,
      glucoseSource: switch (json['glucose_source'] as String?) {
        'finger' => GlucoseSource.finger,
        'dexcomShare' => GlucoseSource.dexcomShare,
        _ => GlucoseSource.nightscout, // ook de oude waarde 'cgm' valt hierop terug
      },
      trainingLimit: ((json['training_limit'] as num?) ?? 5.0).toDouble(),
      dailyLowBelow: ((json['daily_low_below'] as num?) ?? 3.9).toDouble(),
      dailyLowEnabled: (json['daily_low_enabled'] as bool?) ?? true,
      alarmMode: AlarmMode.fromName(json['alarm_mode'] as String?),
      breakSilentMode: (json['break_silent_mode'] as bool?) ?? true,
      hyperLimit: ((json['hyper_limit'] as num?) ?? 10.0).toDouble(),
      hyperAlarmEnabled: (json['hyper_alarm_enabled'] as bool?) ?? true,
      fingerReminderEnabled:
          (json['finger_reminder_enabled'] as bool?) ?? false,
      fingerReminderScope: FingerReminderScope.fromName(
        json['finger_reminder_scope'] as String?,
      ),
      fingerReminderIntervalMinutes:
          (json['finger_reminder_interval_minutes'] as num?)?.toInt() ?? 120,
      onboardingCompleted: (json['onboarding_completed'] as bool?) ?? false,
      nightscoutUrl: (json['nightscout_url'] as String?) ?? '',
      nightscoutToken: (json['nightscout_token'] as String?) ?? '',
      dexcomUsername: (json['dexcom_username'] as String?) ?? '',
      dexcomServer:
          (json['dexcom_server'] as String?) ?? 'shareous1.dexcom.com',
      username: (json['username'] as String?) ?? '',
      avatarUrl: (json['avatar_url'] as String?) ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      heightCm: (json['height_cm'] as num?)?.toInt(),
      sex: (json['sex'] as String?) ?? '',
      weekStart: (json['week_start'] as num?)?.toInt() ?? 1,
      hideSystemBars: (json['hide_system_bars'] as bool?) ?? false,
      mealRemindersEnabled: (json['meal_reminders_enabled'] as bool?) ?? false,
      mealReminders: ((json['meal_reminders'] as List?) ?? [])
          .map(MealReminder.fromJson)
          .toList(),
      mealReminderOffset: (json['meal_reminder_offset'] as num?)?.toInt() ?? 0,
      mealOneOffEnabled: (json['meal_one_off_enabled'] as bool?) ?? true,
      carbPresets: ((json['carb_presets'] as List?) ?? [])
          .map((e) => e as String)
          .toList(),
      prepItems: ((json['prep_items'] as List?) ?? [])
          .map((e) => PrepItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      showPauseButton: (json['show_pause_button'] as bool?) ?? true,
      foodPresets: ((json['food_checklist'] as List?) ?? [])
          .map(FoodPreset.fromJson)
          .toList(),
      foodWaitReminderSound:
          (json['food_wait_reminder_sound'] as bool?) ?? true,
      bolusCalculatorEnabled:
          (json['bolus_calculator_enabled'] as bool?) ?? false,
      bolusPeriods: ((json['bolus_periods'] as List?) ?? [])
          .map((e) => BolusPeriod.fromJson(e as Map<String, dynamic>))
          .toList(),
      correctionFactor:
          ((json['correction_factor'] as num?) ?? 2.0).toDouble(),
      correctionTargetDay:
          ((json['correction_target_day'] as num?) ?? 8.0).toDouble(),
      correctionTargetNight:
          ((json['correction_target_night'] as num?) ?? 10.0).toDouble(),
      correctionNightStart:
          (json['correction_night_start'] as String?) ?? '19:00',
      correctionNightEnd:
          (json['correction_night_end'] as String?) ?? '05:00',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'glucose_source': glucoseSource.name,
    'training_limit': trainingLimit,
    'daily_low_below': dailyLowBelow,
    'daily_low_enabled': dailyLowEnabled,
    'alarm_mode': alarmMode.name,
    'break_silent_mode': breakSilentMode,
    'hyper_limit': hyperLimit,
    'hyper_alarm_enabled': hyperAlarmEnabled,
    'finger_reminder_enabled': fingerReminderEnabled,
    'finger_reminder_scope': fingerReminderScope.name,
    'finger_reminder_interval_minutes': fingerReminderIntervalMinutes,
    'onboarding_completed': onboardingCompleted,
    'nightscout_url': nightscoutUrl.trim(),
    'nightscout_token': nightscoutToken.trim(),
    'dexcom_username': dexcomUsername.trim(),
    'dexcom_server': dexcomServer.trim(),
    'username': username.trim(),
    'avatar_url': avatarUrl,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'sex': sex,
    'week_start': weekStart,
    'hide_system_bars': hideSystemBars,
    'meal_reminders_enabled': mealRemindersEnabled,
    'meal_reminders': mealReminders.map((m) => m.toJson()).toList(),
    'meal_reminder_offset': mealReminderOffset,
    'meal_one_off_enabled': mealOneOffEnabled,
    'carb_presets': carbPresets,
    'prep_items': prepItems.map((p) => p.toJson()).toList(),
    'show_pause_button': showPauseButton,
    'food_checklist': foodPresets.map((p) => p.toJson()).toList(),
    'food_wait_reminder_sound': foodWaitReminderSound,
    'bolus_calculator_enabled': bolusCalculatorEnabled,
    'bolus_periods': bolusPeriods.map((p) => p.toJson()).toList(),
    'correction_factor': correctionFactor,
    'correction_target_day': correctionTargetDay,
    'correction_target_night': correctionTargetNight,
    'correction_night_start': correctionNightStart,
    'correction_night_end': correctionNightEnd,
  };

  AppProfile copyWith({
    GlucoseSource? glucoseSource,
    double? trainingLimit,
    double? dailyLowBelow,
    bool? dailyLowEnabled,
    AlarmMode? alarmMode,
    bool? breakSilentMode,
    double? hyperLimit,
    bool? hyperAlarmEnabled,
    bool? fingerReminderEnabled,
    FingerReminderScope? fingerReminderScope,
    int? fingerReminderIntervalMinutes,
    bool? onboardingCompleted,
    String? nightscoutUrl,
    String? nightscoutToken,
    String? dexcomUsername,
    String? dexcomServer,
    String? username,
    String? avatarUrl,
    double? weightKg,
    int? heightCm,
    String? sex,
    int? weekStart,
    bool? hideSystemBars,
    bool? mealRemindersEnabled,
    List<MealReminder>? mealReminders,
    int? mealReminderOffset,
    bool? mealOneOffEnabled,
    bool clearWeight = false,
    bool clearHeight = false,
    List<String>? carbPresets,
    List<PrepItem>? prepItems,
    bool? showPauseButton,
    List<FoodPreset>? foodPresets,
    bool? foodWaitReminderSound,
    bool? bolusCalculatorEnabled,
    List<BolusPeriod>? bolusPeriods,
    double? correctionFactor,
    double? correctionTargetDay,
    double? correctionTargetNight,
    String? correctionNightStart,
    String? correctionNightEnd,
  }) {
    return AppProfile(
      id: id,
      glucoseSource: glucoseSource ?? this.glucoseSource,
      trainingLimit: trainingLimit ?? this.trainingLimit,
      dailyLowBelow: dailyLowBelow ?? this.dailyLowBelow,
      dailyLowEnabled: dailyLowEnabled ?? this.dailyLowEnabled,
      alarmMode: alarmMode ?? this.alarmMode,
      breakSilentMode: breakSilentMode ?? this.breakSilentMode,
      hyperLimit: hyperLimit ?? this.hyperLimit,
      hyperAlarmEnabled: hyperAlarmEnabled ?? this.hyperAlarmEnabled,
      fingerReminderEnabled:
          fingerReminderEnabled ?? this.fingerReminderEnabled,
      fingerReminderScope: fingerReminderScope ?? this.fingerReminderScope,
      fingerReminderIntervalMinutes:
          fingerReminderIntervalMinutes ?? this.fingerReminderIntervalMinutes,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      nightscoutUrl: nightscoutUrl ?? this.nightscoutUrl,
      nightscoutToken: nightscoutToken ?? this.nightscoutToken,
      dexcomUsername: dexcomUsername ?? this.dexcomUsername,
      dexcomServer: dexcomServer ?? this.dexcomServer,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      sex: sex ?? this.sex,
      weekStart: weekStart ?? this.weekStart,
      hideSystemBars: hideSystemBars ?? this.hideSystemBars,
      mealRemindersEnabled: mealRemindersEnabled ?? this.mealRemindersEnabled,
      mealReminders: mealReminders ?? this.mealReminders,
      mealReminderOffset: mealReminderOffset ?? this.mealReminderOffset,
      mealOneOffEnabled: mealOneOffEnabled ?? this.mealOneOffEnabled,
      carbPresets: carbPresets ?? this.carbPresets,
      prepItems: prepItems ?? this.prepItems,
      showPauseButton: showPauseButton ?? this.showPauseButton,
      foodPresets: foodPresets ?? this.foodPresets,
      foodWaitReminderSound:
          foodWaitReminderSound ?? this.foodWaitReminderSound,
      bolusCalculatorEnabled:
          bolusCalculatorEnabled ?? this.bolusCalculatorEnabled,
      bolusPeriods: bolusPeriods ?? this.bolusPeriods,
      correctionFactor: correctionFactor ?? this.correctionFactor,
      correctionTargetDay: correctionTargetDay ?? this.correctionTargetDay,
      correctionTargetNight:
          correctionTargetNight ?? this.correctionTargetNight,
      correctionNightStart:
          correctionNightStart ?? this.correctionNightStart,
      correctionNightEnd: correctionNightEnd ?? this.correctionNightEnd,
    );
  }
}
