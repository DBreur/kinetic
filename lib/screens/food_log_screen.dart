// food_log_screen.dart — eetlogboek voor diabetes, in de geest van mySugr:
// wat je hebt gegeten, presets met +/− (net als de voedingslog tijdens een
// training) die meteen de omschrijving én de koolhydraten bijwerken, en je
// glucosewaarde op dat moment. Aan te passen achteraf, te exporteren als
// PDF of CSV.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/bolus_calculator.dart';
import '../core/food_log_export.dart';
import '../core/food_preset_usage.dart';
import '../core/glucose_prefill.dart';
import '../core/formatters.dart';
import '../models/app_profile.dart';
import '../models/food_log_entry.dart';
import '../models/food_preset.dart';
import '../models/glucose.dart';
import '../repositories/food_log_repository.dart';
import '../services/food_wait_reminder_service.dart';
import '../services/meal_reminder_service.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/food_preset_picker.dart';
import 'food_presets_screen.dart';
import '../widgets/kinetic.dart';

class FoodLogScreen extends StatefulWidget {
  const FoodLogScreen({
    super.key,
    required this.controller,
    this.openNewMeal = false,
  });

  final AppController controller;

  /// Meteen het blad "maaltijd loggen" openen (snelle actie op het
  /// dashboard).
  final bool openNewMeal;

  @override
  State<FoodLogScreen> createState() => FoodLogScreenState();
}

