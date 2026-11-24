// log_training_screen.dart: "Training loggen" (kinetic_log_session): een
// training achteraf vastleggen in ~30 seconden: discipline, focus, duur en
// RPE, het metabool traject uit de CGM-data van dat tijdvak, de geoefende
// technieken en mat-notities. Opslaan gaat naar `training_sessions`.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/kinetic_profile.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/start_training_sheet.dart';

const _focusOptions = ['Techniek', 'Drilling', 'Sparring', 'Wedstrijd', 'Conditie'];

const _rpeLabels = {
  1: 'Niveau 1: Flow / warming-up',
  2: 'Niveau 2: Rustig tempo',
  3: 'Niveau 3: Gemiddelde rondes',
  4: 'Niveau 4: Zware sparring',
  5: 'Niveau 5: Max / wedstrijdtempo',
};

class LogTrainingScreen extends StatefulWidget {
  const LogTrainingScreen({super.key});

  @override
  State<LogTrainingScreen> createState() => _LogTrainingScreenState();
}

class _LogTrainingScreenState extends State<LogTrainingScreen> {
  late String _discipline;
  final _name = TextEditingController();
  final _notes = TextEditingController();
  String _focus = 'Sparring';
  int _minutes = 60;
  int? _rpe;
  final List<String> _techniques = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final store = KineticScope.read(context);
    // Voorvullen met de training van vandaag, als die er is.
    final p = store.nextPlannedTraining;
    final today = p != null && daysUntil(p.startsAt, now: store.now()) == 0;
    _discipline = today ? disciplineFor(p) : kDisciplines.first;
    if (today && _discipline == 'Overig' && p.displayTitle != 'Overig') _name.text = p.displayTitle;
    if (today && p.durationMinutes != null) {
      _minutes = ((p.durationMinutes! / 15).round() * 15).clamp(15, 240);
    }
    if (_discipline == 'Kracht') _focus = 'Conditie';
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _title {
    if (_discipline != 'Overig') return _discipline;
    final n = _name.text.trim();
    return n.isEmpty ? 'Training' : n;
  }

