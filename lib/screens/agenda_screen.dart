// agenda_screen.dart — tab "Agenda": de eerstvolgende wedstrijd met
// aftelling, fase en disciplineregel, geplande trainingen (met melding) en
// alle wedstrijden inclusief uitslagen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/competition_plan.dart';
import '../models/agenda.dart';
import '../core/session_times.dart';
import '../repositories/technique_repository.dart';
import '../models/technique.dart';
import '../repositories/agenda_repository.dart';
import '../services/agenda_notification_service.dart';
import '../services/technique_reminder_input.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';

/// Wat de agenda meteen opent (vanuit een snelle actie op het dashboard).
enum AgendaStartAction { planTraining, addCompetition }

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, required this.controller, this.startAction});

  final AppController controller;
  final AgendaStartAction? startAction;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late final AgendaRepository _repo;
  List<PlannedTraining> _trainings = const [];
  List<Competition> _competitions = const [];
  bool _loading = true;
  bool _showPast = false;

  @override
  void initState() {
    super.initState();
    _repo = AgendaRepository(widget.controller.client!);
    _load();
    final action = widget.startAction;
    if (action != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case AgendaStartAction.planTraining:
            _editTraining();
          case AgendaStartAction.addCompetition:
            _editCompetition();
        }
      });
    }
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _repo.trainings(userId),
        _repo.competitions(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _trainings = results[0] as List<PlannedTraining>;
        _competitions = results[1] as List<Competition>;
      });
      await AgendaNotificationService.instance.sync(
        trainings: _trainings,
        competitions: _competitions,
        techniques: await loadTechniqueReminderInput(widget.controller),
      );
    } catch (_) {
      // Lijst blijft leeg/oud; pull-to-refresh probeert het opnieuw.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editTraining([PlannedTraining? existing]) async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    var techniques = const <Technique>[];
    try {
      techniques = await TechniqueRepository(
        widget.controller.client!,
      ).listForUser(userId);
    } catch (_) {
      // Zonder lijst kun je nog steeds plannen, alleen geen technieken kiezen.
    }
    if (!mounted) return;
    final profile = widget.controller.profile;
    final result = await showModalBottomSheet<_SheetResult<PlannedTraining>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrainingSheet(
        existing: existing,
        competition: nextCompetition(_competitions, DateTime.now()),
        techniques: techniques,
        defaultTechniqueReminders: profile?.techniqueRemindersEnabled == false
            ? const []
            : (profile?.techniqueReminderDefaults ?? const [60, 0]),
      ),
    );
    if (result == null) return;
    try {
      if (result.deleted) {
        await _repo.deleteTraining(existing!.id);
      } else {
        if (result.value!.remindMinutesBefore != null ||
            result.value!.techniqueReminders.isNotEmpty) {
          await AgendaNotificationService.instance
              .requestExactAlarmPermissionIfNeeded();
        }
        await _repo.saveTraining(result.value!, userId);
      }
      await _load();
    } catch (_) {
      _snack('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  /// Bestaande wedstrijd: eerst de detailpagina (alle info, links), met
  /// daar de knoppen Aanpassen en Verwijderen.
  Future<void> _openCompetition(Competition competition) async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CompetitionDetailScreen(
          competition: competition,
          repository: _repo,
          userId: userId,
          currentWeightKg: widget.controller.profile?.weightKg,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editCompetition([Competition? existing]) async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    final result = await showModalBottomSheet<_SheetResult<Competition>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CompetitionSheet(existing: existing),
    );
    if (result == null) return;
    try {
      if (result.deleted) {
        await _repo.deleteCompetition(existing!.id);
      } else {
        await _repo.saveCompetition(result.value!, userId);
      }
      await _load();
    } catch (_) {
      _snack('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = nextCompetition(_competitions, now);
    final upcoming =
        _trainings
            .where((t) => !t.startsAt.isBefore(now.subtract(const Duration(hours: 3))))
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = _trainings.where((t) => !upcoming.contains(t)).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final comps = [..._competitions]
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

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
          if (next != null)
            CompetitionCountdownCard(
              competition: next,
              currentWeightKg: widget.controller.profile?.weightKg,
              onTap: () => _openCompetition(next),
            )
          else
            KCard(
              onTap: () => _editCompetition(),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined, color: AppColor.coral),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Geen wedstrijd gepland', style: AppText.cardTitle),
                        Text(
                          'Voeg je volgende wedstrijd toe voor een dagelijkse aftelling.',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.add, color: AppColor.ink),
                ],
              ),
            ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _editTraining(),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Training'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editCompetition(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Wedstrijd'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          KSectionTitle(
            'Gepland',
            trailing: upcoming.isEmpty ? null : '${upcoming.length} komend',
          ),
          if (!_loading && upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Nog geen trainingen gepland.',
                style: AppText.caption,
              ),
            ),
          for (var i = 0; i < upcoming.length; i++) ...[
            if (i == 0 ||
                daysUntil(upcoming[i].startsAt, upcoming[i - 1].startsAt) != 0)
              Padding(
                padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 10, 0, 6),
                child: KLabel(_dayLabel(upcoming[i].startsAt, now)),
              ),
            _TrainingRow(
              training: upcoming[i],
              conflict: conflictsWithCompetition(
                upcoming[i].kind,
                upcoming[i].startsAt,
                next,
              ),
              onTap: () => _editTraining(upcoming[i]),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (past.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showPast = !_showPast),
              icon: Icon(_showPast ? Icons.expand_less : Icons.expand_more),
              label: Text(
                _showPast ? 'Verberg afgelopen' : 'Afgelopen (${past.length})',
              ),
            ),
            if (_showPast)
              for (final t in past.take(30)) ...[
                Opacity(
                  opacity: .6,
                  child: _TrainingRow(
                    training: t,
                    conflict: false,
                    showDate: true,
                    onTap: () => _editTraining(t),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
          ],
          const SizedBox(height: AppSpace.lg),
          KSectionTitle(
            'Wedstrijden',
            trailing: comps.isEmpty ? null : '${comps.length}',
          ),
          if (!_loading && comps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Nog geen wedstrijden.', style: AppText.caption),
            ),
          for (final c in comps) ...[
            _CompetitionRow(
              competition: c,
              onTap: () => _openCompetition(c),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }

  static String _dayLabel(DateTime at, DateTime now) {
    final d = daysUntil(at, now);
    if (d == 0) return 'Vandaag';
    if (d == 1) return 'Morgen';
    return DateFormat('EEEE d MMMM', 'nl_NL').format(at);
  }
}

// ───────────────────────── aftelkaart ───────────────────────────────────────

/// De eerstvolgende wedstrijd: dagen te gaan, fase, disciplineregel.
/// Ook gebruikt op Vandaag.
class CompetitionCountdownCard extends StatelessWidget {
  const CompetitionCountdownCard({
    super.key,
    required this.competition,
    this.onTap,
    this.compact = false,
    this.currentWeightKg,
  });

  final Competition competition;
  final VoidCallback? onTap;
  final bool compact;

  /// Huidig gewicht uit het profiel, voor "nog x kg te gaan".
  final double? currentWeightKg;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final now = DateTime.now();
    final days = daysUntil(c.startsAt, now);
    final phase = phaseFor(days);
    final rule = disciplineReminder(c.discipline);
    final weight = weightStatus(c, currentWeightKg);
    return KCard(
      glow: days <= 14 ? AppColor.coral : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, size: 20, color: AppColor.coral),
              const SizedBox(width: 8),
              const Expanded(
                child: KLabel('Volgende wedstrijd', color: AppColor.coralSoft),
              ),
              KTag(c.discipline.label, color: AppColor.ice),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: AppText.title),
                    Text(
                      [
                        DateFormat('EEE d MMM · HH:mm', 'nl_NL').format(c.startsAt),
                        if (c.location.isNotEmpty) c.location,
                        if (c.weightClass.isNotEmpty) c.weightClass,
                      ].join(' · '),
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    days == 0 ? 'Vandaag' : '$days',
                    style: AppText.metric.copyWith(
                      color: AppColor.coralSoft,
                      fontSize: days == 0 ? 24 : 32,
                    ),
                  ),
                  KLabel(
                    days == 1 ? 'dag te gaan' : (days == 0 ? '' : 'dagen te gaan'),
                  ),
                ],
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColor.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KLabel(phase.label, color: AppColor.ice),
                  const SizedBox(height: 4),
                  Text(phase.focus, style: AppText.body),
                  if (c.goal.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Doel: ${c.goal}', style: AppText.caption),
                  ],
                ],
              ),
            ),
          ],
          if (weight != null) ...[
            const SizedBox(height: AppSpace.sm),
            _WeightLine(status: weight, current: currentWeightKg),
          ],
          if (rule != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.rule, size: 16, color: AppColor.coralSoft),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rule,
                    style: AppText.caption.copyWith(color: AppColor.ink),
                  ),
                ),
              ],
            ),
          ],
          if (c.dailyReminder && !compact) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 14,
                  color: AppColor.inkFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  'Dagelijkse herinnering om ${c.reminderTime}',
                  style: AppText.caption,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _kg(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';

/// "Onder 79,0 kg · doel 78,5 kg · nu 80,2 kg — nog 1,7 kg".
class _WeightLine extends StatelessWidget {
  const _WeightLine({required this.status, required this.current});

  final WeightStatus status;
  final double? current;

  @override
  Widget build(BuildContext context) {
    final toGo = status.toGoKg;
    final reached = toGo != null && toGo <= 0.05;
    final color = toGo == null
        ? AppColor.inkMuted
        : reached
        ? AppColor.ice
        : (status.withinLimit == false ? AppColor.amber : AppColor.coralSoft);
    final parts = [
      status.limitLabel,
      if (!status.limitLabel.startsWith('Doel')) 'doel ${_kg(status.goalKg)}',
      if (current != null) 'nu ${_kg(current!)}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.monitor_weight_outlined, size: 16, color: AppColor.ice),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: parts.join(' · '),
              style: AppText.caption.copyWith(color: AppColor.ink),
              children: [
                if (toGo != null)
                  TextSpan(
                    text: reached
                        ? ' — op gewicht'
                        : ' — nog ${_kg(toGo.abs())}',
                    style: AppText.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  TextSpan(
                    text: ' — vul je gewicht in bij je profiel',
                    style: AppText.caption,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── rijen ────────────────────────────────────────────

class _TrainingRow extends StatelessWidget {
  const _TrainingRow({
    required this.training,
    required this.conflict,
    required this.onTap,
    this.showDate = false,
  });

  final PlannedTraining training;
  final bool conflict;
  final bool showDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = training;
    final color = switch (t.kind) {
      TrainingKind.sportSambo => AppColor.coral,
      TrainingKind.combatSambo => AppColor.coralSoft,
      TrainingKind.kracht => AppColor.slateDim,
      TrainingKind.overig => AppColor.inkFaint,
    };
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
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(t.startsAt),
                              style: AppText.cardTitle,
                            ),
                            if (t.endsAt case final end?)
                              Text(
                                'tot ${DateFormat('HH:mm').format(end)}',
                                style: AppText.caption,
                              ),
                            if (showDate)
                              Text(
                                DateFormat('d MMM', 'nl_NL').format(t.startsAt),
                                style: AppText.caption,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KTag(t.kind.label, color: color),
                            const SizedBox(height: 4),
                            Text(t.displayTitle, style: AppText.bodyStrong),
                            if (t.location.isNotEmpty)
                              Text(t.location, style: AppText.caption),
                            if (t.techniqueIds.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.sports_martial_arts_outlined,
                                      size: 13,
                                      color: AppColor.coralSoft,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${t.techniqueIds.length} '
                                      '${t.techniqueIds.length == 1 ? 'techniek' : 'technieken'} oefenen',
                                      style: AppText.caption.copyWith(
                                        color: AppColor.coralSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (conflict)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Past niet bij je komende wedstrijd',
                                  style: AppText.caption.copyWith(
                                    color: AppColor.amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (t.remindMinutesBefore != null ||
                          t.techniqueReminders.isNotEmpty)
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                          color: AppColor.ice,
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

class _CompetitionRow extends StatelessWidget {
  const _CompetitionRow({required this.competition, required this.onTap});

  final Competition competition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final days = daysUntil(c.startsAt, DateTime.now());
    final past = days < 0;
    final result = c.hasResult
        ? [
            if (c.resultPlace != null) '${c.resultPlace}e plaats',
            if (c.resultWins != null || c.resultLosses != null)
              '${c.resultWins ?? 0}W – ${c.resultLosses ?? 0}V',
          ].join(' · ')
        : null;
    return KCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: past ? AppColor.surfaceHigh : AppColor.coralWash,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              c.resultPlace == 1 ? Icons.emoji_events : Icons.sports_mma,
              color: past ? AppColor.inkMuted : AppColor.coralSoft,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: AppText.bodyStrong),
                Text(
                  '${DateFormat('d MMM yyyy', 'nl_NL').format(c.startsAt)} · ${c.discipline.label}',
                  style: AppText.caption,
                ),
                if (result != null)
                  Text(
                    result,
                    style: AppText.caption.copyWith(color: AppColor.ice),
                  )
                else if (past)
                  Text(
                    'Tik om je uitslag in te vullen',
                    style: AppText.caption.copyWith(color: AppColor.coralSoft),
                  ),
              ],
            ),
          ),
          if (!past)
            KPill(
              text: days == 0
                  ? 'Vandaag'
                  : '$days ${days == 1 ? 'dag' : 'dagen'}',
              color: AppColor.coralSoft,
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── detailpagina wedstrijd ───────────────────────────

/// Alles over één wedstrijd: aftelling, fase, gewicht, disciplineregel,
/// doel, links en uitslag. Aanpassen en verwijderen gaan via een knop.
class CompetitionDetailScreen extends StatefulWidget {
  const CompetitionDetailScreen({
    super.key,
    required this.competition,
    required this.repository,
    required this.userId,
    this.currentWeightKg,
  });

  final Competition competition;
  final AgendaRepository repository;
  final String userId;
  final double? currentWeightKg;

  @override
  State<CompetitionDetailScreen> createState() =>
      _CompetitionDetailScreenState();
}

class _CompetitionDetailScreenState extends State<CompetitionDetailScreen> {
  late Competition _c = widget.competition;
  bool _changed = false;
  bool _busy = false;

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit() async {
    final result = await showModalBottomSheet<_SheetResult<Competition>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CompetitionSheet(existing: _c),
    );
    if (result == null || !mounted) return;
    if (result.deleted) {
      await _delete(confirm: false);
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await widget.repository.saveCompetition(
        result.value!,
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _c = saved;
        _changed = true;
      });
    } catch (_) {
      _snack('Opslaan is niet gelukt. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete({bool confirm = true}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('"${_c.name}" verwijderen?', style: AppText.cardTitle),
          content: Text(
            'De wedstrijd, de aftelling en de dagelijkse meldingen verdwijnen.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuleer'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Verwijderen'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.deleteCompetition(_c.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Verwijderen is niet gelukt. Probeer opnieuw.');
    }
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && mounted) _snack('Deze link kon niet worden geopend.');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final days = daysUntil(c.startsAt, DateTime.now());
    final past = days < 0;
    final weight = weightStatus(c, widget.currentWeightKg);
    String kg(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
          title: Text(c.name, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (!past)
                CompetitionCountdownCard(
                  competition: c,
                  currentWeightKg: widget.currentWeightKg,
                )
              else
                KCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const KLabel('Afgelopen', color: AppColor.inkMuted),
                      const SizedBox(height: 6),
                      Text(c.name, style: AppText.title),
                      Text(
                        DateFormat('EEEE d MMMM yyyy', 'nl_NL').format(c.startsAt),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.md),
              KCard(
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.event,
                      label: 'Wanneer',
                      value: DateFormat('EEEE d MMMM yyyy · HH:mm', 'nl_NL')
                          .format(c.startsAt),
                    ),
                    _InfoRow(
                      icon: Icons.sports_mma_outlined,
                      label: 'Discipline',
                      value: c.discipline.label,
                    ),
                    if (c.location.isNotEmpty)
                      _InfoRow(
                        icon: Icons.place_outlined,
                        label: 'Locatie',
                        value: c.location,
                      ),
                    if (c.weightLimit != WeightLimit.none && c.weightLimitKg != null)
                      _InfoRow(
                        icon: Icons.monitor_weight_outlined,
                        label: 'Gewichtsklasse',
                        value: '${c.weightLimit.label} ${kg(c.weightLimitKg!)}'
                            '${c.targetWeightKg != null ? ' · doel ${kg(c.targetWeightKg!)}' : ''}',
                      )
                    else if (c.targetWeightKg != null)
                      _InfoRow(
                        icon: Icons.monitor_weight_outlined,
                        label: 'Doelgewicht',
                        value: kg(c.targetWeightKg!),
                      ),
                    if (c.goal.isNotEmpty)
                      _InfoRow(icon: Icons.flag_outlined, label: 'Jouw doel', value: c.goal),
                    _InfoRow(
                      icon: Icons.notifications_active_outlined,
                      label: 'Dagelijkse melding',
                      value: c.dailyReminder ? 'Om ${c.reminderTime}' : 'Uit',
                      last: true,
                    ),
                  ],
                ),
              ),
              if (past && weight != null) ...[
                const SizedBox(height: AppSpace.md),
                KCard(child: _WeightLine(status: weight, current: widget.currentWeightKg)),
              ],
              if (c.rulesUrl.isNotEmpty || c.websiteUrl.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                const KSectionTitle('Links'),
                if (c.rulesUrl.isNotEmpty)
                  _LinkTile(
                    icon: Icons.gavel_outlined,
                    title: 'Reglement',
                    url: c.rulesUrl,
                    onTap: () => _open(c.rulesUrl),
                  ),
                if (c.websiteUrl.isNotEmpty)
                  _LinkTile(
                    icon: Icons.public,
                    title: 'Toernooiwebsite',
                    url: c.websiteUrl,
                    onTap: () => _open(c.websiteUrl),
                  ),
              ],
              if (past || c.hasResult) ...[
                const SizedBox(height: AppSpace.md),
                const KSectionTitle('Uitslag'),
                KCard(
                  onTap: c.hasResult ? null : _edit,
                  child: c.hasResult
                      ? Row(
                          children: [
                            if (c.resultPlace != null)
                              Expanded(
                                child: KMetricTile(
                                  label: 'Plaats',
                                  value: '${c.resultPlace}e',
                                  valueColor: c.resultPlace! <= 3
                                      ? AppColor.amberBright
                                      : AppColor.ink,
                                ),
                              ),
                            if (c.resultPlace != null) const SizedBox(width: 8),
                            Expanded(
                              child: KMetricTile(
                                label: 'Gewonnen',
                                value: '${c.resultWins ?? 0}',
                                valueColor: AppColor.ice,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: KMetricTile(
                                label: 'Verloren',
                                value: '${c.resultLosses ?? 0}',
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Nog geen uitslag — tik om in te vullen.',
                          style: AppText.body.copyWith(color: AppColor.coralSoft),
                        ),
                ),
                if (c.resultNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(c.resultNote, style: AppText.body),
                ],
              ],
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _delete(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColor.redBright,
                        side: const BorderSide(color: AppColor.red),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Verwijderen'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(past && !c.hasResult ? 'Uitslag invullen' : 'Aanpassen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: AppColor.line)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColor.inkMuted),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KLabel(label),
              const SizedBox(height: 2),
              Text(value, style: AppText.body),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.url,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: KCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColor.ice),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                Text(
                  url.replaceFirst(RegExp(r'^https?://'), ''),
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.open_in_new, size: 18, color: AppColor.inkFaint),
        ],
      ),
    ),
  );
}

// ───────────────────────── invoerbladen ─────────────────────────────────────

class _SheetResult<T> {
  final T? value;
  final bool deleted;
  const _SheetResult.saved(this.value) : deleted = false;
  const _SheetResult.deleted() : value = null, deleted = true;
}

const _reminderOptions = <(int?, String)>[
  (null, 'Geen'),
  (15, '15 min'),
  (30, '30 min'),
  (60, '1 uur'),
  (120, '2 uur'),
  (1440, '1 dag'),
];

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom +
          20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColor.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(title, style: AppText.title),
          const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    ),
  );
}

Widget _fieldLabel(String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: KLabel(text),
);

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> pickDate() async {
      final d = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      );
      if (d != null) {
        onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute));
      }
    }

    Future<void> pickTime() async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(value),
      );
      if (t != null) {
        onChanged(
          DateTime(value.year, value.month, value.day, t.hour, t.minute),
        );
      }
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: OutlinedButton.icon(
            onPressed: pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat('EEE d MMM yyyy', 'nl_NL').format(value)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: pickTime,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(DateFormat('HH:mm').format(value)),
          ),
        ),
      ],
    );
  }
}