/// Publiek zodat de shell de export rechtsboven in de topbalk kan tonen.
class FoodLogScreenState extends State<FoodLogScreen> {
  late final FoodLogRepository _repo;
  List<FoodLogEntry> _entries = [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  List<FoodPreset> get _presets =>
      widget.controller.profile?.foodPresets ?? const [];

  @override
  void initState() {
    super.initState();
    _repo = FoodLogRepository(widget.controller.client!);
    _load();
    if (widget.openNewMeal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addOrEdit();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final entries = await _repo.listForUser(userId);
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      // Lijst blijft leeg/oud; pull-to-refresh laat het opnieuw proberen.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({FoodLogEntry? existing}) async {
    final profile = widget.controller.profile!;
    final fromSensor = profile.glucoseSource != GlucoseSource.finger;
    final latest = widget.controller.cachedGlucose?.reading;
    // Nieuw eetmoment: altijd even de nieuwste meting ophalen (via de
    // app-brede ophaler). Het blad gaat meteen open met de laatst bekende
    // waarde en wordt bijgewerkt zodra er een nieuwere binnen is — tenzij je
    // zelf al iets hebt ingevuld.
    Future<GlucoseReading?>? fresh;
    if (existing == null) {
      fresh = () async {
        try {
          await widget.controller.refreshGlucose().timeout(
            const Duration(seconds: 8),
          );
        } catch (_) {
          // Time-out of geen verbinding: dan blijft de bekende waarde staan.
        }
        final now = widget.controller.cachedGlucose?.reading;
        if (now == null) return null;
        if (latest != null && !now.at.isAfter(latest.at)) return null;
        return now;
      }();
    }
    final result = await showFoodLogEntrySheet(
      context,
      presets: _presets,
      profile: profile,
      existing: existing,
      usage: presetUsage(_entries, now: DateTime.now()),
      latestReading: latest,
      freshReading: fresh,
      liveGlucose: widget.controller.glucose,
      readingFromSensor: fromSensor,
    );
    if (result == null) return;
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      if (result.deleted) {
        if (existing != null) await _repo.delete(existing.id);
      } else if (existing != null) {
        await _repo.update(
          existing.copyWith(
            at: result.at,
            description: result.description,
            presetCounts: result.presetCounts,
            carbs: result.carbs,
            clearCarbs: result.carbs == null,
            mmol: result.mmol,
            clearMmol: result.mmol == null,
            insulinUnits: result.insulinUnits,
            clearInsulinUnits: result.insulinUnits == null,
            insulinTiming: result.insulinTiming,
            clearInsulinTiming: result.insulinTiming == null,
            insulinFoodUnits: result.insulinFoodUnits,
            clearInsulinFoodUnits: result.insulinFoodUnits == null,
            insulinCorrectionUnits: result.insulinCorrectionUnits,
            clearInsulinCorrectionUnits: result.insulinCorrectionUnits == null,
            insulinNote: result.insulinNote,
            insulinWaitMinutes: result.insulinWaitMinutes,
            clearInsulinWaitMinutes: result.insulinWaitMinutes == null,
          ),
        );
      } else {
        await _repo.create(
          userId,
          result.at!,
          result.description!,
          result.presetCounts!,
          result.carbs,
          result.mmol,
          insulinUnits: result.insulinUnits,
          insulinTiming: result.insulinTiming,
          insulinFoodUnits: result.insulinFoodUnits,
          insulinCorrectionUnits: result.insulinCorrectionUnits,
          insulinNote: result.insulinNote,
          insulinWaitMinutes: result.insulinWaitMinutes,
        );
      }
      if (!result.deleted && result.insulinWaitMinutes != null) {
        await FoodWaitReminderService.instance
            .requestExactAlarmPermissionIfNeeded();
        await FoodWaitReminderService.instance.scheduleReminder(
          result.at!,
          result.insulinWaitMinutes!,
          withSound: widget.controller.profile?.foodWaitReminderSound ?? true,
        );
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> exportLog(bool asPdf) async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nog niets om te exporteren.')),
      );
      return;
    }
    if (asPdf) {
      await exportFoodLogAsPdf(_entries);
    } else {
      await exportFoodLogAsCsv(_entries);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _entries
        : _entries
              .where(
                (e) =>
                    e.description.toLowerCase().contains(query) ||
                    dutchDateTime(e.at).toLowerCase().contains(query),
              )
              .toList();
    final profile = widget.controller.profile;
    final now = DateTime.now();
    final today = _entries.where((e) => _sameDay(e.at, now)).toList();
    final waiting = _activeWait(now);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          4,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          if (waiting != null) ...[
            _WaitTimerCard(entry: waiting.$1, eatAt: waiting.$2),
            const SizedBox(height: AppSpace.md),
          ],
          if (profile != null && profile.mealOneOffEnabled) ...[
            _OneOffMealReminder(withSound: profile.foodWaitReminderSound),
            const SizedBox(height: AppSpace.md),
          ],
          if (profile != null)
            _BolusHeroCard(
              profile: profile,
              today: today,
              presetCount: _presets.length,
              onManagePresets: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FoodPresetsScreen(
                      controller: widget.controller,
                      usage: presetUsage(_entries, now: DateTime.now()),
                    ),
                  ),
                );
                if (mounted) setState(() {});
              },
              onLog: () => _addOrEdit(),
            ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: _searching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: AppText.bodyStrong,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Zoek op omschrijving of datum',
                        ),
                      )
                    : Text('Maaltijdlogboek', style: AppText.cardTitle),
              ),
              IconButton(
                tooltip: _searching ? 'Sluiten' : 'Zoeken',
                onPressed: _toggleSearch,
                icon: Icon(
                  _searching ? Icons.close : Icons.search,
                  color: AppColor.inkMuted,
                ),
              ),
              if (!_searching)
                PopupMenuButton<bool>(
                  tooltip: 'Exporteren',
                  icon: const Icon(Icons.ios_share, color: AppColor.inkMuted),
                  onSelected: exportLog,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: true,
                      child: Text('Exporteer als PDF'),
                    ),
                    PopupMenuItem(
                      value: false,
                      child: Text('Exporteer als CSV'),
                    ),
                  ],
                ),
              if (!_searching)
                KLabel('${today.length} vandaag', color: AppColor.inkFaint),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (!_loading && filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                query.isNotEmpty ? 'Niets gevonden voor "$_query".' : 'Nog niets gelogd. Tik op "Maaltijd loggen" om bij te houden wat je hebt gegeten.',
                style: AppText.caption,
              ),
            ),
          for (var i = 0; i < filtered.length; i++) ...[
            if (i == 0 || !_sameDay(filtered[i].at, filtered[i - 1].at))
              Padding(
                padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 16, 0, 8),
                child: KLabel(_dayLabel(filtered[i].at)),
              ),
            _FoodLogRow(
              entry: filtered[i],
              onTap: () => _addOrEdit(existing: filtered[i]),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }

  /// De laatst gelogde maaltijd met een wachttijd waarvan het eetmoment nog
  /// niet voorbij is — voor de aftelkaart bovenaan.
  (FoodLogEntry, DateTime)? _activeWait(DateTime now) {
    for (final e in _entries) {
      final wait = e.insulinWaitMinutes;
      if (wait == null) continue;
      final eatAt = e.at.add(Duration(seconds: (wait * 60).round()));
      if (eatAt.isAfter(now)) return (e, eatAt);
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return 'Vandaag';
    if (day == today.subtract(const Duration(days: 1))) return 'Gisteren';
    return dutchShortDate(at);
  }
}

