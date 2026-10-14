// now_screen.dart — tab "Vandaag" (Kinetic: Today / Readiness & Mat Clearance)
//
// Opbouw van boven naar beneden:
//   1. datum, begroeting + oordeel ("Vrij voor de mat")
//   2. matklaar-kaart  — ringmeter, delta, 3-uurscurve, pre-mat check
//   3. trainingsdag    — voorbereiding als tijdlijn + startknoppen
//   4. snelle acties
//   5. laatste sessies

import 'package:flutter/material.dart';
import 'dart:async';

import '../core/formatters.dart';
import '../core/training_streak.dart';
import '../models/app_profile.dart';
import '../models/glucose.dart';
import '../models/glucose_entry.dart';
import '../models/prep_item.dart';
import '../models/training_session.dart';
import '../models/workout_template.dart';
import '../core/competition_plan.dart';
import '../models/agenda.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/food_log_repository.dart';
import '../repositories/glucose_entry_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../repositories/workout_template_repository.dart';
import '../services/agenda_notification_service.dart';
import '../services/glucose_provider.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';
import '../widgets/manual_glucose.dart';
import 'agenda_screen.dart' show CompetitionCountdownCard;
import 'session_detail_screen.dart';
import 'package:intl/intl.dart';

// ───────────────────────────── scherm ───────────────────────────────────────

class NowScreen extends StatefulWidget {
  const NowScreen({
    super.key,
    required this.controller,
    required this.openMatSession,
    required this.openStrengthSession,
    this.onNavigate,
    this.onOpenSettings,
    this.onStartPlanned,
    this.alreadyStartedPlanned = const {},
    this.sessionRunning = false,
  });

  /// Start de sessie van een geplande training (via de "Start nu"-kaart).
  final ValueChanged<PlannedTraining>? onStartPlanned;

  /// Al gestarte geplande trainingen — daarvoor geen kaart meer.
  final Set<String> alreadyStartedPlanned;

  /// Er loopt al een sessie (op de achtergrond) — dan geen startkaart.
  final bool sessionRunning;

  final AppController controller;

  /// Wisselt naar een ander tabblad (snelle acties).
  final ValueChanged<KineticTab>? onNavigate;

  /// Opent de instellingen (bv. als er nog geen glucosebron is).
  final VoidCallback? onOpenSettings;

  /// Start (of heropent) een live sambo-sessie via ShellScreen, dat de
  /// sessie op de achtergrond laat doorlopen als je van tabblad wisselt.
  final Future<bool?> Function({required GlucoseReading? initialReading})
  openMatSession;

  /// Zelfde als [openMatSession], maar voor een live krachttraining —
  /// [planned]/[plannedCircuits] vullen 'm bij het starten voor met de
  /// oefeningen/sets en circuits van een gekozen trainingsschema (leeg voor
  /// een blanco start).
  final Future<bool?> Function({
    required GlucoseReading? initialReading,
    List<ExerciseEntry> planned,
    List<Circuit> plannedCircuits,
  })
  openStrengthSession;

  @override
  State<NowScreen> createState() => _NowScreenState();
}

/// Korte samenvatting van vandaag — combineert trainingen en eetlogboek in
/// één klein kaartje, zodat je niet hoeft te wisselen van tabblad om te zien
/// wat je vandaag al hebt gedaan/gegeten.
class _TodaySummary {
  final int sessionCount;
  final int minutes;
  final double carbs;

  const _TodaySummary({
    required this.sessionCount,
    required this.minutes,
    required this.carbs,
  });

  _TodaySummary copyWith({int? sessionCount, int? minutes, double? carbs}) =>
      _TodaySummary(
        sessionCount: sessionCount ?? this.sessionCount,
        minutes: minutes ?? this.minutes,
        carbs: carbs ?? this.carbs,
      );

  bool get isEmpty => sessionCount == 0 && carbs == 0;
}

class _NowScreenState extends State<NowScreen> {
  late final SessionRepository _sessionRepo;
  late final GlucoseEntryRepository _glucoseEntryRepo;
  late final FoodLogRepository _foodLogRepo;
  late final TechniqueRepository _techniqueRepo;
  int _plannedToday = 0;
  Competition? _nextCompetition;
  List<PlannedTraining> _trainingsToday = const [];
  Timer? _clock;
  Timer? _poller;
  late GlucoseSnapshot _glucose;
  late List<ManualGlucoseEntry> _fingerEntries;
  List<TrainingSession> _recent = [];
  TrainingStreak _streak = const TrainingStreak(
    consecutiveDays: 0,
    daysInLastWeek: 0,
  );
  _TodaySummary _today = const _TodaySummary(
    sessionCount: 0,
    minutes: 0,
    carbs: 0,
  );

  List<PrepItem> get _prep => widget.controller.profile?.prepItems ?? const [];

  bool get _isFinger =>
      widget.controller.profile?.glucoseSource == GlucoseSource.finger;