class _TrainingSheet extends StatefulWidget {
  const _TrainingSheet({
    this.existing,
    this.competition,
    this.techniques = const [],
    this.defaultTechniqueReminders = const [60, 0],
  });

  final PlannedTraining? existing;
  final Competition? competition;

  /// Je technieken, om te kiezen welke je bij deze training wilt oefenen.
  final List<Technique> techniques;

  /// Voorgestelde herinneringen zodra je de eerste techniek kiest.
  final List<int> defaultTechniqueReminders;

  @override
  State<_TrainingSheet> createState() => _TrainingSheetState();
}

class _TrainingSheetState extends State<_TrainingSheet> {
  late DateTime _at;
  late TrainingKind _kind;
  late int? _remind;
  late int? _duration;
  late List<String> _techniqueIds;
  late List<int> _techniqueReminders;
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _at = e?.startsAt ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19);
    _kind =
        e?.kind ??
        (widget.competition?.discipline == Discipline.combat
            ? TrainingKind.combatSambo
            : TrainingKind.sportSambo);
    _remind = e == null ? 60 : e.remindMinutesBefore;
    _duration = e == null ? 90 : e.durationMinutes;
    _techniqueIds = [...?e?.techniqueIds];
    _techniqueReminders = [...?e?.techniqueReminders];
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conflict = conflictsWithCompetition(_kind, _at, widget.competition);
    return _SheetFrame(
      title: widget.existing == null ? 'Training plannen' : 'Training aanpassen',
      children: [
        _fieldLabel('Wanneer'),
        _DateTimeRow(value: _at, onChanged: (v) => setState(() => _at = v)),
        const SizedBox(height: 8),
        _EndTimeRow(
          start: _at,
          duration: _duration,
          onChanged: (d) => setState(() => _duration = d),
        ),
        _fieldLabel('Soort'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in TrainingKind.values)
              ChoiceChip(
                label: Text(k.label),
                selected: _kind == k,
                showCheckmark: false,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        if (conflict) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColor.amberWash,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              'Je volgende wedstrijd (${widget.competition!.name}) is '
              '${widget.competition!.discipline.label.toLowerCase()} — '
              '${disciplineReminder(widget.competition!.discipline)}',
              style: AppText.caption.copyWith(color: AppColor.amberBright),
            ),
          ),
        ],
        _fieldLabel('Titel (optioneel)'),
        TextField(
          controller: _title,
          style: AppText.body,
          decoration: InputDecoration(hintText: _kind.label),
        ),
        _fieldLabel('Locatie (optioneel)'),
        TextField(
          controller: _location,
          style: AppText.body,
          decoration: const InputDecoration(hintText: 'Bv. club, zaal'),
        ),
        _fieldLabel('Melding vooraf'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (minutes, label) in _reminderOptions)
              ChoiceChip(
                label: Text(label),
                selected: _remind == minutes,
                showCheckmark: false,
                onSelected: (_) => setState(() => _remind = minutes),
              ),
          ],
        ),
        _fieldLabel('Technieken oefenen (optioneel)'),
        _TechniquePicker(
          all: widget.techniques,
          selected: _techniqueIds,
          onChanged: (ids) => setState(() {
            // Eerste techniek: de standaardherinneringen voorstellen.
            if (_techniqueIds.isEmpty &&
                ids.isNotEmpty &&
                _techniqueReminders.isEmpty) {
              _techniqueReminders = [...widget.defaultTechniqueReminders];
            }
            _techniqueIds = ids;
          }),
        ),
        if (_techniqueIds.isNotEmpty) ...[
          _fieldLabel('Herinneringen voor deze technieken'),
          _ReminderEditor(
            start: _at,
            duration: _duration,
            reminders: _techniqueReminders,
            onChanged: (r) => setState(() => _techniqueReminders = r),
          ),
        ],
        _fieldLabel('Notitie (optioneel)'),
        TextField(
          controller: _note,
          style: AppText.body,
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            if (widget.existing != null) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const _SheetResult<PlannedTraining>.deleted()),
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
                onPressed: () => Navigator.pop(
                  context,
                  _SheetResult.saved(
                    PlannedTraining(
                      id: widget.existing?.id ?? '',
                      startsAt: _at,
                      kind: _kind,
                      title: _title.text,
                      location: _location.text,
                      note: _note.text,
                      remindMinutesBefore: _remind,
                      durationMinutes: _duration,
                      techniqueIds: _techniqueIds,
                      techniqueReminders: _techniqueIds.isEmpty
                          ? const []
                          : normalizeReminders([
                              for (final m in _techniqueReminders)
                                if (m >= 0 ||
                                    -m <=
                                        (_duration ?? kMaxMinutesAfterStart))
                                  m,
                            ]),
                    ),
                  ),
                ),
                child: const Text('Opslaan'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Tot 20:30 · 1u30" — eindtijd en duur van een geplande training. Tot
/// aanpassen past de duur aan; de duur aanpassen schuift de tot-tijd op.
class _EndTimeRow extends StatelessWidget {
  const _EndTimeRow({
    required this.start,
    required this.duration,
    required this.onChanged,
  });

  final DateTime start;
  final int? duration;
  final ValueChanged<int?> onChanged;

  static String _durationLabel(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '${h}u' : '${h}u${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = duration;
    if (d == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => onChanged(90),
          icon: const Icon(Icons.more_time, size: 18),
          label: const Text('Eindtijd toevoegen'),
        ),
      );
    }
    final end = endFor(start, d);
    Future<void> pickEnd() async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(end),
        helpText: 'Tot',
      );
      if (t != null) onChanged(durationUntil(start, t.hour, t.minute));
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: OutlinedButton.icon(
            onPressed: pickEnd,
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: Text('Tot ${DateFormat('HH:mm').format(end)}'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '15 min korter',
          onPressed: d >= 15 ? () => onChanged(d - 15) : null,
          icon: const Icon(Icons.remove),
        ),
        Text(_durationLabel(d), style: AppText.bodyStrong),
        IconButton(
          tooltip: '15 min langer',
          onPressed: d + 15 <= 1440 ? () => onChanged(d + 15) : null,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: 'Geen eindtijd',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close, size: 18, color: AppColor.inkFaint),
        ),
      ],
    );
  }
}