// ───────────────────── kaarten bovenaan ─────────────────────────────────────

/// "Herinner me om …": één melding op een zelfgekozen tijd. Toont de
/// ingestelde herinnering met een knop om hem te annuleren.
class _OneOffMealReminder extends StatefulWidget {
  const _OneOffMealReminder({required this.withSound});

  final bool withSound;

  @override
  State<_OneOffMealReminder> createState() => _OneOffMealReminderState();
}

class _OneOffMealReminderState extends State<_OneOffMealReminder> {
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    MealReminderService.instance.pendingOneOff().then((at) {
      if (mounted) setState(() => _at = at);
    });
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final suggestion = now.add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: suggestion.hour, minute: 0),
      helpText: 'Herinner me om',
    );
    if (time == null || !mounted) return;
    var at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    // Tijd al voorbij vandaag? Dan morgen.
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await MealReminderService.instance.scheduleOneOff(
      at,
      withSound: widget.withSound,
    );
    if (mounted) setState(() => _at = at);
  }

  Future<void> _cancel() async {
    await MealReminderService.instance.cancelOneOff();
    if (mounted) setState(() => _at = null);
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    if (at == null) {
      return OutlinedButton.icon(
        onPressed: _pick,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: const Icon(Icons.alarm_add_outlined, size: 20),
        label: const Text('Herinner me om …'),
      );
    }
    final tomorrow = at.day != DateTime.now().day;
    return KCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.alarm_on, color: AppColor.ice),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              'Eet-herinnering ${tomorrow ? 'morgen ' : ''}om '
              '${DateFormat('HH:mm').format(at)}',
              style: AppText.bodyStrong,
            ),
          ),
          TextButton(onPressed: _pick, child: const Text('Wijzig')),
          IconButton(
            tooltip: 'Annuleren',
            onPressed: _cancel,
            icon: const Icon(Icons.close, color: AppColor.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Bolus-adviseur: actief tijdvak (KH-ratio), correctie-instellingen en het
/// dagtotaal, met de grote knop om een maaltijd te loggen.
class _BolusHeroCard extends StatelessWidget {
  const _BolusHeroCard({
    required this.profile,
    required this.today,
    required this.presetCount,
    required this.onManagePresets,
    required this.onLog,
  });

  final AppProfile profile;
  final List<FoodLogEntry> today;
  final int presetCount;
  final VoidCallback onManagePresets;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final carbs = today.fold<double>(0, (n, e) => n + (e.carbs ?? 0));
    final insulin = today.fold<double>(0, (n, e) => n + (e.insulinUnits ?? 0));
    final period = profile.bolusCalculatorEnabled
        ? activePeriod(profile.bolusPeriods, now)
        : null;
    final night = isNight(
      now,
      profile.correctionNightStart,
      profile.correctionNightEnd,
    );
    final target = night
        ? profile.correctionTargetNight
        : profile.correctionTargetDay;

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KCardHeader(
            icon: Icons.calculate_outlined,
            iconColor: AppColor.coral,
            label: profile.bolusCalculatorEnabled
                ? 'Bolus-adviseur'
                : 'Maaltijd & insuline',
            trailing: profile.bolusCalculatorEnabled
                ? KPill(
                    text: period?.label.isNotEmpty == true
                        ? period!.label
                        : (night ? 'Nacht' : 'Dag'),
                    color: AppColor.ice,
                    dot: true,
                  )
                : null,
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: KMetricTile(
                  label: 'KH vandaag',
                  value: carbsText(carbs),
                  unit: 'g',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KMetricTile(
                  label: 'Insuline',
                  value: carbsText(insulin),
                  unit: 'E',
                  valueColor: AppColor.coralSoft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KMetricTile(label: 'Momenten', value: '${today.length}'),
              ),
            ],
          ),
          if (profile.bolusCalculatorEnabled) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColor.bgDeep,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  _RatioStat(
                    label: 'KH-ratio',
                    value: period == null
                        ? '—'
                        : '1:${carbsText(period.carbRatio)}',
                  ),
                  _RatioStat(
                    label: 'Correctie',
                    value: '${mmolText(profile.correctionFactor)}/E',
                  ),
                  _RatioStat(label: 'Doel', value: mmolText(target)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: onLog,
            icon: const Icon(Icons.bolt),
            label: Text(
              profile.bolusCalculatorEnabled
                  ? 'Maaltijd & dosis loggen'
                  : 'Maaltijd loggen',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: onManagePresets,
              icon: const Icon(Icons.bookmarks_outlined, size: 16),
              label: Text(
                presetCount == 0
                    ? 'Voedingspresets aanmaken'
                    : 'Voedingspresets beheren ($presetCount)',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatioStat extends StatelessWidget {
  const _RatioStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        KLabel(label),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppText.bodyStrong.copyWith(
            color: AppColor.ice,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Aftellen tot het eetmoment na een ingestelde wachttijd (spuit-eet-
/// interval). Tikt elke seconde zolang hij in beeld is.
class _WaitTimerCard extends StatefulWidget {
  const _WaitTimerCard({required this.entry, required this.eatAt});

  final FoodLogEntry entry;
  final DateTime eatAt;

  @override
  State<_WaitTimerCard> createState() => _WaitTimerCardState();
}

class _WaitTimerCardState extends State<_WaitTimerCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.eatAt.difference(DateTime.now());
    final done = left.isNegative;
    final mm = left.inMinutes.clamp(0, 999).toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0');
    final carbs = widget.entry.carbs;
    return KCard(
      glow: AppColor.ice,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColor.iceDeep,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.timer_outlined, color: AppColor.iceInk),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KLabel('Eet-timer actief', color: AppColor.ice),
                const SizedBox(height: 2),
                Text(
                  done
                      ? 'Tijd om te eten'
                      : 'Eten om ${DateFormat('HH:mm', 'nl_NL').format(widget.eatAt)}'
                            '${carbs != null ? ' · ${carbsText(carbs)} g' : ''}',
                  style: AppText.body,
                ),
              ],
            ),
          ),
          Text(
            done ? '00:00' : '$mm:$ss',
            style: AppText.metric.copyWith(color: AppColor.ice),
          ),
        ],
      ),
    );
  }
}

// ───────────────────── logboekregel ─────────────────────────────────────────

class _FoodLogRow extends StatelessWidget {
  const _FoodLogRow({required this.entry, required this.onTap});

  final FoodLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final bg = e.mmol;
    final bgColor = bg == null
        ? AppColor.inkFaint
        : glucoseColor(glucoseStateFor(bg));
    return KCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KDot(color: bgColor, size: 6),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm', 'nl_NL').format(e.at),
                style: AppText.overline.copyWith(color: AppColor.ink),
              ),
              if (e.insulinTiming != null) ...[
                const SizedBox(width: 8),
                Text(
                  e.insulinTiming!.label.toLowerCase(),
                  style: AppText.caption,
                ),
              ],
              const Spacer(),
              if (bg != null) KTag('BG ${mmolText(bg)}', color: bgColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            e.description.isEmpty ? '—' : e.description,
            style: AppText.bodyStrong,
          ),
          if (e.carbs != null)
            Text(
              '${carbsText(e.carbs!)} g koolhydraten',
              style: AppText.caption,
            ),
          if (e.insulinUnits != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (e.insulinFoodUnits != null)
                  KTag(
                    'Maaltijd ${carbsText(e.insulinFoodUnits!)} E',
                    color: AppColor.inkMuted,
                    background: AppColor.surfaceRaised,
                  ),
                if (e.insulinCorrectionUnits != null &&
                    e.insulinCorrectionUnits! != 0)
                  KTag(
                    'Corr. ${carbsText(e.insulinCorrectionUnits!)} E',
                    color: AppColor.amber,
                    background: AppColor.surfaceRaised,
                  ),
                KTag(
                  'Totaal ${carbsText(e.insulinUnits!)} E',
                  color: AppColor.coralInk,
                  background: AppColor.coralSoft,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────── toevoegen/aanpassen ──────────────────────────────────

class FoodLogEntryResult {
  final DateTime? at;
  final String? description;
  final Map<String, int>? presetCounts;
  final double? carbs;
  final double? mmol;
  final double? insulinUnits;
  final InsulinTiming? insulinTiming;
  final double? insulinFoodUnits;
  final double? insulinCorrectionUnits;
  final String insulinNote;
  final double? insulinWaitMinutes;
  final bool deleted;

  const FoodLogEntryResult.saved({
    required DateTime this.at,
    required String this.description,
    required Map<String, int> this.presetCounts,
    this.carbs,
    this.mmol,
    this.insulinUnits,
    this.insulinTiming,
    this.insulinFoodUnits,
    this.insulinCorrectionUnits,
    this.insulinNote = '',
    this.insulinWaitMinutes,
  }) : deleted = false;

  const FoodLogEntryResult.deleted()
    : at = null,
      description = null,
      presetCounts = null,
      carbs = null,
      mmol = null,
      insulinUnits = null,
      insulinTiming = null,
      insulinFoodUnits = null,
      insulinCorrectionUnits = null,
      insulinNote = '',
      insulinWaitMinutes = null,
      deleted = true;
}

Future<FoodLogEntryResult?> showFoodLogEntrySheet(
  BuildContext context, {
  required List<FoodPreset> presets,
  required AppProfile profile,
  FoodLogEntry? existing,
  Map<String, int> usage = const {},
  GlucoseReading? latestReading,
  Future<GlucoseReading?>? freshReading,
  ValueListenable<GlucoseSnapshot?>? liveGlucose,
  bool readingFromSensor = true,
}) {
  return showModalBottomSheet<FoodLogEntryResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).padding.bottom +
            20,
      ),
      child: _FoodLogSheet(
        presets: presets,
        profile: profile,
        existing: existing,
        usage: usage,
        latestReading: latestReading,
        freshReading: freshReading,
        liveGlucose: liveGlucose,
        readingFromSensor: readingFromSensor,
      ),
    ),
  );
}

