// profile_screen.dart — tab "Profiel" (Kinetic: Athlete Profile / Passport)
//
// Opbouw:
//   1. identiteitskaart — wie, sinds wanneer, glucosebron
//   2. medisch paspoort — bron, alarmgrenzen, bolus-calculator
//   3. seizoen          — trainingen dit jaar, uren, streak
//   4. meesterschap     — technieken per leerstatus

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/training_streak.dart';
import '../models/app_profile.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../models/agenda.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/weigh_in_sheet.dart';
import '../widgets/kinetic.dart';
import 'avatar_crop_screen.dart';
import 'technique_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TechniqueRepository _techniqueRepo;
  late final SessionRepository _sessionRepo;
  List<Technique> _techniques = const [];
  List<TrainingSession> _sessions = const [];
  List<Competition> _competitions = const [];
  bool _loading = true;
  LearningStatus _mastery = LearningStatus.mastered;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _techniqueRepo = TechniqueRepository(widget.controller.client!);
    _sessionRepo = SessionRepository(widget.controller.client!);
    _load();
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _techniqueRepo.listForUser(userId),
        _sessionRepo.listForUser(userId),
        AgendaRepository(widget.controller.client!).competitions(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _techniques = results[0] as List<Technique>;
        _sessions = results[1] as List<TrainingSession>;
        _competitions = results[2] as List<Competition>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name => widget.controller.displayName;

  String get _athleteId {
    final id = widget.controller.user?.id ?? '';
    final short = id.replaceAll('-', '');
    return short.length >= 4 ? 'KNT-${short.substring(0, 4).toUpperCase()}' : 'KNT';
  }

  static String sourceLabel(GlucoseSource s) => switch (s) {
    GlucoseSource.nightscout => 'Nightscout (CGM)',
    GlucoseSource.dexcomShare => 'Dexcom Share (CGM)',
    GlucoseSource.finger => 'Vingerprik',
  };

  Future<void> _share() async {
    final p = widget.controller.profile;
    if (p == null) return;
    final lines = [
      'Kinetic atletenpaspoort — $_name',
      'Glucosebron: ${sourceLabel(p.glucoseSource)}',
      'Ondergrens training: ${mmolText(p.trainingLimit)} mmol/L',
      'Ondergrens dagelijks: ${p.dailyLowEnabled ? '${mmolText(p.dailyLowBelow)} mmol/L' : 'uit'}',
      'Bovengrens: ${p.hyperAlarmEnabled ? '${mmolText(p.hyperLimit)} mmol/L' : 'uit'}',
      if (p.bolusCalculatorEnabled)
        'Correctiefactor: ${mmolText(p.correctionFactor)} mmol/L per E',
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  Future<void> _changePhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Kies uit galerij'),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Maak een foto'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            if (widget.controller.profile?.avatarUrl.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColor.redBright,
                ),
                title: const Text('Foto verwijderen'),
                onTap: () => Navigator.pop(c, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      if (choice == 'remove') {
        await widget.controller.removeAvatar();
      } else {
        // Ruim binnenhalen (niet al op 512 px), zodat inzoomen in het
        // uitsnijscherm scherp blijft.
        final picked = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 92,
        );
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        // De fotokiezer zet een kopie in de cachemap van de app — meteen
        // opruimen, de foto zelf staat (na uitsnijden) in Supabase.
        try {
          await File(picked.path).delete();
        } catch (_) {}
        if (!mounted) return;
        final cropped = await cropAvatar(context, bytes);
        if (cropped == null) return;
        await widget.controller.updateAvatar(cropped, 'jpg');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profielfoto opslaan is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(
      text: widget.controller.profile?.username ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Gebruikersnaam', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: AppText.body,
          decoration: InputDecoration(hintText: _name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    final profile = widget.controller.profile;
    if (result == null || profile == null) return;
    await widget.controller.saveProfile(profile.copyWith(username: result));
    if (mounted && widget.controller.authError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.authError!)),
      );
    }
  }

  static String _sexLabel(String sex) => switch (sex) {
    'male' => 'Man',
    'female' => 'Vrouw',
    'other' => 'Anders',
    _ => '—',
  };

  Future<void> _editBody() async {
    final profile = widget.controller.profile;
    if (profile == null) return;
    final weight = TextEditingController(
      text: profile.weightKg == null
          ? ''
          : profile.weightKg!.toStringAsFixed(1).replaceAll('.', ','),
    );
    final height = TextEditingController(
      text: profile.heightCm?.toString() ?? '',
    );
    var sex = profile.sex;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(c).viewInsets.bottom +
                MediaQuery.of(c).padding.bottom +
                20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Lichaamsgegevens', style: AppText.title),
              const SizedBox(height: 4),
              Text(
                'Je gewicht wordt gebruikt bij de gewichtsklasse van je '
                'wedstrijden. Alles is optioneel.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppText.body,
                      decoration: const InputDecoration(
                        labelText: 'Gewicht',
                        suffixText: 'kg',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: height,
                      keyboardType: TextInputType.number,
                      style: AppText.body,
                      decoration: const InputDecoration(
                        labelText: 'Lengte',
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const KLabel('Geslacht'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('male', 'Man'),
                    ('female', 'Vrouw'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: sex == value,
                      showCheckmark: false,
                      onSelected: (_) => setSheet(() => sex = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Opslaan'),
              ),
            ],
          ),
        ),
      ),
    );
    final w = double.tryParse(weight.text.trim().replaceAll(',', '.'));
    final h = int.tryParse(height.text.trim());
    if (saved != true) return;
    final validW = w != null && w >= 20 && w <= 300 ? w : null;
    final validH = h != null && h >= 50 && h <= 250 ? h : null;
    await widget.controller.saveProfile(
      profile.copyWith(
        weightKg: validW,
        clearWeight: validW == null,
        heightCm: validH,
        clearHeight: validH == null,
        sex: sex,
      ),
    );
    if (!mounted) return;
    final error = widget.controller.authError;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Nieuw gewicht ingevuld: ook als weging bewaren (met datum).
    if (validW != null && validW != profile.weightKg) {
      await widget.controller.addWeighIn(validW);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KINETIC',
              style: AppText.cardTitle.copyWith(height: 1, letterSpacing: 1.6),
            ),
            const SizedBox(height: 3),
            const KLabel('Profiel'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final profile = widget.controller.profile;
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
                _identity(profile),
                const SizedBox(height: AppSpace.lg),
                if (profile != null) _medical(profile),
                const SizedBox(height: AppSpace.lg),
                _season(),
                const SizedBox(height: AppSpace.lg),
                _masteryCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 1. identiteit ──
  Widget _identity(AppProfile? profile) {
    final created = widget.controller.user?.createdAt;
    final since = created == null
        ? '—'
        : DateFormat('MMM yyyy', 'nl_NL').format(DateTime.parse(created));
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _photoBusy ? null : _changePhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    KAvatar(
                      url: profile?.avatarUrl ?? '',
                      initials: widget.controller.initials,
                      size: 88,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColor.coral,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColor.surface, width: 3),
                        ),
                        child: _photoBusy
                            ? const Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColor.coralInk,
                                ),
                              )
                            : const Icon(
                                Icons.photo_camera,
                                size: 15,
                                color: AppColor.coralInk,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KLabel('ID · $_athleteId', color: AppColor.ice),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _changeName,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _name,
                              style: AppText.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColor.inkFaint,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Sambo-atleet',
                      style: AppText.body.copyWith(color: AppColor.coralSoft),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.controller.user?.email ?? '',
                      style: AppText.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: KMetricTile(
                  label: 'Glucosebron',
                  value: profile == null
                      ? '—'
                      : sourceLabel(profile.glucoseSource).split(' ').first,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: KMetricTile(label: 'Lid sinds', value: since)),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _editBody,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Row(
              children: [
                Expanded(
                  child: KMetricTile(
                    label: 'Gewicht',
                    value: profile?.weightKg == null
                        ? '—'
                        : profile!.weightKg!
                              .toStringAsFixed(1)
                              .replaceAll('.', ','),
                    unit: profile?.weightKg == null ? null : 'kg',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KMetricTile(
                    label: 'Lengte',
                    value: profile?.heightCm?.toString() ?? '—',
                    unit: profile?.heightCm == null ? null : 'cm',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KMetricTile(
                    label: 'Geslacht',
                    value: _sexLabel(profile?.sex ?? ''),
                  ),
                ),
              ],
            ),
          ),
          WeighInSummary(controller: widget.controller),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColor.ink,
                    side: BorderSide.none,
                    backgroundColor: AppColor.surfaceRaised,
                  ),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Instellingen'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.iceDeep,
                    foregroundColor: AppColor.iceInk,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Delen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. medisch paspoort ──
  Widget _medical(AppProfile p) {
    final live = p.glucoseSource != GlucoseSource.finger;
    final alarmMode = switch (p.alarmMode) {
      AlarmMode.sound => 'met geluid',
      AlarmMode.off => 'uit',
      _ => 'stil',
    };
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KCardHeader(
            large: true,
            icon: Icons.medical_information_outlined,
            iconColor: AppColor.ice,
            label: 'Medisch paspoort',
          ),
          const SizedBox(height: AppSpace.md),
          _PassportRow(
            icon: Icons.sensors,
            label: 'Glucosebron',
            value: sourceLabel(p.glucoseSource),
            badge: live ? 'Live' : 'Handmatig',
            badgeColor: live ? AppColor.ice : AppColor.inkMuted,
          ),
          _PassportRow(
            icon: Icons.notifications_active_outlined,
            label: 'Hypo-alarm',
            value:
                'Training < ${mmolText(p.trainingLimit)} · dagelijks ${p.dailyLowEnabled ? '< ${mmolText(p.dailyLowBelow)}' : 'uit'}',
            badge: live ? alarmMode : 'n.v.t.',
            badgeColor: !live || p.alarmMode == AlarmMode.off
                ? AppColor.inkFaint
                : AppColor.coralSoft,
          ),
          _PassportRow(
            icon: Icons.trending_up,
            label: 'Hyper-alarm',
            value: p.hyperAlarmEnabled
                ? 'Boven ${mmolText(p.hyperLimit)} mmol/L'
                : 'Uitgeschakeld',
          ),
          _PassportRow(
            icon: Icons.calculate_outlined,
            label: 'Bolus-calculator',
            value: p.bolusCalculatorEnabled
                ? 'Correctiefactor ${mmolText(p.correctionFactor)} · doel ${mmolText(p.correctionTargetDay)}/${mmolText(p.correctionTargetNight)}'
                : 'Uit',
            last: true,
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColor.bgDeep,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColor.inkFaint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deel dit paspoort met je trainer, zodat die weet welke grenzen je aanhoudt op de mat.',
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. seizoen ──
  Widget _season() {
    final year = DateTime.now().year;
    final thisYear = _sessions.where((s) => s.startedAt.year == year).toList();
    final sambo = thisYear.where((s) => s.kind == SessionKind.sambo).length;
    final hours =
        thisYear.fold<int>(0, (n, s) => n + s.durationMinutes) / 60;
    final dips = thisYear.where((s) => s.hadDip).length;
    final streak = TrainingStreak.compute(
      _sessions.map((s) => s.startedAt).toList(),
    );
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KCardHeader(
            large: true,
            icon: Icons.emoji_events_outlined,
            iconColor: AppColor.coral,
            label: 'Seizoen $year',
            trailing: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: _SeasonStat(
                  label: 'Sessies',
                  value: '${thisYear.length}',
                  caption: '$sambo sambo',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SeasonStat(
                  label: 'Uren',
                  value: hours.toStringAsFixed(hours < 10 ? 1 : 0).replaceAll('.', ','),
                  caption: 'totaal',
                  color: AppColor.coralSoft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SeasonStat(
                  label: 'Dips',
                  value: '$dips',
                  caption: 'onder 5,0',
                  color: dips == 0 ? AppColor.ice : AppColor.amber,
                ),
              ),
            ],
          ),
          if (_competitions.any(
            (c) => c.startsAt.year == year && c.hasResult,
          )) ...[
            const SizedBox(height: AppSpace.md),
            _competitionRecord(year),
          ],
          if (streak.label != null) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColor.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColor.coral,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.local_fire_department,
                      color: AppColor.coralInk,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const KLabel('Reeks', color: AppColor.coralSoft),
                        Text(streak.label!, style: AppText.bodyStrong),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _competitionRecord(int year) {
    final done = _competitions
        .where((c) => c.startsAt.year == year && c.hasResult)
        .toList();
    final wins = done.fold<int>(0, (n, c) => n + (c.resultWins ?? 0));
    final losses = done.fold<int>(0, (n, c) => n + (c.resultLosses ?? 0));
    final podiums = done
        .where((c) => c.resultPlace != null && c.resultPlace! <= 3)
        .length;
    final total = wins + losses;
    return Container(
      padding: const EdgeInsets.all(14),
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
                const KLabel('Wedstrijdrecord', color: AppColor.coralSoft),
                const SizedBox(height: 4),
                Text(
                  '$wins – $losses',
                  style: AppText.metric.copyWith(color: AppColor.ink),
                ),
                if (total > 0)
                  Text(
                    '${(wins / total * 100).round()}% gewonnen',
                    style: AppText.caption.copyWith(color: AppColor.ice),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${done.length}',
                style: AppText.metric.copyWith(color: AppColor.ink),
              ),
              KLabel(done.length == 1 ? 'wedstrijd' : 'wedstrijden'),
              if (podiums > 0)
                Text(
                  '$podiums× podium',
                  style: AppText.caption.copyWith(color: AppColor.amberBright),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. meesterschap ──
  Widget _masteryCard() {
    final list =
        _techniques.where((t) => t.learningStatus == _mastery).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final counts = {
      for (final s in LearningStatus.values)
        s: _techniques.where((t) => t.learningStatus == s).length,
    };
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KCardHeader(
            large: true,
            icon: Icons.military_tech_outlined,
            iconColor: AppColor.coralSoft,
            label: 'Meesterschap',
          ),
          const SizedBox(height: AppSpace.md),
          KSegmented<LearningStatus>(
            activeColor: AppColor.surfaceHighest,
            activeInk: AppColor.ink,
            options: [
              (
                LearningStatus.mastered,
                'Beheerst ${counts[LearningStatus.mastered]}',
                null,
              ),
              (
                LearningStatus.learning,
                'Leren ${counts[LearningStatus.learning]}',
                null,
              ),
              (
                LearningStatus.planned,
                'Gepland ${counts[LearningStatus.planned]}',
                null,
              ),
            ],
            selected: _mastery,
            onChanged: (v) => setState(() => _mastery = v),
          ),
          const SizedBox(height: AppSpace.md),
          if (!_loading && list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nog geen technieken met deze status.',
                style: AppText.caption,
              ),
            ),
          for (final t in list.take(12)) ...[
            _TechniqueRow(
              technique: t,
              onTap: () async {
                final userId = widget.controller.user?.id;
                if (userId == null) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TechniqueDetailScreen(
                      repository: _techniqueRepo,
                      userId: userId,
                      technique: t,
                    ),
                  ),
                );
                _load();
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (list.length > 12)
            Text(
              '+ ${list.length - 12} meer in Train › Technieken',
              style: AppText.caption,
            ),
        ],
      ),
    );
  }
}

class _PassportRow extends StatelessWidget {
  const _PassportRow({
    required this.icon,
    required this.label,
    required this.value,
    this.badge,
    this.badgeColor = AppColor.ice,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? badge;
  final Color badgeColor;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColor.line)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColor.inkMuted),
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
        if (badge != null) ...[
          const SizedBox(width: 8),
          KPill(text: badge!, color: badgeColor, dot: true),
        ],
      ],
    ),
  );
}

class _SeasonStat extends StatelessWidget {
  const _SeasonStat({
    required this.label,
    required this.value,
    required this.caption,
    this.color = AppColor.ink,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(
      color: AppColor.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      children: [
        KLabel(label),
        const SizedBox(height: 6),
        Text(value, style: AppText.metric.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(caption, style: AppText.caption, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _TechniqueRow extends StatelessWidget {
  const _TechniqueRow({required this.technique, required this.onTap});

  final Technique technique;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = technique;
    final (badge, color) = switch (t.learningStatus) {
      LearningStatus.mastered => ('Beheerst', AppColor.ice),
      LearningStatus.learning => ('Leren', AppColor.coralSoft),
      LearningStatus.planned => ('Gepland', AppColor.slate),
      LearningStatus.none => ('—', AppColor.inkFaint),
    };
    final detail = [
      t.category,
      if (t.updates.isNotEmpty)
        '${t.updates.length} notitie${t.updates.length == 1 ? '' : 's'}',
      if (t.learningStatus == LearningStatus.planned && t.plannedFor != null)
        planningLabel(t.plannedFor!),
    ].join(' · ');
    return Material(
      color: AppColor.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColor.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  t.favorite ? Icons.star : Icons.sports_martial_arts,
                  size: 20,
                  color: t.favorite ? AppColor.coralSoft : AppColor.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: AppText.bodyStrong),
                    Text(
                      detail,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KTag(badge, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
