import 'dart:async';

import 'package:flutter/material.dart';

import '../core/rest_blocks.dart';
import '../core/formatters.dart';
import '../models/agenda.dart' show normalizeReminders, reminderLabel;
import '../models/dashboard_config.dart';
import '../models/app_profile.dart';
import '../models/bolus_period.dart';
import '../models/food_preset.dart';
import '../models/meal_reminder.dart';
import '../services/alarm_notification_service.dart';
import '../services/dexcom_credentials.dart';
import '../services/dexcom_share_service.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/dashboard_editor.dart';
import '../widgets/kinetic.dart';
import 'food_presets_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late GlucoseSource _source;
  late double _trainingLimit;
  late double _dailyLowBelow;
  late bool _dailyLowEnabled;
  late AlarmMode _alarmMode;
  late bool _breakSilentMode;
  late double _hyperLimit;
  late bool _hyperAlarmEnabled;
  late bool _fingerReminderEnabled;
  late FingerReminderScope _fingerReminderScope;
  late int _fingerReminderIntervalMinutes;
  late bool _showPauseButton;
  late int _alarmSnoozeMinutes;
  late int _defaultRestSeconds;
  late SpotifyButtonPlacement _spotifyButton;
  AlarmMode? _trainingAlarmMode;
  late int _circuitPrepSeconds;
  late final TextEditingController _nightscoutUrl;
  late final TextEditingController _nightscoutToken;
  late final TextEditingController _dexcomUsername;
  late final TextEditingController _dexcomPassword;
  late String _dexcomServer;
  bool _testingDexcom = false;
  String? _dexcomTestResult;
  late List<String> _carbPresets;
  final _newPreset = TextEditingController();
  late List<FoodPreset> _foodPresets;
  late int _weekStart;
  late bool _hideSystemBars;
  late DashboardConfig _dashboard;
  late bool _techRemindersEnabled;
  late Set<int> _techReminderDefaults;
  late bool _techReminderSound;
  late bool _foodWaitReminderSound;
  late bool _mealRemindersEnabled;
  late List<MealReminder> _mealReminders;
  late int _mealReminderOffset;
  late bool _mealOneOffEnabled;
  late bool _bolusCalculatorEnabled;
  late List<BolusPeriod> _bolusPeriods;
  late double _correctionFactor;
  late double _correctionTargetDay;
  late double _correctionTargetNight;
  late TimeOfDay _correctionNightStart;
  late TimeOfDay _correctionNightEnd;
  Timer? _testAlarmTimer;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile!;
    _source = profile.glucoseSource;
    _trainingLimit = profile.trainingLimit;
    _dailyLowBelow = profile.dailyLowBelow;
    _dailyLowEnabled = profile.dailyLowEnabled;
    _alarmMode = profile.alarmMode;
    _breakSilentMode = profile.breakSilentMode;
    _hyperLimit = profile.hyperLimit;
    _hyperAlarmEnabled = profile.hyperAlarmEnabled;
    _fingerReminderEnabled = profile.fingerReminderEnabled;
    _fingerReminderScope = profile.fingerReminderScope;
    _fingerReminderIntervalMinutes = profile.fingerReminderIntervalMinutes;
    _showPauseButton = profile.showPauseButton;
    _alarmSnoozeMinutes = profile.alarmSnoozeMinutes;
    _defaultRestSeconds = profile.defaultRestSeconds;
    _spotifyButton = profile.spotifyButton;
    _trainingAlarmMode = profile.trainingAlarmMode;
    _circuitPrepSeconds = profile.circuitPrepSeconds;
    _nightscoutUrl = TextEditingController(text: profile.nightscoutUrl);
    _nightscoutToken = TextEditingController(text: profile.nightscoutToken);
    _dexcomUsername = TextEditingController(text: profile.dexcomUsername);
    _dexcomPassword = TextEditingController();
    _dexcomServer = profile.dexcomServer;
    DexcomCredentials.read().then((password) {
      if (mounted && password != null) {
        setState(() => _dexcomPassword.text = password);
      }
    });
    _carbPresets = List.of(profile.carbPresets);
    _foodPresets = List.of(profile.foodPresets);
    _weekStart = profile.weekStart;
    _hideSystemBars = profile.hideSystemBars;
    _dashboard = profile.dashboard;
    _techRemindersEnabled = profile.techniqueRemindersEnabled;
    _techReminderDefaults = {...profile.techniqueReminderDefaults};
    _techReminderSound = profile.techniqueReminderSound;
    _foodWaitReminderSound = profile.foodWaitReminderSound;
    _mealRemindersEnabled = profile.mealRemindersEnabled;
    _mealReminders = List.of(profile.mealReminders);
    _mealReminderOffset = profile.mealReminderOffset;
    _mealOneOffEnabled = profile.mealOneOffEnabled;
    _bolusCalculatorEnabled = profile.bolusCalculatorEnabled;
    _bolusPeriods = List.of(profile.bolusPeriods);
    _correctionFactor = profile.correctionFactor;
    _correctionTargetDay = profile.correctionTargetDay;
    _correctionTargetNight = profile.correctionTargetNight;
    _correctionNightStart = _parseTimeOfDay(profile.correctionNightStart);
    _correctionNightEnd = _parseTimeOfDay(profile.correctionNightEnd);
  }

  @override
  void dispose() {
    _nightscoutUrl.dispose();
    _nightscoutToken.dispose();
    _dexcomUsername.dispose();
    _dexcomPassword.dispose();
    _newPreset.dispose();
    _testAlarmTimer?.cancel();
    super.dispose();
  }

  bool get _alarmsAvailable => _source != GlucoseSource.finger;

  Future<void> _testDexcomConnection() async {
    final username = _dexcomUsername.text.trim();
    final password = _dexcomPassword.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _dexcomTestResult = 'Vul gebruikersnaam en wachtwoord in.',
      );
      return;
    }
    setState(() {
      _testingDexcom = true;
      _dexcomTestResult = null;
    });
    final snapshot = await DexcomShareService(
      username: username,
      password: password,
      server: _dexcomServer,
    ).fetch(count: 1);
    if (!mounted) return;
    setState(() {
      _testingDexcom = false;
      _dexcomTestResult = snapshot.reading != null
          ? 'Dexcom G7 · verbonden · laatste meting ${relativeDutch(snapshot.reading!.at)}'
          : (snapshot.message ?? 'Verbinding mislukt.');
    });
  }

  TimeOfDay _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String _alarmModeLabel(AlarmMode mode) => switch (mode) {
    AlarmMode.sound => 'Aan met geluid',
    AlarmMode.silent => 'Aan zonder geluid',
    AlarmMode.off => 'Uit',
  };

  String _fingerReminderScopeLabel(FingerReminderScope scope) =>
      switch (scope) {
        FingerReminderScope.fingerOnly => 'Alleen vingerprik',
        FingerReminderScope.sensorOnly => 'Alleen sensor',
        FingerReminderScope.both => 'Allebei',
      };

  String _formatReminderInterval(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return 'Elke $rest min';
    if (rest == 0) return 'Elke $hours uur';
    return 'Elke $hours uur $rest min';
  }

  Future<void> _onAlarmModeChanged(AlarmMode mode) async {
    if (mode == AlarmMode.off) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppColor.surface,
          title: Text('Alarm uitzetten?', style: AppText.cardTitle),
          content: Text(
            'Je krijgt geen waarschuwing meer bij een hypo. Weet je het '
            'zeker?',
            style: AppText.body.copyWith(color: AppColor.inkMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuleer'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(backgroundColor: AppColor.red),
              child: const Text('Alarm uitzetten'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => _alarmMode = mode);
  }

  Future<void> _testAlarm() async {
    _testAlarmTimer?.cancel();
    await AlarmNotificationService.instance.showAlarm(
      withSound: _alarmMode == AlarmMode.sound,
      breakSilentMode: _breakSilentMode,
      isHigh: false,
      mmol: _dailyLowBelow,
    );
    _testAlarmTimer = Timer(const Duration(seconds: 5), () {
      AlarmNotificationService.instance.cancelAlarm();
    });
  }

  void _addPreset() {
    final label = _newPreset.text.trim();
    if (label.isEmpty || _carbPresets.contains(label)) return;
    setState(() {
      _carbPresets.add(label);
      _newPreset.clear();
    });
  }

  Future<void> _openFoodPresetsSheet() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodPresetsScreen(controller: widget.controller),
      ),
    );
    // De presetpagina bewaart zelf; hier de lokale kopie bijwerken zodat
    // "Wijzigingen opslaan" ze niet terugzet.
    if (!mounted) return;
    setState(
      () => _foodPresets = List.of(
        widget.controller.profile?.foodPresets ?? const [],
      ),
    );
  }

  Future<void> _addBolusPeriod() async {
    final result = await showBolusPeriodDialog(context);
    if (result == null) return;
    setState(() => _bolusPeriods.add(result));
  }

  Future<void> _editBolusPeriod(int i) async {
    final result = await showBolusPeriodDialog(
      context,
      existing: _bolusPeriods[i],
    );
    if (result == null) return;
    setState(() => _bolusPeriods[i] = result);
  }

  Future<void> _editMeal(int? index) async {
    final existing = index == null ? null : _mealReminders[index];
    final label = TextEditingController(text: existing?.label ?? '');
    var time = TimeOfDay(
      hour: (existing?.minutesOfDay ?? 12 * 60) ~/ 60,
      minute: (existing?.minutesOfDay ?? 0) % 60,
    );
    final result = await showDialog<MealReminder>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(
            existing == null ? 'Eetmoment toevoegen' : 'Eetmoment',
            style: AppText.cardTitle,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: label,
                autofocus: existing == null,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Naam',
                  hintText: 'Bv. Ontbijt',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: c,
                    initialTime: time,
                  );
                  if (picked != null) setDialog(() => time = picked);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuleer'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                c,
                MealReminder(
                  label: label.text.trim().isEmpty ? 'Eten' : label.text.trim(),
                  time:
                      '${time.hour.toString().padLeft(2, '0')}:'
                      '${time.minute.toString().padLeft(2, '0')}',
                ),
              ),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _mealReminders.add(result);
      } else {
        _mealReminders[index] = result;
      }
      _mealReminders.sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
    });
  }

  Future<void> _save() async {
    if (!isValidAlarmLimits(
      trainingLimit: _trainingLimit,
      dailyLowBelow: _dailyLowBelow,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'De trainingsgrens moet minstens gelijk zijn aan de dagelijkse '
            'grens.',
          ),
        ),
      );
      return;
    }
    // Los geprobeerd: een mislukte secure-storage-schrijfactie (bv. een
    // keystore-probleem) mag de rest van de instellingen niet blokkeren.
    try {
      final dexcomPassword = _dexcomPassword.text.trim();
      if (dexcomPassword.isEmpty) {
        await DexcomCredentials.delete();
      } else {
        await DexcomCredentials.write(dexcomPassword);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dexcom-wachtwoord kon niet veilig worden opgeslagen. De '
              'overige instellingen worden wel bewaard.',
            ),
          ),
        );
      }
    }
    final profile = widget.controller.profile!;
    await widget.controller.saveProfile(
      profile.copyWith(
        glucoseSource: _source,
        trainingLimit: _trainingLimit,
        dailyLowBelow: _dailyLowBelow,
        dailyLowEnabled: _dailyLowEnabled,
        alarmMode: _alarmMode,
        breakSilentMode: _breakSilentMode,
        hyperLimit: _hyperLimit,
        hyperAlarmEnabled: _hyperAlarmEnabled,
        fingerReminderEnabled: _fingerReminderEnabled,
        fingerReminderScope: _fingerReminderScope,
        fingerReminderIntervalMinutes: _fingerReminderIntervalMinutes,
        nightscoutUrl: _nightscoutUrl.text,
        nightscoutToken: _nightscoutToken.text,
        dexcomUsername: _dexcomUsername.text,
        dexcomServer: _dexcomServer,
        carbPresets: _carbPresets,
        showPauseButton: _showPauseButton,
        alarmSnoozeMinutes: _alarmSnoozeMinutes,
        defaultRestSeconds: _defaultRestSeconds,
        spotifyButton: _spotifyButton,
        trainingAlarmMode: _trainingAlarmMode,
        clearTrainingAlarmMode: _trainingAlarmMode == null,
        circuitPrepSeconds: _circuitPrepSeconds,
        foodPresets: _foodPresets,
        weekStart: _weekStart,
        hideSystemBars: _hideSystemBars,
        dashboard: _dashboard,
        techniqueRemindersEnabled: _techRemindersEnabled,
        techniqueReminderDefaults: normalizeReminders([
          ..._techReminderDefaults,
        ]),
        techniqueReminderSound: _techReminderSound,
        foodWaitReminderSound: _foodWaitReminderSound,
        mealRemindersEnabled: _mealRemindersEnabled,
        mealReminders: _mealReminders,
        mealReminderOffset: _mealReminderOffset,
        mealOneOffEnabled: _mealOneOffEnabled,
        bolusCalculatorEnabled: _bolusCalculatorEnabled,
        bolusPeriods: _bolusPeriods,
        correctionFactor: _correctionFactor,
        correctionTargetDay: _correctionTargetDay,
        correctionTargetNight: _correctionTargetNight,
        correctionNightStart: _formatTimeOfDay(_correctionNightStart),
        correctionNightEnd: _formatTimeOfDay(_correctionNightEnd),
      ),
    );
    if (mounted && widget.controller.authError == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          backgroundColor: AppColor.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KINETIC',
                style: AppText.cardTitle.copyWith(
                  height: 1,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 3),
              const KLabel('Instellingen & alarmen'),
            ],
          ),
        ),
        // Opslaan altijd in beeld, niet weggestopt in een ingeklapte groep.
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.controller.authError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.controller.authError!,
                      style: AppText.caption.copyWith(
                        color: AppColor.redBright,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: widget.controller.busy ? null : _save,
                  child: Text(
                    widget.controller.busy
                        ? 'Opslaan...'
                        : 'Wijzigingen opslaan',
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            if (user?.email != null) ...[
              _AccountHeader(email: user!.email!),
              const SizedBox(height: AppSpace.lg),
            ],
            _Section(
              label: 'Alarm',
              child: IgnorePointer(
                ignoring: !_alarmsAvailable,
                child: Opacity(
                  opacity: _alarmsAvailable ? 1 : .4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_alarmsAvailable) ...[
                        Text(
                          'Alarmen werken alleen met een sensor (CGM). Met '
                          'vingerprik krijg je geen alarm.',
                          style: AppText.caption.copyWith(
                            color: AppColor.amberBright,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text('ALARM', style: AppText.overline),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final mode in AlarmMode.values)
                            ChoiceChip(
                              label: Text(_alarmModeLabel(mode)),
                              selected: _alarmMode == mode,
                              onSelected: _alarmsAvailable
                                  ? (_) => _onAlarmModeChanged(mode)
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('TIJDENS TRAINING', style: AppText.overline),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final mode in <AlarmMode?>[
                            null,
                            ...AlarmMode.values,
                          ])
                            ChoiceChip(
                              label: Text(
                                mode == null
                                    ? 'Zoals hierboven'
                                    : _alarmModeLabel(mode),
                              ),
                              selected: _trainingAlarmMode == mode,
                              onSelected: _alarmsAvailable
                                  ? (_) => setState(
                                      () => _trainingAlarmMode = mode,
                                    )
                                  : null,
                            ),
                        ],
                      ),
                      if (_alarmMode == AlarmMode.sound) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _InfoRow(
                                title: 'Doorbreek stille modus',
                                subtitle: 'Alarm gaat over DND/stil heen',
                                value: '',
                              ),
                            ),
                            Switch(
                              value: _breakSilentMode,
                              onChanged: _alarmsAvailable
                                  ? (v) => setState(() => _breakSilentMode = v)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoRow(
                              title: 'Dagelijkse ondergrens',
                              subtitle: 'Geldt als je niet traint.',
                              value: mmolText(_dailyLowBelow),
                              valueColor: _dailyLowEnabled
                                  ? AppColor.redBright
                                  : AppColor.inkFaint,
                            ),
                          ),
                          Switch(
                            value: _dailyLowEnabled,
                            onChanged: _alarmsAvailable
                                ? (v) => setState(() => _dailyLowEnabled = v)
                                : null,
                          ),
                        ],
                      ),
                      if (_dailyLowEnabled)
                        Slider(
                          value: _dailyLowBelow,
                          min: 3.0,
                          max: 6.0,
                          divisions: 30,
                          activeColor: AppColor.red,
                          inactiveColor: AppColor.line,
                          onChanged: (value) =>
                              setState(() => _dailyLowBelow = value),
                        ),
                      const Divider(),
                      _InfoRow(
                        title: 'Ondergrens tijdens training',
                        subtitle:
                            'Geldt alleen tijdens een sambo- of '
                            'krachtsessie.',
                        value: mmolText(_trainingLimit),
                        valueColor: AppColor.redBright,
                      ),
                      Slider(
                        value: _trainingLimit,
                        min: 4.0,
                        max: 8.0,
                        divisions: 40,
                        activeColor: AppColor.red,
                        inactiveColor: AppColor.line,
                        onChanged: (value) =>
                            setState(() => _trainingLimit = value),
                      ),
                      const Divider(),
                      _InfoRow(
                        title: 'Sluimertijd',
                        subtitle:
                            'Zo lang blijft het alarm stil na "Sluimeren" of '
                            '"Ingenomen". Herstelt je waarde intussen, dan '
                            'gaat het niet meer af.',
                        value: '$_alarmSnoozeMinutes min',
                      ),
                      Slider(
                        value: _alarmSnoozeMinutes.toDouble(),
                        min: 5,
                        max: 60,
                        divisions: 11,
                        activeColor: AppColor.teal,
                        inactiveColor: AppColor.line,
                        onChanged: (value) =>
                            setState(() => _alarmSnoozeMinutes = value.round()),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _alarmMode == AlarmMode.off
                            ? null
                            : _testAlarm,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Test alarm'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Bovengrens (hyper)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          title: 'Bovengrens (hyper)',
                          subtitle: _hyperAlarmEnabled
                              ? 'Alarm bij te hoge waarde'
                              : 'Alarm uitgeschakeld',
                          value: mmolText(_hyperLimit),
                          valueColor: _hyperAlarmEnabled
                              ? AppColor.amberBright
                              : AppColor.inkFaint,
                        ),
                      ),
                      Switch(
                        value: _hyperAlarmEnabled,
                        onChanged: (v) =>
                            setState(() => _hyperAlarmEnabled = v),
                      ),
                    ],
                  ),
                  if (_hyperAlarmEnabled)
                    Slider(
                      value: _hyperLimit,
                      min: 7.0,
                      max: 20.0,
                      divisions: 26,
                      activeColor: AppColor.amber,
                      inactiveColor: AppColor.line,
                      onChanged: (value) => setState(() => _hyperLimit = value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Bronnen',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<GlucoseSource>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: GlucoseSource.dexcomShare,
                        label: Text(
                          'Dexcom G7',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ButtonSegment(
                        value: GlucoseSource.nightscout,
                        label: Text(
                          'Nightscout',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ButtonSegment(
                        value: GlucoseSource.finger,
                        label: Text(
                          'Vingerprik',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (value) => setState(() {
                      _source = value.first;
                      _dexcomTestResult = null;
                    }),
                  ),
                  if (_source == GlucoseSource.nightscout) ...[
                    const SizedBox(height: 14),
                    _TextBox(
                      controller: _nightscoutUrl,
                      label: 'Nightscout URL',
                    ),
                    const SizedBox(height: 10),
                    _TextBox(
                      controller: _nightscoutToken,
                      label: 'Token of secret',
                      obscure: true,
                    ),
                  ] else if (_source == GlucoseSource.dexcomShare) ...[
                    const SizedBox(height: 14),
                    _TextBox(
                      controller: _dexcomUsername,
                      label: 'Dexcom-gebruikersnaam',
                    ),
                    const SizedBox(height: 10),
                    _TextBox(
                      controller: _dexcomPassword,
                      label: 'Dexcom-wachtwoord',
                      obscure: true,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 'shareous1.dexcom.com',
                          label: Text(
                            'Buiten de VS',
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ButtonSegment(
                          value: 'share2.dexcom.com',
                          label: Text('VS'),
                        ),
                      ],
                      selected: {_dexcomServer},
                      onSelectionChanged: (value) =>
                          setState(() => _dexcomServer = value.first),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _testingDexcom ? null : _testDexcomConnection,
                      child: Text(
                        _testingDexcom
                            ? 'Verbinding testen...'
                            : 'Verbinding testen',
                      ),
                    ),
                    if (_dexcomTestResult != null) ...[
                      const SizedBox(height: 8),
                      Text(_dexcomTestResult!, style: AppText.caption),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Werkt via hetzelfde "Delen"-kanaal als de Dexcom-app — '
                      'zet delen aan in de Dexcom-app zelf. Dit is geen '
                      'officiële Dexcom-koppeling en kan enkele minuten '
                      'achterlopen.',
                      style: AppText.caption.copyWith(fontSize: 10),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Je voert je glucose zelf in op de "Vandaag"-pagina en '
                        'tijdens een training.',
                        style: AppText.caption,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Vingerprik-herinnering',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          title: 'Herinnering aan',
                          subtitle:
                              'Geen alarm — komt ook binnen als de app '
                              'gesloten is.',
                          value: '',
                        ),
                      ),
                      Switch(
                        value: _fingerReminderEnabled,
                        onChanged: (v) =>
                            setState(() => _fingerReminderEnabled = v),
                      ),
                    ],
                  ),
                  if (_fingerReminderEnabled) ...[
                    const SizedBox(height: 10),
                    Text('ONTVANGEN BIJ', style: AppText.overline),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final scope in FingerReminderScope.values)
                          ChoiceChip(
                            label: Text(_fingerReminderScopeLabel(scope)),
                            selected: _fingerReminderScope == scope,
                            onSelected: (_) =>
                                setState(() => _fingerReminderScope = scope),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                      title: 'Interval',
                      value: _formatReminderInterval(
                        _fingerReminderIntervalMinutes,
                      ),
                    ),
                    Slider(
                      value: _fingerReminderIntervalMinutes.toDouble(),
                      min: 15,
                      max: 480,
                      divisions: (480 - 15) ~/ 15,
                      activeColor: AppColor.teal,
                      inactiveColor: AppColor.line,
                      onChanged: (value) => setState(
                        () => _fingerReminderIntervalMinutes = value.round(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Sessie',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          title: 'Pauzeknop tonen',
                          subtitle: 'Tijdens een live training/sparren',
                          value: '',
                        ),
                      ),
                      Switch(
                        value: _showPauseButton,
                        onChanged: (v) => setState(() => _showPauseButton = v),
                      ),
                    ],
                  ),
                  const Divider(),
                  _InfoRow(
                    title: 'Standaard rust (kracht)',
                    subtitle:
                        'Na elke set, of na een blok. Per oefening of blok '
                        'aan te passen.',
                    value: formatRest(_defaultRestSeconds),
                  ),
                  Slider(
                    value: _defaultRestSeconds.toDouble(),
                    min: 15,
                    max: 300,
                    divisions: 19,
                    activeColor: AppColor.teal,
                    inactiveColor: AppColor.line,
                    onChanged: (value) =>
                        setState(() => _defaultRestSeconds = value.round()),
                  ),
                  const Divider(),
                  _InfoRow(
                    title: 'Voorbereiden',
                    subtitle:
                        'Aftellen vóór elke circuitoefening en tijd-set '
                        '(bv. plank), om je halters af te stellen.',
                    value: _circuitPrepSeconds == 0
                        ? 'Uit'
                        : '$_circuitPrepSeconds s',
                  ),
                  Slider(
                    value: _circuitPrepSeconds.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 12,
                    activeColor: AppColor.teal,
                    inactiveColor: AppColor.line,
                    onChanged: (value) =>
                        setState(() => _circuitPrepSeconds = value.round()),
                  ),
                  const Divider(),
                  _InfoRow(
                    title: 'Spotify-knop',
                    subtitle: 'Bij welke trainingen de knop zichtbaar is.',
                    value: '',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (option, label) in const [
                        (SpotifyButtonPlacement.both, 'Kracht en sambo'),
                        (SpotifyButtonPlacement.strength, 'Alleen kracht'),
                        (SpotifyButtonPlacement.mat, 'Alleen sambo'),
                        (SpotifyButtonPlacement.off, 'Verbergen'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _spotifyButton == option,
                          onSelected: (_) =>
                              setState(() => _spotifyButton = option),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Voeding tijdens training',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Presets die je tijdens een training met één tik kunt loggen.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 12),
                  if (_carbPresets.isEmpty)
                    Text('Nog geen presets.', style: AppText.caption)
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in _carbPresets)
                          Chip(
                            label: Text(p),
                            backgroundColor: AppColor.surfaceRaised,
                            labelStyle: AppText.body.copyWith(fontSize: 12),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () =>
                                setState(() => _carbPresets.remove(p)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newPreset,
                          style: AppText.body,
                          onSubmitted: (_) => _addPreset(),
                          decoration: InputDecoration(
                            hintText: 'Bijv. AA, Melk, Ontbijtkoek',
                            filled: true,
                            fillColor: AppColor.surfaceRaised,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addPreset,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Eetlogboek',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Presets met koolhydraten — +/− in het eetlogboek telt '
                    'meteen op/af in aantal en koolhydraten.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _openFoodPresetsSheet,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Presets', style: AppText.bodyStrong),
                                const SizedBox(height: 2),
                                Text(
                                  _foodPresets.isEmpty
                                      ? 'Nog geen presets'
                                      : '${_foodPresets.length} presets',
                                  style: AppText.caption,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColor.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          title: 'Geluid bij eet-herinneringen',
                          subtitle:
                              '"Tijd om te eten" na de wachttijd na '
                              'insuline, en je eetmomenten.',
                          value: '',
                        ),
                      ),
                      Switch(
                        value: _foodWaitReminderSound,
                        onChanged: (v) =>
                            setState(() => _foodWaitReminderSound = v),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mealRemindersEnabled,
                    onChanged: (v) => setState(() {
                      _mealRemindersEnabled = v;
                      if (v && _mealReminders.isEmpty) {
                        _mealReminders = List.of(kDefaultMealReminders);
                      }
                    }),
                    title: Text('Vaste eetmomenten', style: AppText.bodyStrong),
                    subtitle: Text(
                      'Elke dag een melding op je eettijden.',
                      style: AppText.caption,
                    ),
                  ),
                  if (_mealRemindersEnabled) ...[
                    for (var i = 0; i < _mealReminders.length; i++)
                      _MealReminderRow(
                        meal: _mealReminders[i],
                        onTap: () => _editMeal(i),
                        onDelete: () =>
                            setState(() => _mealReminders.removeAt(i)),
                      ),
                    TextButton.icon(
                      onPressed: () => _editMeal(null),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Eetmoment'),
                    ),
                    const SizedBox(height: 6),
                    Text('Melding', style: AppText.caption),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (m, label) in const [
                          (0, 'Op tijd'),
                          (10, '10 min vooraf'),
                          (15, '15 min vooraf'),
                          (20, '20 min vooraf'),
                          (30, '30 min vooraf'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _mealReminderOffset == m,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _mealReminderOffset = m),
                          ),
                      ],
                    ),
                  ],
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mealOneOffEnabled,
                    onChanged: (v) => setState(() => _mealOneOffEnabled = v),
                    title: Text(
                      'Eenmalige herinnering',
                      style: AppText.bodyStrong,
                    ),
                    subtitle: Text(
                      'Knop "Herinner me om …" op de Eten-pagina.',
                      style: AppText.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Bolus-calculator',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          title: 'Bolus-calculator inschakelen',
                          subtitle:
                              'Live voorstel voor voedings- en '
                              'correctie-insuline bij het loggen van eten.',
                          value: '',
                        ),
                      ),
                      Switch(
                        value: _bolusCalculatorEnabled,
                        onChanged: (v) =>
                            setState(() => _bolusCalculatorEnabled = v),
                      ),
                    ],
                  ),
                  if (_bolusCalculatorEnabled) ...[
                    const SizedBox(height: 16),
                    Text('TIJDVAKKEN', style: AppText.overline),
                    const SizedBox(height: 8),
                    if (_bolusPeriods.isEmpty)
                      Text('Nog geen tijdvakken.', style: AppText.caption)
                    else
                      for (var i = 0; i < _bolusPeriods.length; i++)
                        _BolusPeriodRow(
                          period: _bolusPeriods[i],
                          onTap: () => _editBolusPeriod(i),
                          onDelete: () =>
                              setState(() => _bolusPeriods.removeAt(i)),
                        ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addBolusPeriod,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tijdvak toevoegen'),
                    ),
                    const SizedBox(height: 20),
                    _InfoRow(
                      title: 'Correctiefactor',
                      subtitle: 'mmol/L daling per eenheid',
                      value: mmolText(_correctionFactor),
                    ),
                    Slider(
                      value: _correctionFactor.clamp(0.5, 6.0),
                      min: 0.5,
                      max: 6.0,
                      divisions: 11,
                      activeColor: AppColor.teal,
                      inactiveColor: AppColor.line,
                      onChanged: (value) =>
                          setState(() => _correctionFactor = value),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      title: 'Streefwaarde overdag',
                      value: mmolText(_correctionTargetDay),
                    ),
                    Slider(
                      value: _correctionTargetDay.clamp(4.0, 14.0),
                      min: 4.0,
                      max: 14.0,
                      divisions: 20,
                      activeColor: AppColor.teal,
                      inactiveColor: AppColor.line,
                      onChanged: (value) =>
                          setState(() => _correctionTargetDay = value),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      title: 'Streefwaarde \'s nachts',
                      value: mmolText(_correctionTargetNight),
                    ),
                    Slider(
                      value: _correctionTargetNight.clamp(4.0, 14.0),
                      min: 4.0,
                      max: 14.0,
                      divisions: 20,
                      activeColor: AppColor.teal,
                      inactiveColor: AppColor.line,
                      onChanged: (value) =>
                          setState(() => _correctionTargetNight = value),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _TimePickerBox(
                            label: 'NACHT VAN',
                            time: _correctionNightStart,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _correctionNightStart,
                              );
                              if (picked != null) {
                                setState(() => _correctionNightStart = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TimePickerBox(
                            label: 'NACHT TOT',
                            time: _correctionNightEnd,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _correctionNightEnd,
                              );
                              if (picked != null) {
                                setState(() => _correctionNightEnd = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Techniek-herinneringen',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _techRemindersEnabled,
                    onChanged: (v) => setState(() => _techRemindersEnabled = v),
                    title: Text(
                      'Herinneren welke techniek ik oefen',
                      style: AppText.bodyStrong,
                    ),
                    subtitle: Text(
                      'Koppel technieken aan een geplande training (in de '
                      'Agenda of bij de techniek). Per training kun je de '
                      'momenten zelf aanpassen, ook tijdens de training.',
                      style: AppText.caption,
                    ),
                  ),
                  if (_techRemindersEnabled) ...[
                    const SizedBox(height: 6),
                    Text('Standaard melden', style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'Vooraf, bij de start en/of tijdens de training — zo '
                      'staat het klaar bij een nieuwe training met '
                      'technieken. "Na de start" werkt ook als je zonder '
                      'planning een training start.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in const [
                          1440,
                          120,
                          60,
                          30,
                          15,
                          0,
                          -15,
                          -30,
                        ])
                          FilterChip(
                            label: Text(reminderLabel(m)),
                            selected: _techReminderDefaults.contains(m),
                            showCheckmark: false,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _techReminderDefaults.add(m);
                              } else {
                                _techReminderDefaults.remove(m);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _techReminderSound,
                      onChanged: (v) => setState(() => _techReminderSound = v),
                      title: Text('Met geluid', style: AppText.bodyStrong),
                      subtitle: Text(
                        _techReminderSound
                            ? 'Melding met alarmgeluid.'
                            : 'Stille melding (alleen trillen en in de balk).',
                        style: AppText.caption,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Dashboard',
              child: DashboardEditor(
                config: _dashboard,
                onChanged: (c) => setState(() => _dashboard = c),
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Weergave',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hideSystemBars,
                onChanged: (v) => setState(() => _hideSystemBars = v),
                title: Text(
                  'Systeemknoppen verbergen',
                  style: AppText.bodyStrong,
                ),
                subtitle: Text(
                  'Verbergt de navigatieknoppen en statusbalk van je telefoon '
                  'in de hele app. Veeg vanaf de rand om ze even terug te '
                  'halen. Tijdens een live training gebeurt dit altijd.',
                  style: AppText.caption,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Agenda',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Week begint op', style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    'Geldt voor alle kalenders en datumkiezers in de app.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (day, label) in const [
                        (1, 'Maandag'),
                        (0, 'Zondag'),
                        (6, 'Zaterdag'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _weekStart == day,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _weekStart = day),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Section(
              label: 'Account',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.email ?? 'Onbekend account',
                    style: AppText.bodyStrong,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: widget.controller.busy
                        ? null
                        : () async {
                            await widget.controller.signOut();
                            if (context.mounted) {
                              Navigator.popUntil(
                                context,
                                (route) => route.isFirst,
                              );
                            }
                          },
                    child: const Text('Uitloggen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eén instellingengroep: een compacte, tikbare kopregel; de inhoud klapt
/// pas open als je erop tikt — zo blijft de pagina overzichtelijk.
class _Section extends StatefulWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  static const _icons = <String, IconData>{
    'Alarm': Icons.notifications_active_outlined,
    'Bovengrens (hyper)': Icons.trending_up,
    'Bronnen': Icons.sensors,
    'Vingerprik-herinnering': Icons.water_drop_outlined,
    'Techniek-herinneringen': Icons.sports_martial_arts_outlined,
    'Sessie': Icons.timer_outlined,
    'Voeding tijdens training': Icons.local_dining_outlined,
    'Eetlogboek': Icons.restaurant_outlined,
    'Bolus-calculator': Icons.calculate_outlined,
    'Oefeningen': Icons.fitness_center,
    "Trainingsschema's": Icons.view_list_outlined,
    'Circuits': Icons.loop,
    'Dashboard': Icons.dashboard_outlined,
    'Weergave': Icons.fullscreen,
    'Agenda': Icons.event_outlined,
    'Account': Icons.person_outline,
  };

  /// Korte omschrijving onder de titel, zodat je ziet wat erin zit zonder
  /// open te klappen.
  static const _hints = <String, String>{
    'Alarm': 'Geluid, tijdens training, grenzen, sluimeren',
    'Bovengrens (hyper)': 'Alarm bij een hoge waarde',
    'Bronnen': 'Dexcom, Nightscout of vingerprik',
    'Vingerprik-herinnering': 'Herinnering om te prikken',
    'Techniek-herinneringen': 'Technieken oefenen bij trainingen',
    'Sessie': 'Pauzeknop, rust, voorbereiden, Spotify',
    'Voeding tijdens training': 'Snelle keuzes tijdens een sessie',
    'Eetlogboek': 'Presets, wachttijd en eet-herinneringen',
    'Bolus-calculator': "Ratio's en correctie",
    'Dashboard': 'Wat er op Vandaag staat',
    'Weergave': 'Systeembalken',
    'Agenda': 'Eerste dag van de week',
    'Account': 'Uitloggen',
  };

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hint = _Section._hints[widget.label];
    // Material (geen gekleurde Container): dan zijn tik-effecten van
    // schakelaars en lijstregels in de sectie gewoon zichtbaar.
    return Material(
      color: AppColor.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    _Section._icons[widget.label] ?? Icons.tune,
                    size: 20,
                    color: AppColor.ice,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label, style: AppText.bodyStrong),
                        if (hint != null)
                          Text(
                            hint,
                            style: AppText.caption.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: AppColor.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(width: double.infinity, child: widget.child),
            ),
        ],
      ),
    );
  }
}

/// Kop bovenaan: wie is ingelogd, en dat het profiel in Supabase staat.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final local = email.split('@').first;
    final initials = local
        .split(RegExp(r'[._-]'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColor.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColor.ice, width: 1.5),
            ),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: AppText.cardTitle.copyWith(color: AppColor.ice),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: AppText.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                const KLabel('Sambo · glucose-HUD'),
              ],
            ),
          ),
          const KPill(text: 'Synced', color: AppColor.ice, dot: true),
        ],
      ),
    );
  }
}