class _FoodLogSheet extends StatefulWidget {
  const _FoodLogSheet({
    required this.presets,
    required this.profile,
    this.existing,
    this.usage = const {},
    this.latestReading,
    this.freshReading,
    this.liveGlucose,
    this.readingFromSensor = true,
  });

  final List<FoodPreset> presets;
  final AppProfile profile;
  final FoodLogEntry? existing;
  final Map<String, int> usage;

  /// Laatst bekende glucosewaarde (sensor of vingerprik) — wordt bij een
  /// nieuw eetmoment voorgevuld als hij recent genoeg is.
  final GlucoseReading? latestReading;

  /// Verse meting die nog binnenkomt — wordt ingevuld zodra hij er is,
  /// tenzij je intussen zelf iets hebt getypt.
  final Future<GlucoseReading?>? freshReading;

  /// De app-brede live glucose: zolang het blad open staat, wordt een
  /// nieuwere meting meteen overgenomen (tenzij je zelf iets typte).
  final ValueListenable<GlucoseSnapshot?>? liveGlucose;
  final bool readingFromSensor;

  @override
  State<_FoodLogSheet> createState() => _FoodLogSheetState();
}

class _FoodLogSheetState extends State<_FoodLogSheet> {
  late DateTime _at;
  final _descController = TextEditingController();
  final _carbsController = TextEditingController();
  final _mmolController = TextEditingController();
  final _insulinController = TextEditingController();
  final _insulinFoodController = TextEditingController();
  final _insulinCorrectionController = TextEditingController();
  final _insulinNoteController = TextEditingController();
  late Map<String, int> _presetCounts;
  InsulinTiming? _insulinTiming;
  double? _insulinWaitMinutes;