  @override
  void initState() {
    super.initState();
    // Begin met de laatst bekende waarde (zie AppController.cachedGlucose) in
    // plaats van "laden", zodat de kaart niet even leeg/spinnend flitst elke
    // keer dat dit scherm opnieuw wordt opgebouwd (bv. bij het wisselen van
    // tabblad) — verversen gebeurt hieronder gewoon op de achtergrond.
    _glucose =
        widget.controller.cachedGlucose ?? const GlucoseSnapshot.loading();
    _fingerEntries = widget.controller.cachedFingerEntries;
    _sessionRepo = SessionRepository(widget.controller.client!);
    _glucoseEntryRepo = GlucoseEntryRepository(widget.controller.client!);
    _foodLogRepo = FoodLogRepository(widget.controller.client!);
    _techniqueRepo = TechniqueRepository(widget.controller.client!);
    _refreshCurrentSource();
    _loadRecentSessions();
    _loadTodayFoodLog();
    _loadPlannedTechniqueCount();
    _loadAgenda();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _poller = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCurrentSource(),
    );
    widget.controller.addListener(_refreshCurrentSource);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshCurrentSource);
    _clock?.cancel();
    _poller?.cancel();
    super.dispose();
  }

  /// Ververst op basis van de op dit moment gekozen bron — zodat schakelen
  /// tussen CGM en vingerprik in de instellingen hier meteen doorwerkt.
  Future<void> _refreshCurrentSource() async {
    if (_isFinger) {
      await _loadFingerEntries();
    } else {
      await _refreshGlucose();
    }
  }

  Future<void> _refreshGlucose() async {
    final profile = widget.controller.profile;
    if (profile == null) return;
    final provider = await resolveGlucoseProvider(profile);
    if (provider == null) {
      const unconfigured = GlucoseSnapshot.unconfigured();
      widget.controller.cachedGlucose = unconfigured;
      if (mounted) setState(() => _glucose = unconfigured);
      return;
    }
    if (mounted) {
      setState(
        () => _glucose = _glucose.copyWith(
          isLoading: true,
          message: _glucose.message,
        ),
      );
    }
    final next = await provider.fetch();
    widget.controller.cachedGlucose = next;
    if (mounted) setState(() => _glucose = next);
  }

  Future<void> _loadFingerEntries() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final entries = await _glucoseEntryRepo.recentForUser(userId);
      widget.controller.cachedFingerEntries = entries;
      widget.controller.cachedGlucose = _snapshotFromFinger(entries);
      if (mounted) {
        setState(() {
          _fingerEntries = entries;
          _glucose = _snapshotFromFinger(entries);
        });
      }
    } catch (_) {
      // Lijst blijft leeg/oud; pull-to-refresh laat het opnieuw proberen.
    }
  }

  GlucoseSnapshot _snapshotFromFinger(List<ManualGlucoseEntry> entries) {
    if (entries.isEmpty) {
      return const GlucoseSnapshot(
        reading: null,
        history: [],
        message: 'Voer je eerste vingerprik in.',
      );
    }
    final latest = entries.first;
    final trend = entries.length > 1
        ? trendFromDelta(latest.mmol - entries[1].mmol)
        : Trend.flat;
    return GlucoseSnapshot(
      reading: GlucoseReading(latest.mmol, trend, latest.at),
      history: entries.reversed.map((e) => GlucosePoint(e.at, e.mmol)).toList(),
    );
  }

  Future<void> _recordManualReading() async {
    final value = await showManualGlucoseDialog(context);
    if (value == null || !mounted) return;
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      await _glucoseEntryRepo.create(userId, value, DateTime.now());
      await _loadFingerEntries();
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

  Future<void> _editFingerEntry(ManualGlucoseEntry entry) async {
    final result = await showManualGlucoseEditDialog(context, entry);
    if (result == null || !mounted) return;
    try {
      if (result.deleted) {
        await _glucoseEntryRepo.delete(entry.id);
      } else if (result.mmol != null) {
        await _glucoseEntryRepo.update(entry.id, result.mmol!);
      }
      await _loadFingerEntries();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wijzigen is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _persistPrep(List<PrepItem> next) async {
    final profile = widget.controller.profile;
    if (profile == null) return;
    next.sort((a, b) => a.time.compareTo(b.time));
    await widget.controller.saveProfile(profile.copyWith(prepItems: next));
    if (mounted) setState(() {});
  }

  void _togglePrep(int index) {
    final next = List<PrepItem>.of(_prep);
    next[index] = next[index].copyWith(done: !next[index].done);
    _persistPrep(next);
  }

  Future<void> _openPrepSheet({int? index}) async {
    final existing = index != null ? _prep[index] : null;
    final result = await showPrepItemSheet(context, existing: existing);
    if (result == null || !mounted) return;
    final next = List<PrepItem>.of(_prep);
    if (result.deleted) {
      if (index != null) next.removeAt(index);
    } else if (result.item != null) {
      if (index != null) {
        next[index] = result.item!;
      } else {
        next.add(result.item!);
      }
    }
    await _persistPrep(next);
  }

  Future<void> _loadRecentSessions() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final sessions = await _sessionRepo.listForUser(userId);
      if (!mounted) return;
      final todaySessions = sessions.where((s) => _isToday(s.startedAt));
      setState(() {
        _recent = sessions.take(2).toList();
        _today = _today.copyWith(
          sessionCount: todaySessions.length,
          minutes: todaySessions.fold<int>(0, (n, s) => n + s.durationMinutes),
        );
        _streak = TrainingStreak.compute(
          sessions.map((s) => s.startedAt).toList(),
        );
      });
    } catch (_) {
      // Laatste sessies blijven leeg; de "Training"-tab kan opnieuw proberen.
    }
  }

  Future<void> _loadTodayFoodLog() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final entries = await _foodLogRepo.listForUser(userId);
      if (!mounted) return;
      final carbs = entries
          .where((e) => _isToday(e.at))
          .fold<double>(0, (n, e) => n + (e.carbs ?? 0));
      setState(() => _today = _today.copyWith(carbs: carbs));
    } catch (_) {
      // Dagsamenvatting blijft zonder koolhydraten; niet blokkerend.
    }
  }

  bool _isToday(DateTime at) {
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  /// Volgende wedstrijd + de trainingen van vandaag, en meteen de
  /// agenda-meldingen bijwerken (zodat die ook kloppen als je de Agenda-tab
  /// niet opent).
  Future<void> _loadAgenda() async {
    final userId = widget.controller.user?.id;
    final client = widget.controller.client;
    if (userId == null || client == null) return;
    try {
      final repo = AgendaRepository(client);
      final results = await Future.wait([
        repo.trainings(userId),
        repo.competitions(userId),
      ]);
      final trainings = results[0] as List<PlannedTraining>;
      final competitions = results[1] as List<Competition>;
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _nextCompetition = nextCompetition(competitions, now);
          _trainingsToday = trainings
              .where((t) => daysUntil(t.startsAt, now) == 0)
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        });
      }
      await AgendaNotificationService.instance.sync(
        trainings: trainings,
        competitions: competitions,
      );
    } catch (_) {
      // Agenda is aanvullend; Vandaag werkt ook zonder.
    }
  }

  Future<void> _loadPlannedTechniqueCount() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final techniques = await _techniqueRepo.listForUser(userId);
      if (!mounted) return;
      setState(() {
        _plannedToday = techniques
            .where((t) => t.plannedFor != null && _isToday(t.plannedFor!))
            .length;
      });
    } catch (_) {
      // Planningteller blijft op de laatst bekende waarde; niet blokkerend.
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshCurrentSource(),
      _loadRecentSessions(),
      _loadTodayFoodLog(),
      _loadPlannedTechniqueCount(),
      _loadAgenda(),
    ]);
  }

  /// Vraagt eerst welk trainingsschema (of blanco) als startpunt moet
  /// dienen, tenzij er nog geen schema's zijn opgeslagen — dan meteen
  /// blanco starten, zonder extra stap.
  Future<void> _startStrength() async {
    final userId = widget.controller.user?.id;
    final client = widget.controller.client;
    var templates = const <WorkoutTemplate>[];
    if (userId != null && client != null) {
      try {
        templates = await WorkoutTemplateRepository(client).listForUser(userId);
      } catch (_) {
        // Geen schema's beschikbaar; gewoon blanco starten.
      }
    }
    var planned = const <ExerciseEntry>[];
    var plannedCircuits = const <Circuit>[];
    if (templates.isNotEmpty) {
      if (!mounted) return;
      final chosen = await _pickStrengthTemplate(context, templates);
      if (chosen == null) return; // geannuleerd
      planned = chosen.exercises;
      plannedCircuits = chosen.circuits;
    }
    if (!mounted) return;
    final saved = await widget.openStrengthSession(
      initialReading: _glucose.reading,
      planned: planned,
      plannedCircuits: plannedCircuits,
    );
    if (saved == true) _loadRecentSessions();
  }

  Future<WorkoutTemplate?> _pickStrengthTemplate(
    BuildContext context,
    List<WorkoutTemplate> templates,
  ) {
    return showModalBottomSheet<WorkoutTemplate>(
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
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
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
              'Krachttraining starten',
              style: AppText.cardTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () =>
                  Navigator.pop(ctx, const WorkoutTemplate(id: '', name: '')),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColor.lineStrong),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 18, color: AppColor.inkMuted),
                    const SizedBox(width: 10),
                    Text(
                      'Blanco starten',
                      style: AppText.bodyStrong.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            for (final t in templates)
              InkWell(
                onTap: () => Navigator.pop(ctx, t),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                              t.name,
                              style: AppText.bodyStrong.copyWith(fontSize: 13),
                            ),
                            Text(
                              '${t.exercises.length} oefening${t.exercises.length == 1 ? '' : 'en'}',
                              style: AppText.caption.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColor.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Eén oordeel voor kop, badge en kaart — volgt dezelfde grenzen als het
  /// alarm (zie [AppController.alarmDecision]).
  _Verdict _verdict() {
    final reading = _glucose.reading;
    final profile = widget.controller.profile;
    if (reading == null) {
      return _Verdict(
        color: AppColor.inkFaint,
        badge: _glucose.isLoading ? 'Laden' : 'Geen data',
        headline: _glucose.message ?? 'Geen glucosebron actief.',
        icon: Icons.sensors_off_outlined,
      );
    }
    // Een oude meting mag nooit "vrij voor de mat" tonen — die waarde kan
    // inmiddels van alles zijn. Alleen relevant bij CGM: bij vingerprik is
    // "oud" normaal, want je meet niet elke 15 minuten.
    if (!_isFinger && _glucose.isStale) {
      return _Verdict(
        color: AppColor.inkFaint,
        badge: 'Verouderd',
        headline:
            'Geen actuele waarde — laatste om ${DateFormat('HH:mm', 'nl_NL').format(reading.at)}.',
        icon: Icons.history,
      );
    }
    final lower = profile?.trainingLimit ?? 5.0;
    final lowEnabled = !_isFinger && profile?.alarmMode != AlarmMode.off;
    final hyperEnabled = profile?.hyperAlarmEnabled ?? true;
    final upper = profile?.hyperLimit ?? 10.0;
    if (lowEnabled && reading.mmol < lower) {
      return const _Verdict(
        color: AppColor.red,
        badge: 'Te laag',
        headline: 'Niet de mat op — behandel eerst.',
        icon: Icons.gpp_bad_outlined,
      );
    }
    if (hyperEnabled && reading.mmol > upper) {
      return const _Verdict(
        color: AppColor.amber,
        badge: 'Te hoog',
        headline: 'Te hoog — wacht met starten.',
        icon: Icons.gpp_maybe_outlined,
      );
    }
    return _Verdict(
      color: AppColor.ice,
      badge: 'In bereik',
      headline:
          'Vrij voor de mat. Glucose ${trendLabel[reading.trend]!.toLowerCase()}.',
      icon: Icons.verified_user_outlined,
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour < 6) return 'Goedenacht';
    if (now.hour < 12) return 'Goedemorgen';
    if (now.hour < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  @override
  Widget build(BuildContext context) {
    final reading = _glucose.reading;
    final verdict = _verdict();
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          4,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          // ── begroeting ──
          Row(
            children: [
              Expanded(
                child: KLabel(
                  DateFormat('EEEE · HH:mm', 'nl_NL').format(now),
                  color: AppColor.inkFaint,
                ),
              ),
              KPill(
                text: _isFinger ? 'Vingerprik' : 'Sensor live',
                color: _isFinger || reading == null || _glucose.isStale
                    ? AppColor.inkMuted
                    : AppColor.ice,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_greeting(now)}, ${widget.controller.displayName.split(' ').first}.',
            style: AppText.display,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(verdict.icon, size: 18, color: verdict.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  verdict.headline,
                  style: AppText.body.copyWith(color: AppColor.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),

          // ── geplande training: nu starten ──
          if (!widget.sessionRunning && widget.onStartPlanned != null)
            if (plannedToStartNow(
                  _trainingsToday,
                  now,
                  alreadyStarted: widget.alreadyStartedPlanned,
                )
                case final planned?) ...[
              _PlannedStartCard(
                training: planned,
                onStart: () => widget.onStartPlanned!(planned),
              ),
              const SizedBox(height: AppSpace.lg),
            ],

          // ── wedstrijd-aftelling ──
          if (_nextCompetition != null) ...[
            CompetitionCountdownCard(
              competition: _nextCompetition!,
              compact: true,
              currentWeightKg: widget.controller.profile?.weightKg,
              onTap: () => widget.onNavigate?.call(KineticTab.agenda),
            ),
            const SizedBox(height: AppSpace.lg),
          ],

          // ── glucose & matklaar ──
          _ReadinessCard(
            snapshot: _glucose,
            verdict: verdict,
            profile: widget.controller.profile,
            isFinger: _isFinger,
            fingerEntries: _fingerEntries,
            onAddFinger: _recordManualReading,
            onTapFinger: _editFingerEntry,
            onOpenSettings: widget.onOpenSettings,
            alarmLine: _AlarmStatusLine(controller: widget.controller),
          ),
          const SizedBox(height: AppSpace.lg),

          // ── trainingsdag ──
          _TrainingDayCard(
            prep: _prep,
            plannedToday: _plannedToday,
            trainingsToday: _trainingsToday,
            onOpenAgenda: () => widget.onNavigate?.call(KineticTab.agenda),
            summary: _today,
            streakLabel: _streak.label,
            onToggle: _togglePrep,
            onEdit: (i) => _openPrepSheet(index: i),
            onAddPrep: () => _openPrepSheet(),
            onStart: () async {
              final saved = await widget.openMatSession(initialReading: reading);
              if (saved == true) _loadRecentSessions();
            },
            onStartStrength: _startStrength,
          ),
          const SizedBox(height: AppSpace.lg),

          // ── snelle acties ──
          const KSectionTitle('Snelle acties', trailing: 'Bio-adjust'),
          if (_isFinger) ...[
            KActionRow(
              icon: Icons.water_drop_outlined,
              iconColor: AppColor.ice,
              title: 'Vingerprik invoeren',
              subtitle: 'Handmatige meting vastleggen',
              trailingIcon: Icons.add,
              onTap: _recordManualReading,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          KActionRow(
            icon: Icons.restaurant_outlined,
            title: 'Maaltijd & insuline',
            subtitle: 'Koolhydraten tellen, bolus berekenen',
            onTap: () => widget.onNavigate?.call(KineticTab.food),
          ),
          const SizedBox(height: AppSpace.md),
          KActionRow(
            icon: Icons.sports_martial_arts_outlined,
            title: 'Technieken',
            subtitle: 'Worpen, klemmen & leerdoelen',
            onTap: () => widget.onNavigate?.call(KineticTab.train),
          ),
          const SizedBox(height: AppSpace.lg),

          // ── laatste sessies ──
          const KSectionTitle('Laatste sessies'),
          if (_recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Nog geen trainingen opgeslagen.',
                style: AppText.caption,
              ),
            ),
          for (final s in _recent) ...[
            _SessionRow(
              session: s,
              onTap: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(
                      session: s,
                      repository: _sessionRepo,
                      controller: widget.controller,
                    ),
                  ),
                );
                if (changed == true) _loadRecentSessions();
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}

/// Grote kaart "Geplande training · Start nu" rond het geplande begin.
class _PlannedStartCard extends StatelessWidget {
  const _PlannedStartCard({required this.training, required this.onStart});

  final PlannedTraining training;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = training;
    final minutes = t.startsAt.difference(DateTime.now()).inMinutes;
    final when = minutes > 0
        ? 'begint over $minutes min'
        : (minutes == 0 ? 'begint nu' : 'begon ${-minutes} min geleden');
    return KCard(
      glow: AppColor.coral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, size: 20, color: AppColor.coral),
              const SizedBox(width: 8),
              const Expanded(
                child: KLabel('Geplande training', color: AppColor.coralSoft),
              ),
              KTag(t.kind.label, color: AppColor.ice),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(t.displayTitle, style: AppText.title),
          Text(
            [
              '${DateFormat('HH:mm').format(t.startsAt)} · $when',
              if (t.location.isNotEmpty) t.location,
            ].join(' · '),
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start nu'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ],
      ),
    );
  }
}

class _Verdict {
  final Color color;
  final String badge;
  final String headline;
  final IconData icon;
  const _Verdict({
    required this.color,
    required this.badge,
    required this.headline,
    required this.icon,
  });
}

// ───────────────────────── matklaar-kaart ───────────────────────────────────

/// Ringmeter met de actuele waarde, delta, 3-uurscurve en een uitklapbare
/// pre-mat check. Kleur volgt [glucoseStateFor], dus dit widget kiest zelf
/// niets.
class _ReadinessCard extends StatefulWidget {
  const _ReadinessCard({
    required this.snapshot,
    required this.verdict,
    required this.profile,
    required this.isFinger,
    required this.fingerEntries,
    required this.onAddFinger,
    required this.onTapFinger,
    required this.alarmLine,
    this.onOpenSettings,
  });

  final GlucoseSnapshot snapshot;
  final _Verdict verdict;
  final AppProfile? profile;
  final bool isFinger;
  final List<ManualGlucoseEntry> fingerEntries;
  final VoidCallback onAddFinger;
  final ValueChanged<ManualGlucoseEntry> onTapFinger;
  final VoidCallback? onOpenSettings;
  final Widget alarmLine;

  @override
  State<_ReadinessCard> createState() => _ReadinessCardState();
}

class _ReadinessCardState extends State<_ReadinessCard> {
  bool _open = false;

  /// Verschil met de meting van ~30 minuten geleden (CGM), of met de vorige
  /// vingerprik.
  double? _delta() {
    final reading = widget.snapshot.reading;
    if (reading == null) return null;
    if (widget.isFinger) {
      final e = widget.fingerEntries;
      return e.length > 1 ? e[0].mmol - e[1].mmol : null;
    }
    final target = reading.at.subtract(const Duration(minutes: 30));
    GlucosePoint? best;
    for (final p in widget.snapshot.history) {
      if (p.at.isAfter(reading.at.subtract(const Duration(minutes: 20)))) {
        continue;
      }
      if (best == null ||
          (p.at.difference(target)).abs() < (best.at.difference(target)).abs()) {
        best = p;
      }
    }
    if (best == null ||
        best.at.difference(target).abs() > const Duration(minutes: 15)) {
      return null;
    }
    return reading.mmol - best.mmol;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final reading = snapshot.reading;
    final stale = !widget.isFinger && snapshot.isStale;
    final color = reading == null || stale
        ? AppColor.inkFaint
        : glucoseColor(glucoseStateFor(reading.mmol));
    final lower = widget.profile?.trainingLimit ?? 5.0;
    final delta = _delta();

    return KCard(
      padding: const EdgeInsets.all(20),
      glow: widget.verdict.color == AppColor.red ? AppColor.red : null,
      child: Column(
        children: [
          KCardHeader(
            icon: Icons.monitor_heart_outlined,
            label: 'Matklaar & glucose',
            iconColor: AppColor.ice,
            trailing: KPill(
              text: widget.verdict.badge,
              color: widget.verdict.color,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          KRing(
            value: reading == null ? 0 : glucoseFraction(reading.mmol),
            inner: glucoseFraction(lower),
            color: color,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reading != null && !stale)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trendArrow[reading.trend], size: 18, color: color),
                      const SizedBox(width: 4),
                      KLabel(trendLabel[reading.trend]!, color: color),
                    ],
                  )
                else if (snapshot.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  KLabel(stale ? 'Verouderd' : 'Geen data'),
                const SizedBox(height: 2),
                Text(
                  reading == null ? '—' : mmolText(reading.mmol),
                  style: AppText.reading.copyWith(
                    color: stale ? AppColor.inkFaint : AppColor.ink,
                  ),
                ),
                const SizedBox(height: 2),
                const KLabel('mmol / L'),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Stat(
                  label: widget.isFinger ? 'Delta (vorige)' : 'Delta (30m)',
                  value: delta == null
                      ? '—'
                      : '${delta >= 0 ? '+' : ''}${mmolText(delta)}',
                ),
                const VerticalDivider(
                  width: 32,
                  color: AppColor.surfaceHighest,
                  indent: 4,
                  endIndent: 4,
                ),
                _Stat(
                  label: 'Laatste meting',
                  value: reading == null ? '—' : relativeDutch(reading.at),
                  color: AppColor.ice,
                ),
              ],
            ),
          ),
          if (reading == null && !snapshot.isLoading && !widget.isFinger) ...[
            const SizedBox(height: AppSpace.md),
            OutlinedButton(
              onPressed: widget.onOpenSettings,
              child: const Text('Glucosebron instellen'),
            ),
          ],
          if (!widget.isFinger && reading != null) ...[
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              height: 64,
              child: CustomPaint(
                painter: _CurvePainter(
                  snapshot.history.isEmpty
                      ? [
                          GlucosePoint(
                            reading.at.subtract(const Duration(minutes: 1)),
                            reading.mmol,
                          ),
                          GlucosePoint(reading.at, reading.mmol),
                        ]
                      : snapshot.history,
                  color,
                  stale ? AppColor.inkFaint : AppColor.ice,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in [
                  reading.at.subtract(const Duration(hours: 3)),
                  reading.at.subtract(const Duration(minutes: 90)),
                ])
                  Text(
                    DateFormat('HH:mm', 'nl_NL').format(t),
                    style: AppText.caption.copyWith(fontSize: 10),
                  ),
                Text('nu', style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ],
          if (widget.isFinger) ...[
            const SizedBox(height: AppSpace.lg),
            if (widget.fingerEntries.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in widget.fingerEntries.take(4))
                    ActionChip(
                      onPressed: () => widget.onTapFinger(e),
                      label: Text(
                        '${DateFormat('HH:mm', 'nl_NL').format(e.at)} · ${mmolText(e.mmol)}',
                        style: AppText.caption.copyWith(color: AppColor.ink),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              onPressed: widget.onAddFinger,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Vingerprik invoeren'),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Material(
            color: AppColor.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    KDot(color: widget.verdict.color, size: 10),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: KLabel('Pre-mat check', color: AppColor.ink),
                    ),
                    KTag(widget.verdict.badge, color: widget.verdict.color),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more,
                        size: 20,
                        color: AppColor.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open ? _drawer() : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _drawer() {
    final p = widget.profile;
    final alarm = switch (p?.alarmMode) {
      AlarmMode.sound => 'Geluid',
      AlarmMode.off => 'Uit',
      null => '—',
      _ => 'Stil',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KMetricTile(
                  label: 'Ondergrens',
                  value: mmolText(p?.trainingLimit ?? 5.0),
                  caption: 'training',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KMetricTile(
                  label: 'Bovengrens',
                  value: mmolText(p?.hyperLimit ?? 10.0),
                  caption: (p?.hyperAlarmEnabled ?? true) ? 'actief' : 'uit',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KMetricTile(
                  label: 'Alarm',
                  value: widget.isFinger ? '—' : alarm,
                  caption: widget.isFinger ? 'vingerprik' : 'hypo',
                  captionColor: AppColor.inkFaint,
                ),
              ),
            ],
          ),
          widget.alarmLine,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      KLabel(label),
      const SizedBox(height: 2),
      Text(
        value,
        style: AppText.bodyStrong.copyWith(color: color ?? AppColor.ink),
      ),
    ],
  );
}

/// Curve met de in-bereik-band als achtergrond. Vaste y-as van 2-14 mmol/L
/// zodat de vorm tussen sessies vergelijkbaar blijft. Punten staan op hun
/// echte tijdstip in plaats van gelijk verdeeld, zodat een ontbrekende
/// meting als gat zichtbaar is in plaats van de rest te verschuiven.
class _CurvePainter extends CustomPainter {
  final List<GlucosePoint> points;
  final Color line;
  final Color dot;
  _CurvePainter(this.points, this.line, this.dot);

  static const _min = 2.0, _max = 14.0;
  static const _lo = 3.9, _hi = 10.0;
  static const _minGap = Duration(minutes: 20);

  double _y(double v, double h) =>
      h - ((v.clamp(_min, _max) - _min) / (_max - _min)) * h;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // band: in bereik
    canvas.drawRect(
      Rect.fromLTRB(0, _y(_hi, size.height), size.width, _y(_lo, size.height)),
      Paint()..color = line.withValues(alpha: .12),
    );

    final span = points.last.at.difference(points.first.at).inMilliseconds;
    double x(int i) => span > 0
        ? size.width *
              (points[i].at.difference(points.first.at).inMilliseconds / span)
        : size.width * i / (points.length - 1);

    // Gat = duidelijk langere stilte dan de gebruikelijke tussenpoos —
    // gebaseerd op de mediaan zodat het bij zowel CGM (~5 min) als
    // onregelmatige vingerprikken werkt, met een ondergrens van 20 minuten.
    final deltas = [
      for (var i = 1; i < points.length; i++)
        points[i].at.difference(points[i - 1].at),
    ]..sort((a, b) => a.compareTo(b));
    final median = deltas[deltas.length ~/ 2];
    final gapThreshold = median * 2.5 > _minGap ? median * 2.5 : _minGap;

    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path? path;
    Offset? prev;
    for (var i = 0; i < points.length; i++) {
      final p = Offset(x(i), _y(points[i].mmol, size.height));
      final gap =
          i > 0 && points[i].at.difference(points[i - 1].at) > gapThreshold;
      if (path == null || gap) {
        if (path != null) canvas.drawPath(path, paint);
        path = Path()..moveTo(p.dx, p.dy);
      } else if (prev != null) {
        final mid = Offset((prev.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        if (i == points.length - 1) path.lineTo(p.dx, p.dy);
      }
      prev = p;
    }
    if (path != null) canvas.drawPath(path, paint);

    canvas.drawCircle(
      Offset(x(points.length - 1), _y(points.last.mmol, size.height)),
      4.5,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.line != line;
}

// ───────────────────────── alarmstatus ──────────────────────────────────────

/// Rustige regel die altijd laat zien of het alarm actief is — zodat je dat
/// nooit hoeft te gokken. Toont ook een aftellertje na "Ingenomen" tot de
/// volgende hermeet-herinnering.
class _AlarmStatusLine extends StatelessWidget {
  const _AlarmStatusLine({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: controller.alarmGuard.nextRemeasureAt,
      builder: (context, remeasureAt, _) {
        if (remeasureAt != null) {
          final left = remeasureAt.difference(DateTime.now());
          final minutes = left.isNegative ? 0 : (left.inSeconds / 60).ceil();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Hermeting over $minutes min',
              style: AppText.caption.copyWith(color: AppColor.tealBright),
            ),
          );
        }
        final decision = controller.alarmDecisionOutsideSession();
        if (decision.enabled) return const SizedBox.shrink();
        final isFinger =
            controller.profile?.glucoseSource == GlucoseSource.finger;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isFinger ? 'Geen alarm — vingerprik' : 'Alarm uit',
            style: AppText.caption.copyWith(color: AppColor.inkFaint),
          ),
        );
      },
    );
  }
}

// ───────────────────────── kaart "Trainingsdag" ─────────────────────────────

/// Voorbereiding als tijdlijn (het eerstvolgende open punt in koraal), de
/// dagsamenvatting en de startknoppen voor sambo en kracht.
class _TrainingDayCard extends StatelessWidget {
  final List<PrepItem> prep;
  final int plannedToday;
  final List<PlannedTraining> trainingsToday;
  final VoidCallback onOpenAgenda;
  final _TodaySummary summary;
  final String? streakLabel;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onEdit;
  final VoidCallback onAddPrep;
  final VoidCallback onStart;
  final VoidCallback onStartStrength;
  const _TrainingDayCard({
    required this.prep,
    required this.plannedToday,
    required this.trainingsToday,
    required this.onOpenAgenda,
    required this.summary,
    required this.streakLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onAddPrep,
    required this.onStart,
    required this.onStartStrength,
  });

  @override
  Widget build(BuildContext context) {
    final nextIndex = prep.indexWhere((p) => !p.done);
    final open = prep.where((p) => !p.done).length;
    final facts = <(IconData, String)>[
      if (summary.sessionCount > 0)
        (
          Icons.timer_outlined,
          '${summary.sessionCount} training${summary.sessionCount == 1 ? '' : 'en'} · ${summary.minutes} min',
        ),
      if (summary.carbs > 0)
        (Icons.restaurant_outlined, '${carbsText(summary.carbs)}g koolhydraten'),
      if (plannedToday > 0)
        (
          Icons.event_outlined,
          '$plannedToday technie${plannedToday == 1 ? 'k' : 'ken'} op de planning',
        ),
      if (streakLabel != null)
        (Icons.local_fire_department_outlined, streakLabel!),
    ];

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KCardHeader(
            large: true,
            icon: Icons.sports_mma_outlined,
            iconColor: AppColor.coral,
            label: 'Trainingsdag',
            trailing: KLabel(
              prep.isEmpty ? 'Geen voorbereiding' : '$open open',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (final t in trainingsToday) ...[
            Material(
              color: AppColor.coralWash,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: onOpenAgenda,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 18, color: AppColor.coralSoft),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat('HH:mm').format(t.startsAt),
                        style: AppText.bodyStrong,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          [t.displayTitle, if (t.location.isNotEmpty) t.location]
                              .join(' · '),
                          style: AppText.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (t.remindMinutesBefore != null)
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 16,
                          color: AppColor.ice,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          for (var i = 0; i < prep.length; i++) ...[
            _PrepBlock(
              item: prep[i],
              isNext: i == nextIndex,
              onToggle: () => onToggle(i),
              onEdit: () => onEdit(i),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          TextButton.icon(
            onPressed: onAddPrep,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Voorbereiding toevoegen'),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            for (final (icon, text) in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: AppColor.inkFaint),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, style: AppText.caption)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start sambo'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onStartStrength,
                  icon: const Icon(Icons.fitness_center, size: 18),
                  label: const Text('Kracht'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrepBlock extends StatelessWidget {
  const _PrepBlock({
    required this.item,
    required this.isNext,
    required this.onToggle,
    required this.onEdit,
  });

  final PrepItem item;
  final bool isNext;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bar = item.done
        ? AppColor.surfaceHighest
        : (isNext ? AppColor.coral : AppColor.slateDim);
    return Material(
      color: AppColor.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: bar),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isNext)
                            const KTag(
                              'Volgende',
                              color: AppColor.coralSoft,
                              background: AppColor.coralWash,
                            )
                          else if (item.done)
                            const KTag('Gedaan', color: AppColor.inkFaint),
                          const Spacer(),
                          Text(
                            item.time,
                            style: AppText.bodyStrong.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        style: AppText.cardTitle.copyWith(
                          color: item.done ? AppColor.inkFaint : AppColor.ink,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: item.done ? 'Markeer als open' : 'Markeer als gedaan',
                onPressed: onToggle,
                icon: Icon(
                  item.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: item.done ? AppColor.ice : AppColor.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── voorbereiding toevoegen/aanpassen ────────────────


/// Resultaat van [showPrepItemSheet]: een nieuw/aangepast item, of een
/// signaal dat het verwijderd moet worden.
class PrepItemResult {
  final PrepItem? item;
  final bool deleted;
  const PrepItemResult.saved(this.item) : deleted = false;
  const PrepItemResult.deleted() : item = null, deleted = true;
}

Future<PrepItemResult?> showPrepItemSheet(
  BuildContext context, {
  PrepItem? existing,
}) {
  return showModalBottomSheet<PrepItemResult>(
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
      child: _PrepItemSheet(existing: existing),
    ),
  );
}

class _PrepItemSheet extends StatefulWidget {
  final PrepItem? existing;
  const _PrepItemSheet({this.existing});

  @override
  State<_PrepItemSheet> createState() => _PrepItemSheetState();
}

class _PrepItemSheetState extends State<_PrepItemSheet> {
  late TimeOfDay _time;
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e != null ? _parseTime(e.time) : TimeOfDay.now();
    _label = TextEditingController(text: e?.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return TimeOfDay.now();
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
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
                ? 'Voorbereiding toevoegen'
                : 'Voorbereiding aanpassen',
            style: AppText.cardTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 18),
          Text('TIJD', style: AppText.overline),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickTime,
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
                  Text(_timeText, style: AppText.bodyStrong),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('ACTIE / VOORBEREIDING', style: AppText.overline),
          const SizedBox(height: 8),
          TextField(
            controller: _label,
            autofocus: widget.existing == null,
            style: AppText.body,
            decoration: InputDecoration(
              hintText: 'Bijv. 30 g koolhydraten',
              filled: true,
              fillColor: Colors.white.withValues(alpha: .05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (widget.existing != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, const PrepItemResult.deleted()),
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
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _label,
                  builder: (context, value, _) => FilledButton(
                    onPressed: value.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            PrepItemResult.saved(
                              PrepItem(
                                time: _timeText,
                                label: value.text.trim(),
                                done: widget.existing?.done ?? false,
                              ),
                            ),
                          ),
                    child: const Text('Opslaan'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── sessie-rij ───────────────────────────────────────

class _SessionRow extends StatelessWidget {
  final TrainingSession session;
  final VoidCallback onTap;
  const _SessionRow({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hadDip = session.hadDip;
    final isSambo = session.kind == SessionKind.sambo;
    final count = isSambo
        ? '${session.blocks.length} technieken'
        : '${session.exercises.length} oefeningen';
    final metric = hadDip
        ? mmolText(session.lowestMmol ?? 0)
        : (session.firstMmol != null && session.lastMmol != null
              ? mmolText(session.lastMmol! - session.firstMmol!)
              : '—');
    return Material(
      color: AppColor.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: isSambo ? AppColor.coral : AppColor.slateDim,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KTag(
                              isSambo ? 'Sambo' : 'Kracht',
                              color: isSambo
                                  ? AppColor.coralSoft
                                  : AppColor.slate,
                              background: isSambo
                                  ? AppColor.coralWash
                                  : AppColor.surfaceHigh,
                            ),
                            const SizedBox(height: 6),
                            Text(session.title, style: AppText.cardTitle),
                            Text(
                              '${dutchShortDate(session.startedAt)} · ${session.durationMinutes} min · $count',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            metric,
                            style: AppText.cardTitle.copyWith(
                              color: hadDip ? AppColor.amber : AppColor.ice,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          KLabel(hadDip ? 'laagste' : 'verschil'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