/// Technieken kiezen voor een training: gekozen technieken als chips (tik
/// op × om weg te halen), en een knop die een doorzoekbare lijst opent.
class _TechniquePicker extends StatelessWidget {
  const _TechniquePicker({
    required this.all,
    required this.selected,
    required this.onChanged,
  });

  final List<Technique> all;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TechniqueChoiceSheet(all: all, selected: selected),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final t in all) t.id: t};
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in selected)
          if (byId[id] case final t?)
            InputChip(
              avatar: const Icon(Icons.sports_martial_arts_outlined, size: 16),
              label: Text(t.name),
              onDeleted: () =>
                  onChanged([for (final s in selected) if (s != id) s]),
            ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: Text(selected.isEmpty ? 'Techniek kiezen' : 'Aanpassen'),
          onPressed: all.isEmpty ? null : () => _open(context),
        ),
        if (all.isEmpty)
          Text('Je hebt nog geen technieken.', style: AppText.caption),
      ],
    );
  }
}

class _TechniqueChoiceSheet extends StatefulWidget {
  const _TechniqueChoiceSheet({required this.all, required this.selected});

  final List<Technique> all;
  final List<String> selected;

  @override
  State<_TechniqueChoiceSheet> createState() => _TechniqueChoiceSheetState();
}

class _TechniqueChoiceSheetState extends State<_TechniqueChoiceSheet> {
  late final Set<String> _chosen = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list =
        widget.all
            .where((t) => q.isEmpty || t.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final insets = MediaQuery.of(context);
    return SizedBox(
      height: insets.size.height * .75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          12 + insets.viewInsets.bottom + insets.padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Technieken oefenen', style: AppText.title),
            const SizedBox(height: 10),
            TextField(
              style: AppText.body,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Zoek een techniek',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final t in list)
                    CheckboxListTile(
                      value: _chosen.contains(t.id),
                      dense: true,
                      title: Text(t.name, style: AppText.body),
                      subtitle: t.learningStatus == LearningStatus.none
                          ? null
                          : Text(
                              t.learningStatus.label,
                              style: AppText.caption,
                            ),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _chosen.add(t.id);
                        } else {
                          _chosen.remove(t.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              // Volgorde van de lijst aanhouden.
              onPressed: () => Navigator.pop(context, [
                for (final t in widget.all)
                  if (_chosen.contains(t.id)) t.id,
              ]),
              child: Text('Klaar (${_chosen.length})'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Meerdere herinneringen: vooraf, bij de start of tijdens de training
/// (negatieve minuten). Toevoegen via vaste keuzes of een eigen tijd — nooit
/// na de eindtijd.
class _ReminderEditor extends StatelessWidget {
  const _ReminderEditor({
    required this.start,
    required this.duration,
    required this.reminders,
    required this.onChanged,
  });

  final DateTime start;

  /// Duur van de training (null = geen eindtijd).
  final int? duration;
  final List<int> reminders;
  final ValueChanged<List<int>> onChanged;

  static const _quick = [1440, 120, 60, 30, 15, 0, -15, -30, -45, -60];

  /// Past dit moment binnen de training (niet na de eindtijd)?
  bool _fits(int minutesBefore) =>
      minutesBefore >= 0 ||
      -minutesBefore <= (duration ?? kMaxMinutesAfterStart);

  void _add(int minutes) => onChanged(normalizeReminders([...reminders, minutes]));

  Future<void> _addCustom(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        start.subtract(const Duration(minutes: 45)),
      ),
      helpText: 'Herinnering om',
    );
    if (t == null || !context.mounted) return;
    final at = DateTime(start.year, start.month, start.day, t.hour, t.minute);
    final minutesBefore = start.difference(at).inMinutes;
    if (!_fits(minutesBefore)) {
      final end = duration == null ? null : endFor(start, duration!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            end == null
                ? 'Dat is te lang na de start van de training.'
                : 'Een herinnering mag niet na de eindtijd '
                      '(${DateFormat('HH:mm').format(end)}) vallen.',
          ),
        ),
      );
      return;
    }
    _add(minutesBefore);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reminders.isEmpty)
          Text('Geen herinneringen.', style: AppText.caption)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in reminders)
                InputChip(
                  avatar: const Icon(Icons.notifications_outlined, size: 16),
                  label: Text(
                    '${DateFormat('HH:mm').format(start.subtract(Duration(minutes: m)))}'
                    ' · ${reminderLabel(m)}',
                  ),
                  onDeleted: () =>
                      onChanged([for (final r in reminders) if (r != m) r]),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _quick)
              if (!reminders.contains(m) && _fits(m))
                ActionChip(
                  label: Text('+ ${reminderLabel(m)}'),
                  onPressed: () => _add(m),
                ),
            ActionChip(
              avatar: const Icon(Icons.schedule, size: 16),
              label: const Text('Eigen tijd'),
              onPressed: () => _addCustom(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompetitionSheet extends StatefulWidget {
  const _CompetitionSheet({this.existing});

  final Competition? existing;

  @override
  State<_CompetitionSheet> createState() => _CompetitionSheetState();
}

class _CompetitionSheetState extends State<_CompetitionSheet> {
  late DateTime _at;
  late Discipline _discipline;
  late bool _daily;
  late TimeOfDay _reminderTime;
  late WeightLimit _weightLimit;
  late final TextEditingController _limitKg;
  late final TextEditingController _targetKg;
  late final TextEditingController _rulesUrl;
  late final TextEditingController _websiteUrl;
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _weight;
  late final TextEditingController _goal;
  late final TextEditingController _place;
  late final TextEditingController _wins;
  late final TextEditingController _losses;
  late final TextEditingController _resultNote;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final inAMonth = DateTime.now().add(const Duration(days: 30));
    _at = e?.startsAt ?? DateTime(inAMonth.year, inAMonth.month, inAMonth.day, 10);
    _discipline = e?.discipline ?? Discipline.sport;
    _daily = e?.dailyReminder ?? true;
    final parts = (e?.reminderTime ?? '08:00').split(':');
    _reminderTime = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    _weightLimit = e?.weightLimit ?? WeightLimit.none;
    String kg(double? v) =>
        v == null ? '' : v.toStringAsFixed(1).replaceAll('.', ',');
    _limitKg = TextEditingController(text: kg(e?.weightLimitKg));
    _rulesUrl = TextEditingController(text: e?.rulesUrl ?? '');
    _websiteUrl = TextEditingController(text: e?.websiteUrl ?? '');
    _targetKg = TextEditingController(text: kg(e?.targetWeightKg));
    _name = TextEditingController(text: e?.name ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _weight = TextEditingController(text: e?.weightClass ?? '');
    _goal = TextEditingController(text: e?.goal ?? '');
    _place = TextEditingController(text: e?.resultPlace?.toString() ?? '');
    _wins = TextEditingController(text: e?.resultWins?.toString() ?? '');
    _losses = TextEditingController(text: e?.resultLosses?.toString() ?? '');
    _resultNote = TextEditingController(text: e?.resultNote ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _rulesUrl,
      _websiteUrl,
      _limitKg,
      _targetKg,
      _name,
      _location,
      _weight,
      _goal,
      _place,
      _wins,
      _losses,
      _resultNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _timeText =>
      '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}';

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  double? _kgValue(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null || v < 20 || v > 300 ? null : v;
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Geef de wedstrijd een naam.');
      return;
    }
    Navigator.pop(
      context,
      _SheetResult.saved(
        Competition(
          id: widget.existing?.id ?? '',
          name: _name.text,
          startsAt: _at,
          discipline: _discipline,
          location: _location.text,
          weightClass: _kgValue(_limitKg) != null &&
                  _weightLimit != WeightLimit.none
              ? '${_weightLimit == WeightLimit.under ? '-' : '+'}'
                    '${_limitKg.text.trim()} kg'
              : _weight.text,
          goal: _goal.text,
          dailyReminder: _daily,
          reminderTime: _timeText,
          resultPlace: _int(_place),
          resultWins: _int(_wins),
          resultLosses: _int(_losses),
          resultNote: _resultNote.text,
          weightLimit: _kgValue(_limitKg) == null
              ? WeightLimit.none
              : _weightLimit,
          weightLimitKg: _weightLimit == WeightLimit.none
              ? null
              : _kgValue(_limitKg),
          targetWeightKg: _kgValue(_targetKg),
          rulesUrl: _rulesUrl.text,
          websiteUrl: _websiteUrl.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPast = daysUntil(_at, DateTime.now()) < 0;
    return _SheetFrame(
      title: widget.existing == null ? 'Wedstrijd toevoegen' : 'Wedstrijd',
      children: [
        _fieldLabel('Naam'),
        TextField(
          controller: _name,
          style: AppText.body,
          decoration: InputDecoration(
            hintText: 'Bv. NK Sport Sambo',
            errorText: _error,
          ),
        ),
        _fieldLabel('Wanneer'),
        _DateTimeRow(value: _at, onChanged: (v) => setState(() => _at = v)),
        _fieldLabel('Discipline'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<Discipline>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Discipline.sport, label: Text('Sport')),
              ButtonSegment(value: Discipline.combat, label: Text('Combat')),
              ButtonSegment(value: Discipline.both, label: Text('Beide')),
            ],
            selected: {_discipline},
            onSelectionChanged: (v) => setState(() => _discipline = v.first),
          ),
        ),
        if (disciplineReminder(_discipline) != null) ...[
          const SizedBox(height: 6),
          Text(
            disciplineReminder(_discipline)!,
            style: AppText.caption,
          ),
        ],
        _fieldLabel('Locatie'),
        TextField(controller: _location, style: AppText.body),
        _fieldLabel('Gewichtsklasse'),
        Wrap(
          spacing: 6,
          children: [
            for (final w in WeightLimit.values)
              ChoiceChip(
                label: Text(w == WeightLimit.none ? 'Geen klasse' : '${w.label} grens'),
                selected: _weightLimit == w,
                showCheckmark: false,
                onSelected: (_) => setState(() => _weightLimit = w),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_weightLimit != WeightLimit.none) ...[
              Expanded(
                child: TextField(
                  controller: _limitKg,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppText.body,
                  decoration: InputDecoration(
                    labelText: _weightLimit == WeightLimit.under
                        ? 'Onder (kg)'
                        : 'Boven (kg)',
                    hintText: 'Bv. 79',
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _targetKg,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Doel op weging (kg)',
                  hintText: 'Bv. 78,5',
                ),
              ),
            ),
          ],
        ),
        _fieldLabel('Jouw doel'),
        TextField(
          controller: _goal,
          style: AppText.body,
          decoration: const InputDecoration(
            hintText: 'Bv. elke partij de eerste worp',
          ),
        ),
        _fieldLabel('Links (optioneel)'),
        TextField(
          controller: _rulesUrl,
          keyboardType: TextInputType.url,
          style: AppText.body,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.gavel_outlined, size: 18),
            labelText: 'Reglement',
            hintText: 'Bv. sambo.nl/reglement',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _websiteUrl,
          keyboardType: TextInputType.url,
          style: AppText.body,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.public, size: 18),
            labelText: 'Toernooiwebsite',
            hintText: 'Bv. nk-sambo.nl',
          ),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _daily,
          onChanged: (v) => setState(() => _daily = v),
          title: Text('Dagelijkse aftel-melding', style: AppText.bodyStrong),
          subtitle: Text(
            'Hoeveel dagen nog, met een motiverend bericht.',
            style: AppText.caption,
          ),
        ),
        if (_daily)
          OutlinedButton.icon(
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _reminderTime,
              );
              if (t != null) setState(() => _reminderTime = t);
            },
            icon: const Icon(Icons.schedule, size: 18),
            label: Text('Elke dag om $_timeText'),
          ),
        if (isPast || (widget.existing?.hasResult ?? false)) ...[
          _fieldLabel('Uitslag'),
          Row(
            children: [
              for (final (c, hint) in [
                (_place, 'Plaats'),
                (_wins, 'Gewonnen'),
                (_losses, 'Verloren'),
              ]) ...[
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                    style: AppText.body,
                    decoration: InputDecoration(labelText: hint),
                  ),
                ),
                if (hint != 'Verloren') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _resultNote,
            style: AppText.body,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Wat ging goed, wat neem je mee?',
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            if (widget.existing != null) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const _SheetResult<Competition>.deleted()),
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
              child: FilledButton(onPressed: _save, child: const Text('Opslaan')),
            ),
          ],
        ),
      ],
    );
  }
}