  /// Waar zolang de glucose nog de automatisch ingevulde waarde is (niet
  /// zelf aangepast) — voor het "van sensor"-labeltje.
  bool _mmolPrefilled = false;

  /// De meting waarmee het veld is voorgevuld (voor het labeltje).
  GlucoseReading? _prefillReading;

  /// Of de bolus-calculator het insuline-blok vervangt door de drie vakjes
  /// (voeding/correctie/totaal) — alleen als hij aan staat én er minstens
  /// één tijdvak is ingesteld, anders blijft het oude enkele veld bestaan.
  bool get _useBolusCalculator =>
      widget.profile.bolusCalculatorEnabled &&
      widget.profile.bolusPeriods.isNotEmpty;

  double? _parsed(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  /// Insuline wordt altijd in stappen van 0,5 E gespoten — rond handmatig
  /// getypte waardes daarop af.
  double? _parsedInsulin(TextEditingController c) {
    final v = _parsed(c);
    return v == null ? null : roundToHalfUnit(v);
  }

  BolusSuggestion get _suggestion => calculateBolus(
    periods: widget.profile.bolusPeriods,
    carbs: _parsed(_carbsController),
    currentMmol: _parsed(_mmolController),
    correctionFactor: widget.profile.correctionFactor,
    correctionTargetDay: widget.profile.correctionTargetDay,
    correctionTargetNight: widget.profile.correctionTargetNight,
    nightStart: widget.profile.correctionNightStart,
    nightEnd: widget.profile.correctionNightEnd,
    at: _at,
  );

  /// Wat daadwerkelijk bewaard zou worden: je eigen invoer als die er is,
  /// anders het berekende voorstel.
  double? get _effectiveFoodUnits => _useBolusCalculator
      ? (_parsedInsulin(_insulinFoodController) ?? _suggestion.foodDose)
      : null;
  double? get _effectiveCorrectionUnits => _useBolusCalculator
      ? (_parsedInsulin(_insulinCorrectionController) ??
            _suggestion.correctionDose)
      : null;
  double? get _effectiveTotalUnits {
    if (_useBolusCalculator) {
      final food = _effectiveFoodUnits;
      final correction = _effectiveCorrectionUnits;
      if (food == null && correction == null) return null;
      return (food ?? 0) + (correction ?? 0);
    }
    return _parsedInsulin(_insulinController);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _at = e?.at ?? DateTime.now();
    _descController.text = e?.description ?? '';
    _carbsController.text = e?.carbs != null ? carbsText(e!.carbs!) : '';
    _mmolController.text = e?.mmol != null ? mmolText(e!.mmol!) : '';
    final r = widget.latestReading;
    if (e == null &&
        r != null &&
        isPrefillableReading(r, widget.readingFromSensor)) {
      _mmolController.text = mmolText(r.mmol);
      _mmolPrefilled = true;
      _prefillReading = r;
    }
    if (e == null) {
      widget.freshReading?.then(_offerReading);
      widget.liveGlucose?.addListener(_onLiveGlucose);
      // "x min geleden" bijhouden zolang het blad open is.
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _mmolPrefilled) setState(() {});
      });
    }
    _insulinController.text = e?.insulinUnits != null
        ? carbsText(e!.insulinUnits!)
        : '';
    _insulinFoodController.text = e?.insulinFoodUnits != null
        ? carbsText(e!.insulinFoodUnits!)
        : '';
    _insulinCorrectionController.text = e?.insulinCorrectionUnits != null
        ? carbsText(e!.insulinCorrectionUnits!)
        : '';
    _insulinNoteController.text = e?.insulinNote ?? '';
    _insulinTiming = e?.insulinTiming;
    _insulinWaitMinutes = e?.insulinWaitMinutes;
    _presetCounts = e != null ? Map.of(e.presetCounts) : {};
  }

  void _incrementWait() =>
      setState(() => _insulinWaitMinutes = (_insulinWaitMinutes ?? 0) + 2.5);

  void _decrementWait() => setState(() {
    final next = (_insulinWaitMinutes ?? 0) - 2.5;
    _insulinWaitMinutes = next <= 0 ? null : next;
  });

  String _fmtMinutes(double minutes) => minutes % 1 == 0
      ? minutes.toInt().toString()
      : minutes.toStringAsFixed(1).replaceAll('.', ',');

  Timer? _ticker;

  void _onLiveGlucose() => _offerReading(widget.liveGlucose?.value?.reading);

  /// Een (nieuwere) meting invullen — niet als je zelf iets hebt getypt, en
  /// alleen als hij nieuwer is dan wat er al staat.
  void _offerReading(GlucoseReading? reading) {
    if (!mounted || reading == null) return;
    if (!isPrefillableReading(reading, widget.readingFromSensor)) return;
    if (_mmolController.text.trim().isNotEmpty && !_mmolPrefilled) return;
    final current = _prefillReading;
    if (current != null && !reading.at.isAfter(current.at)) return;
    setState(() {
      _mmolController.text = mmolText(reading.mmol);
      _mmolPrefilled = true;
      _prefillReading = reading;
    });
  }

  @override
  void dispose() {
    widget.liveGlucose?.removeListener(_onLiveGlucose);
    _ticker?.cancel();
    _descController.dispose();
    _carbsController.dispose();
    _mmolController.dispose();
    _insulinController.dispose();
    _insulinFoodController.dispose();
    _insulinCorrectionController.dispose();
    _insulinNoteController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) return;
    setState(
      () => _at = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  /// Voegt [item] toe aan een kommagescheiden lijst in [text].
  String _appendListItem(String text, String item) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? item : '$trimmed, $item';
  }

  /// Haalt [item] uit een kommagescheiden lijst in [text], inclusief het
  /// scheidingsteken aan weerszijden, zonder de rest aan te raken.
  String _removeListItem(String text, String item) {
    var result = text.replaceFirst('$item, ', '');
    result = result.replaceFirst(', $item', '');
    result = result.replaceFirst(item, '');
    return result.trim();
  }

  /// Past de omschrijving en koolhydraten incrementeel aan voor één preset —
  /// vervangt alleen het stukje tekst/getal van déze preset (bv. "2
  /// boterhammen" → "3 boterhammen", of +15 g), in plaats van het hele veld
  /// opnieuw op te bouwen. Zo blijft wat je er zelf bij hebt getypt staan.
  void _changePresetCount(FoodPreset preset, int delta) {
    setState(() {
      final oldCount = _presetCounts[preset.singular] ?? 0;
      final newCount = oldCount + delta;
      if (newCount == oldCount) return;

      final oldLabel = oldCount > 0 ? preset.label(oldCount) : null;
      final newLabel = newCount > 0 ? preset.label(newCount) : null;
      var text = _descController.text;
      if (oldLabel != null && text.contains(oldLabel)) {
        text = newLabel != null
            ? text.replaceFirst(oldLabel, newLabel)
            : _removeListItem(text, oldLabel);
      } else if (newLabel != null) {
        text = _appendListItem(text, newLabel);
      }
      _descController.text = text;

      final carbsDelta = preset.carbs * (newCount - oldCount);
      final currentCarbs =
          double.tryParse(_carbsController.text.trim().replaceAll(',', '.')) ??
          0;
      final updatedCarbs = (currentCarbs + carbsDelta).clamp(
        0.0,
        double.infinity,
      );
      _carbsController.text = updatedCarbs > 0 ? carbsText(updatedCarbs) : '';

      if (newCount <= 0) {
        _presetCounts.remove(preset.singular);
      } else {
        _presetCounts[preset.singular] = newCount;
      }
    });
  }

  void _save() {
    final desc = _descController.text.trim();
    if (desc.isEmpty) return;
    final carbs = _parsed(_carbsController);
    final mmol = _parsed(_mmolController);
    final insulinUnits = _effectiveTotalUnits;
    final insulinFoodUnits = _useBolusCalculator ? _effectiveFoodUnits : null;
    final insulinCorrectionUnits = _useBolusCalculator
        ? _effectiveCorrectionUnits
        : null;
    Navigator.pop(
      context,
      FoodLogEntryResult.saved(
        at: _at,
        description: desc,
        presetCounts: _presetCounts,
        carbs: carbs,
        mmol: mmol,
        insulinUnits: insulinUnits,
        insulinTiming: insulinUnits != null ? _insulinTiming : null,
        insulinFoodUnits: insulinUnits != null ? insulinFoodUnits : null,
        insulinCorrectionUnits: insulinUnits != null
            ? insulinCorrectionUnits
            : null,
        insulinNote: insulinUnits != null
            ? _insulinNoteController.text.trim()
            : '',
        insulinWaitMinutes:
            insulinUnits != null && _insulinTiming == InsulinTiming.before
            ? _insulinWaitMinutes
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColor.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            widget.existing == null
                ? 'Eetmoment loggen'
                : 'Eetmoment aanpassen',
            style: AppText.cardTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),
          Text('TIJDSTIP', style: AppText.overline),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 18,
                    color: AppColor.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(dutchDateTime(_at), style: AppText.bodyStrong),
                ],
              ),
            ),
          ),
          if (widget.presets.isNotEmpty) ...[
            const SizedBox(height: 16),
            FoodPresetPicker(
              presets: widget.presets,
              counts: _presetCounts,
              usage: widget.usage,
              onChange: _changePresetCount,
            ),
          ],
          const SizedBox(height: 8),
          Text('WAT HEB JE GEGETEN?', style: AppText.overline),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: TextField(
              controller: _descController,
              maxLines: 3,
              minLines: 2,
              style: AppText.body,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Bijv. Boterham met kaas en een appel',
                hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('KOOLHYDRATEN', style: AppText.overline),
          const SizedBox(height: 8),
          TextField(
            controller: _carbsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.body,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              suffixText: 'g',
              filled: true,
              fillColor: Colors.white.withValues(alpha: .05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('GLUCOSE OP DIT MOMENT (OPTIONEEL)', style: AppText.overline),
          const SizedBox(height: 8),
          TextField(
            controller: _mmolController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.body,
            onChanged: (_) => setState(() => _mmolPrefilled = false),
            decoration: InputDecoration(
              suffixText: 'mmol/L',
              filled: true,
              fillColor: Colors.white.withValues(alpha: .05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_mmolPrefilled && _prefillReading != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  widget.readingFromSensor
                      ? Icons.sensors
                      : Icons.water_drop_outlined,
                  size: 14,
                  color: AppColor.ice,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${widget.readingFromSensor ? 'Van je sensor' : 'Laatste vingerprik'} · '
                    '${relativeDutch(_prefillReading!.at)} — tik om aan te passen',
                    style: AppText.caption.copyWith(color: AppColor.ice),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('INSULINE (OPTIONEEL)', style: AppText.overline),
          const SizedBox(height: 8),
          if (_useBolusCalculator) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _BolusInputBox(
                    label: 'VOEDING',
                    controller: _insulinFoodController,
                    suggestion: _suggestion.foodDose,
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BolusInputBox(
                    label: 'CORRECTIE',
                    controller: _insulinCorrectionController,
                    suggestion: _suggestion.correctionDose,
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BolusTotalBox(units: _effectiveTotalUnits ?? 0),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _insulinController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppText.body,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText: 'E',
                filled: true,
                fillColor: Colors.white.withValues(alpha: .05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          if (_effectiveTotalUnits != null) ...[
            const SizedBox(height: 10),
            SegmentedButton<InsulinTiming>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: InsulinTiming.before,
                  label: Text(
                    InsulinTiming.before.label,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: InsulinTiming.after,
                  label: Text(
                    InsulinTiming.after.label,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: _insulinTiming != null ? {_insulinTiming!} : {},
              emptySelectionAllowed: true,
              onSelectionChanged: (value) => setState(
                () => _insulinTiming = value.isEmpty ? null : value.first,
              ),
            ),
            if (_insulinTiming == InsulinTiming.before) ...[
              const SizedBox(height: 14),
              Text(
                'WACHTTIJD VOOR HET ETEN (OPTIONEEL)',
                style: AppText.overline,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _stepBtn(
                    Icons.remove,
                    (_insulinWaitMinutes ?? 0) > 0 ? _decrementWait : null,
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      _insulinWaitMinutes != null
                          ? '${_fmtMinutes(_insulinWaitMinutes!)} min'
                          : 'Geen',
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(
                        color: AppColor.tealBright,
                      ),
                    ),
                  ),
                  _stepBtn(Icons.add, _incrementWait),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _insulinNoteController,
              maxLines: 2,
              minLines: 1,
              style: AppText.body,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: .05),
                hintText: 'Waarom voor/na het eten? (optioneel)',
                hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              if (widget.existing != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const FoodLogEntryResult.deleted(),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColor.redBright,
                      side: const BorderSide(color: AppColor.red),
                    ),
                    child: const Text('Verwijderen'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _descController.text.trim().isEmpty ? null : _save,
                  child: const Text('Opslaan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 16,
        color: onTap == null ? AppColor.inkGhost : AppColor.tealBright,
      ),
    ),
  );
}

/// Eén van de twee bewerkbare vakjes van de bolus-calculator (voeding of
/// correctie) — toont het live berekende voorstel als placeholder; typ je
/// zelf iets in, dan geldt dat in plaats van het voorstel.
class _BolusInputBox extends StatelessWidget {
  const _BolusInputBox({
    required this.label,
    required this.controller,
    required this.suggestion,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final double? suggestion;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.caption.copyWith(
            fontSize: 10,
            color: AppColor.inkFaint,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppText.body,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            suffixText: 'E',
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: .05),
            hintText: suggestion != null ? carbsText(suggestion!) : null,
            hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Niet-bewerkbaar derde vakje: het totaal van voeding + correctie, in
/// helder groen — de uiteindelijke dosis die je gaat inspuiten.
class _BolusTotalBox extends StatelessWidget {
  const _BolusTotalBox({required this.units});

  final double units;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOTAAL',
          style: AppText.caption.copyWith(
            fontSize: 10,
            color: AppColor.inkFaint,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColor.greenWash,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColor.greenEdge),
          ),
          child: Text(
            '${carbsText(units)} E',
            style: AppText.bodyStrong.copyWith(
              color: AppColor.greenBright,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}