class _MealReminderRow extends StatelessWidget {
  const _MealReminderRow({
    required this.meal,
    required this.onTap,
    required this.onDelete,
  });

  final MealReminder meal;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              meal.time,
              style: AppText.bodyStrong.copyWith(color: AppColor.ice),
            ),
          ),
          Expanded(child: Text(meal.label, style: AppText.body)),
          IconButton(
            tooltip: 'Verwijderen',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 18, color: AppColor.inkFaint),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    this.subtitle,
    required this.value,
    this.valueColor,
  });

  final String title;
  final String? subtitle;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppText.caption.copyWith(color: AppColor.inkFaint),
                  ),
              ],
            ),
          ),
          Text(value, style: AppText.cardTitle.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    required this.controller,
    required this.label,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: AppText.body,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColor.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}

class _BolusPeriodRow extends StatelessWidget {
  const _BolusPeriodRow({
    required this.period,
    required this.onTap,
    required this.onDelete,
  });

  final BolusPeriod period;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColor.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${period.label} vanaf ${period.startTime}',
                    style: AppText.bodyStrong.copyWith(fontSize: 13),
                  ),
                  Text(
                    '1 E per ${carbsText(period.carbRatio)} g',
                    style: AppText.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: AppColor.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerBox extends StatelessWidget {
  const _TimePickerBox({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.overline),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: AppColor.inkMuted),
                const SizedBox(width: 10),
                Text(time.format(context), style: AppText.bodyStrong),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Modal met de volledige lijst presets voor het eetlogboek — bewerken,
/// verwijderen en toevoegen zitten allemaal hier, zodat het instellingen-
/// scherm zelf compact blijft.
Future<FoodPreset?> showFoodPresetDialog(
  BuildContext context, {
  FoodPreset? existing,
}) {
  final singular = TextEditingController(text: existing?.singular ?? '');
  final plural = TextEditingController(text: existing?.plural ?? '');
  final carbs = TextEditingController(
    text: existing != null ? carbsText(existing.carbs) : '',
  );
  final unitAmount = TextEditingController(
    text: existing != null && existing.unitAmount > 0
        ? carbsText(existing.unitAmount)
        : '',
  );
  final unitLabel = TextEditingController(text: existing?.unitLabel ?? '');
  return showDialog<FoodPreset>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColor.surface,
      title: Text(
        existing == null ? 'Preset toevoegen' : 'Preset aanpassen',
        style: AppText.cardTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: singular,
              style: AppText.body,
              decoration: const InputDecoration(
                labelText: 'Enkelvoud (bv. boterham)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: plural,
              style: AppText.body,
              decoration: const InputDecoration(
                labelText: 'Meervoud (bv. boterhammen)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: carbs,
              style: AppText.body,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Koolhydraten per stuk',
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: unitAmount,
                    style: AppText.body,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Hoeveelheid per stuk',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unitLabel,
                    style: AppText.body,
                    decoration: const InputDecoration(
                      labelText: 'Eenheid',
                      hintText: 'ml, g, ...',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Optioneel — bv. 250 ml per glas melk of 150 g per bakje yoghurt. '
              'Telt mee op bij +/− in het eetlogboek.',
              style: AppText.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        FilledButton(
          onPressed: () {
            final s = singular.text.trim();
            if (s.isEmpty) return;
            final p = plural.text.trim();
            final carbsValue =
                double.tryParse(carbs.text.trim().replaceAll(',', '.')) ?? 0;
            final unitAmountValue =
                double.tryParse(unitAmount.text.trim().replaceAll(',', '.')) ??
                0;
            Navigator.pop(
              c,
              FoodPreset(
                singular: s,
                plural: p.isEmpty ? s : p,
                carbs: carbsValue,
                unitAmount: unitAmountValue,
                unitLabel: unitLabel.text.trim(),
              ),
            );
          },
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
}

Future<BolusPeriod?> showBolusPeriodDialog(
  BuildContext context, {
  BolusPeriod? existing,
}) {
  final label = TextEditingController(text: existing?.label ?? '');
  final carbRatio = TextEditingController(
    text: existing != null ? carbsText(existing.carbRatio) : '',
  );
  var startTime = existing != null
      ? TimeOfDay(
          hour: int.tryParse(existing.startTime.split(':').first) ?? 0,
          minute: int.tryParse(existing.startTime.split(':').last) ?? 0,
        )
      : const TimeOfDay(hour: 0, minute: 0);

  return showDialog<BolusPeriod>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialogState) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text(
          existing == null ? 'Tijdvak toevoegen' : 'Tijdvak aanpassen',
          style: AppText.cardTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Naam (bv. Ochtend)',
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: c,
                    initialTime: startTime,
                  );
                  if (picked != null) {
                    setDialogState(() => startTime = picked);
                  }
                },
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Vanaf'),
                  child: Text(startTime.format(c), style: AppText.body),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: carbRatio,
                style: AppText.body,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Koolhydraatratio',
                  suffixText: 'g per 1 E',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dit tijdvak loopt tot het volgende tijdvak begint.',
                style: AppText.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () {
              final l = label.text.trim();
              if (l.isEmpty) return;
              final ratio =
                  double.tryParse(carbRatio.text.trim().replaceAll(',', '.')) ??
                  0;
              Navigator.pop(
                c,
                BolusPeriod(
                  label: l,
                  startTime:
                      '${startTime.hour.toString().padLeft(2, '0')}:'
                      '${startTime.minute.toString().padLeft(2, '0')}',
                  carbRatio: ratio,
                ),
              );
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    ),
  );
}