  void _step(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _minutes = (_minutes + delta).clamp(15, 240));
  }

  Future<void> _addTechniques() async {
    final store = KineticScope.read(context);
    final pick = await showTechniquePicker(
      context,
      title: 'Technieken geoefend',
      allowCustom: true,
      initiallySelected: (e) => _techniques.contains(e.name),
    );
    if (pick == null || !mounted) return;
    final vaultNames = store.vault.map((e) => e.name).toSet();
    final picked = pick.entries.map((e) => e.name).toList();
    setState(() {
      final keep = _techniques.where((n) => !vaultNames.contains(n) || picked.contains(n)).toList();
      _techniques
        ..clear()
        ..addAll(keep)
        ..addAll(picked.where((n) => !keep.contains(n)))
        ..addAll(pick.customNames.where((n) => !keep.contains(n) && !picked.contains(n)));
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = KineticScope.read(context);
    final saved = await store.logTrainingSession(
      discipline: _title,
      focus: _focus,
      minutes: _minutes,
      rpe: _rpe,
      techniqueNames: List.of(_techniques),
      notes: _notes.text,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _saving = false);
      showToast(context, 'Opslaan mislukt. Controleer je verbinding.', error: true);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    showToastOn(messenger, 'Training gelogd: $_title • $_minutes min');
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KineticPage(
      subtitle: 'Training loggen',
      bottomBar: BottomActionBar(
        child: BigButton(
          label: _saving ? 'Opslaan…' : 'Sessie opslaan',
          icon: Icons.check_circle_outline,
          height: 56,
          onPressed: _saving ? null : _save,
        ),
      ),
      body: ListView(
        padding: pagePadding(context, top: 16, extraBottom: 24),
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: k.accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Eyebrow('Snelle post-mat log', color: k.accent)),
              const KPill('~30 sec', icon: Icons.timer_outlined, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          _disciplineCard(),
          const SizedBox(height: 16),
          _durationCard(),
          const SizedBox(height: 16),
          _MetabolicCard(minutes: _minutes),
          const SizedBox(height: 16),
          _techniquesCard(),
        ],
      ),
    );
  }

  Widget _disciplineCard() {
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('1. Discipline'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in kDisciplines)
                KChip(label: d, selected: _discipline == d, onTap: () => setState(() => _discipline = d)),
            ],
          ),
          if (_discipline == 'Overig') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              style: context.t.body,
              decoration: const InputDecoration(labelText: 'Naam van de training', hintText: 'Bijv. Worstelen'),
            ),
          ],
          const SizedBox(height: 20),
          const FormLabel('2. Sessiefocus'),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, f) in _focusOptions.indexed)
                    SizedBox(
                      // De laatste tegel vult de rij (zoals in het ontwerp).
                      width: i == _focusOptions.length - 1 && _focusOptions.length % 3 == 2 ? w * 2 + 8 : w,
                      child: _ChoiceTile(
                        label: f,
                        selected: _focus == f,
                        onTap: () => setState(() => _focus = f),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _durationCard() {
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('3. Duur & intensiteit', trailing: 'Mat-tijd'),
          KWell(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _StepTile(label: '−15m', semantics: '15 minuten minder', onTap: _minutes > 15 ? () => _step(-15) : null),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$_minutes', style: context.t.metric.copyWith(fontSize: 40)),
                      const SizedBox(width: 6),
                      Text('min', style: context.t.unit),
                    ],
                  ),
                ),
                _StepTile(label: '+15m', semantics: '15 minuten meer', onTap: _minutes < 240 ? () => _step(15) : null),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FormLabel(
            'Ervaren RPE',
            trailing: _rpe == null ? 'Tik om te kiezen' : _rpeLabels[_rpe],
            trailingColor: _rpe == null ? null : k.accent,
          ),
          Row(
            children: [
              for (var i = 1; i <= 5; i++) ...[
                if (i > 1) const SizedBox(width: 8),
                Expanded(
                  child: _ChoiceTile(
                    label: '$i',
                    big: true,
                    selected: _rpe == i,
                    onTap: () => setState(() => _rpe = _rpe == i ? null : i),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _techniquesCard() {
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormLabel(
            '5. Technieken geoefend',
            trailing: _techniques.isEmpty ? 'Optioneel' : '${_techniques.length} vastgelegd',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _techniques)
                RemovablePill(label: t, onRemove: () => setState(() => _techniques.remove(t))),
              Material(
                color: k.primaryTint,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _addTechniques,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: k.accent),
                          const SizedBox(width: 6),
                          Text(
                            'Techniek',
                            style: context.t.caption.copyWith(color: k.accent, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const FormLabel('6. Mat-notities'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: context.t.body,
            decoration: const InputDecoration(
              hintText: 'Waar lag de focus? Hoe reageerde je glucose?',
            ),
          ),
        ],
      ),
    );
  }
}

/// Keuzetegel (sessiefocus, RPE): well of primary als hij gekozen is.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap, this.big = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? k.primary : k.well,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.md),
          side: BorderSide(color: selected ? k.primary : k.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: big ? 56 : 48,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (big ? context.t.title : context.t.bodyStrong).copyWith(
                  color: selected ? k.onPrimary : k.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "−15m" / "+15m" in de duur-stepper.
class _StepTile extends StatelessWidget {
  const _StepTile({required this.label, required this.semantics, required this.onTap});
  final String label;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: k.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md), side: BorderSide(color: k.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 56,
            child: Center(
              child: Text(
                label,
                style: context.t.bodyStrong.copyWith(color: onTap == null ? k.textMuted : k.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Metabool traject": start / piek of dip / eind uit de CGM-data van het
/// tijdvak dat net is afgelopen (nu − duur .. nu).
class _MetabolicCard extends StatelessWidget {
  const _MetabolicCard({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();
    final points = store.glucoseBetween(now.subtract(Duration(minutes: minutes)), now);
    final t = GlucoseTrajectory.of(points);
    final finger = store.profile?.glucoseSource == GlucoseSource.finger;

    Widget value(String label, double mmol) {
      final ink = zoneInk(k, mmol);
      return KWell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label.toUpperCase(), style: context.t.labelSm)),
                Container(width: 7, height: 7, decoration: BoxDecoration(color: ink, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(dec1(mmol), style: context.t.metricMd),
            ),
            Text('mmol/L', style: context.t.caption),
            const SizedBox(height: 4),
            Text(zoneLabel(mmol), style: context.t.caption.copyWith(color: ink, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: Icons.autorenew, size: 40, color: k.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('4. Metabool traject', style: context.t.title),
                    Text(
                      'Laatste $minutes min • ${finger ? 'vingerprikken' : 'Dexcom G7'}',
                      style: context.t.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              t == null
                  ? const KPill('Geen data', dense: true)
                  : const KPill('Automatisch', tone: KTone.success, dot: true, dense: true),
            ],
          ),
          const SizedBox(height: 16),
          if (t == null)
            KWell(
              child: Text(
                'Geen glucosemetingen in dit tijdvak. De training wordt zonder glucoseverloop opgeslagen.',
                style: context.t.caption,
              ),
            )
          else ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: value('Start', t.start)),
                  const SizedBox(width: 8),
                  Expanded(child: value(t.middleLabel, t.middle)),
                  const SizedBox(width: 8),
                  Expanded(child: value('Eind', t.end)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            KWell(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: k.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${points.length} metingen • ${((t.inRange ?? 0) * 100).round()}% in bereik',
                      style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'Delta: ${t.delta >= 0 ? '+' : '−'}${dec1(t.delta.abs())}',
                    style: context.t.caption,
                  ),
                ],
              ),
            ),
            if (t.low < hypoBelow) ...[
              const SizedBox(height: 8),
              Text(
                'Laagste waarde ${dec1(t.low)} mmol/L: noteer wat je nam om te herstellen.',
                style: context.t.caption.copyWith(color: k.dangerInk),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
