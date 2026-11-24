// start_training_sheet.dart: "Training starten" vanaf Vandaag of Training:
// discipline, format (rondes/werk/rust) en focus-technieken kiezen en de
// live sessie meteen starten. Bevat ook de techniekkiezer uit de vault en
// een paar gedeelde helpers voor glucoseverloop en mat-clearance die
// Vandaag, Training en Training loggen samen gebruiken.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/sparring_timer.dart';
import '../models/glucose.dart';
import '../models/library.dart';
import '../models/planned_training.dart';
import '../models/technique.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'sheets.dart';

/// Disciplines die je kunt starten of loggen.
const kDisciplines = ['Combat Sambo', 'Sport Sambo', 'BJJ', 'Judo', 'Kracht', 'Overig'];

/// Formatpresets voor de rondeklok.
const kFormatPresets = <({String label, String sub, SparringConfig config})>[
  (label: '5×5:00', sub: 'Sparring', config: SparringConfig(rounds: 5, workSeconds: 300, restSeconds: 60)),
  (label: '3×3:00', sub: 'Korte rondes', config: SparringConfig(rounds: 3, workSeconds: 180, restSeconds: 60)),
  (label: '1×60:00', sub: 'Techniek', config: SparringConfig(rounds: 1, workSeconds: 3600, restSeconds: 60)),
];

bool sameConfig(SparringConfig a, SparringConfig b) =>
    a.rounds == b.rounds && a.workSeconds == b.workSeconds && a.restSeconds == b.restSeconds;

/// Totale duur van een format in minuten (werk + rust tussen de rondes).
int configMinutes(SparringConfig c) =>
    ((c.rounds * c.workSeconds + math.max(0, c.rounds - 1) * c.restSeconds) / 60).round();

/// "5×5:00" (rondes × werktijd).
String configShort(SparringConfig c) => '${c.rounds}×${_clock(c.workSeconds)}';

String _clock(int s) => '${s ~/ 60}:${two(s % 60)}';

/// Rusttijd als "1:00".
String restClock(SparringConfig c) => _clock(c.restSeconds);

/// Discipline die past bij een geplande training ('Overig' als niets past).
String disciplineFor(PlannedTraining? p) {
  if (p == null) return kDisciplines.first;
  if (p.kind != TrainingKind.overig) return p.kind.label;
  final t = p.title.toLowerCase();
  for (final d in kDisciplines) {
    if (t.contains(d.toLowerCase())) return d;
  }
  return 'Overig';
}

// ------------------------------------------------------- glucose-helpers

/// Statuskleur bij een glucosewaarde (altijd samen met een label tonen).
KTone zoneTone(double mmol) => switch (zoneFor(mmol)) {
  GlucoseZone.hypo => KTone.danger,
  GlucoseZone.low => KTone.warning,
  GlucoseZone.inTarget => KTone.success,
  GlucoseZone.high => KTone.warning,
};

/// Tekstkleur voor een glucosewaarde in het actieve thema.
Color zoneInk(KineticColors k, double mmol) => toneColors(k, zoneTone(mmol)).$2;

String zoneLabel(double mmol) => switch (zoneFor(mmol)) {
  GlucoseZone.hypo => 'Hypo',
  GlucoseZone.low => 'Laag',
  GlucoseZone.inTarget => 'In bereik',
  GlucoseZone.high => 'Hoog',
};

KTone clearanceTone(ClearanceLevel l) => switch (l) {
  ClearanceLevel.safe => KTone.success,
  ClearanceLevel.caution => KTone.warning,
  ClearanceLevel.danger => KTone.danger,
  ClearanceLevel.unknown => KTone.neutral,
};

IconData clearanceIcon(ClearanceLevel l) => switch (l) {
  ClearanceLevel.safe => Icons.check_circle_outline,
  ClearanceLevel.caution => Icons.warning_amber_rounded,
  ClearanceLevel.danger => Icons.dangerous_outlined,
  ClearanceLevel.unknown => Icons.help_outline,
};

/// Kort label voor een clearance-niveau ("Veilig", "Let op"...).
String clearanceShort(ClearanceLevel l) => switch (l) {
  ClearanceLevel.safe => 'Veilig',
  ClearanceLevel.caution => 'Let op',
  ClearanceLevel.danger => 'Niet starten',
  ClearanceLevel.unknown => 'Meet eerst',
};

/// Start / piek of dip / eind van een glucoseverloop.
class GlucoseTrajectory {
  GlucoseTrajectory._(this.points, this.start, this.end, this.low, this.high);

  /// null als er geen meetpunten zijn.
  static GlucoseTrajectory? of(List<GlucosePoint> points) {
    if (points.isEmpty) return null;
    final values = points.map((p) => p.mmol);
    return GlucoseTrajectory._(
      points,
      points.first.mmol,
      points.last.mmol,
      values.reduce(math.min),
      values.reduce(math.max),
    );
  }

  final List<GlucosePoint> points;
  final double start;
  final double end;
  final double low;
  final double high;

  /// Is de daling groter dan de stijging (dan tonen we "Dip" i.p.v. "Piek").
  bool get dipDominant => (start - low) > (high - start);
  String get middleLabel => dipDominant ? 'Dip' : 'Piek';
  double get middle => dipDominant ? low : high;
  double get delta => end - start;
  double? get inRange => timeInRange(points.map((p) => p.mmol));

  /// Samenvatting van het verloop, met kleur.
  (String, KTone) get status {
    if (low < hypoBelow) return ('Hypo tijdens training', KTone.danger);
    if (start - low >= 1.5) return ('Dip', KTone.warning);
    if (high > targetHigh) return ('Boven doelbereik', KTone.warning);
    if (high - start >= 1.5) return ('Stijging', KTone.warning);
    if (low < targetLow) return ('Laag tijdens training', KTone.warning);
    return ('Stabiel verloop', KTone.success);
  }
}

/// Uitklapbare clearance-melding (titel + uitleg, kleur + icoon).
class ClearanceNote extends StatelessWidget {
  const ClearanceNote({super.key, required this.clearance});
  final MatClearance clearance;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context.k, clearanceTone(clearance.level));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(clearanceIcon(clearance.level), color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clearance.title, style: context.t.bodyStrong.copyWith(color: fg)),
                const SizedBox(height: 2),
                Text(clearance.detail, style: context.t.caption.copyWith(color: context.k.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icoon per techniekgroep.
IconData groupIcon(TechniqueGroup g) => switch (g) {
  TechniqueGroup.throws => Icons.sports_kabaddi,
  TechniqueGroup.striking => Icons.sports_mma,
  TechniqueGroup.submissions => Icons.lock_outline,
  TechniqueGroup.sweeps => Icons.swap_horiz,
  TechniqueGroup.control => Icons.push_pin_outlined,
  TechniqueGroup.defense => Icons.shield_outlined,
  TechniqueGroup.other => Icons.category_outlined,
};

/// Kop boven een blok in een sheet of formulier, met optionele rechtertekst.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.trailing, this.trailingColor});
  final String text;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: context.t.label.copyWith(color: context.k.text)),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: context.t.caption.copyWith(color: trailingColor, fontWeight: trailingColor == null ? null : FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ start-sheet

/// Opent de sheet om een training te starten, eventueel voor een geplande
/// training (discipline, duur en technieken worden dan voorgevuld).
Future<void> showStartTrainingSheet(BuildContext context, {PlannedTraining? planned}) =>
    showKineticSheet<void>(context, builder: (_) => _StartTrainingSheet(planned: planned));

class _StartTrainingSheet extends StatefulWidget {
  const _StartTrainingSheet({this.planned});
  final PlannedTraining? planned;

  @override
  State<_StartTrainingSheet> createState() => _StartTrainingSheetState();
}

class _StartTrainingSheetState extends State<_StartTrainingSheet> {
  late String _discipline;
  final _name = TextEditingController();
  late int _format; // 0..2 = preset, 3 = eigen
  late SparringConfig _custom;
  late List<String> _ids;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final store = KineticScope.read(context);
    final p = widget.planned;
    _discipline = disciplineFor(p);
    if (_discipline == 'Overig' && p != null) _name.text = p.displayTitle == 'Overig' ? '' : p.displayTitle;
    _custom = store.sparringConfig;
    final preset = kFormatPresets.indexWhere((f) => sameConfig(f.config, store.sparringConfig));
    _format = preset >= 0 ? preset : 3;
    if (_discipline == 'Kracht') _format = 2;

    // Technieken: die van de geplande training (eigen id of bibliotheek-id),
    // anders de focus-technieken uit de vault.
    final own = {for (final t in store.techniques) t.id: t};
    final byLibrary = {
      for (final t in store.techniques)
        if (t.libraryId != null) t.libraryId!: t.id,
    };
    final fromPlan = <String>[
      for (final id in p?.techniqueIds ?? const <String>[])
        if (own.containsKey(id)) id else if (byLibrary.containsKey(id)) byLibrary[id]!,
    ];
    _ids = fromPlan.isNotEmpty ? fromPlan.toSet().toList() : store.focusTechniques.map((t) => t.id).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SparringConfig get _config => _format < kFormatPresets.length ? kFormatPresets[_format].config : _custom;

  String get _title {
    if (_discipline != 'Overig') return _discipline;
    final n = _name.text.trim();
    return n.isEmpty ? 'Training' : n;
  }

  void _toggle(String id) => setState(() {
    _ids = _ids.contains(id) ? _ids.where((x) => x != id).toList() : [..._ids, id];
  });

  Future<void> _pickFromVault() async {
    final store = KineticScope.read(context);
    final pick = await showTechniquePicker(
      context,
      title: 'Focus technieken',
      initiallySelected: (e) => e.own != null && _ids.contains(e.own!.id),
    );
    if (pick == null || !mounted) return;
    setState(() => _picking = true);
    final ids = <String>[];
    for (final e in pick.entries) {
      final t = await store.ensureOwnTechnique(e);
      if (t != null) ids.add(t.id);
    }
    if (!mounted) return;
    setState(() {
      _picking = false;
      // Bestaande volgorde aanhouden, nieuwe achteraan.
      _ids = [..._ids.where(ids.contains), ...ids.where((id) => !_ids.contains(id))];
    });
  }

  void _start() {
    final store = KineticScope.read(context);
    final nav = Navigator.of(context);
    if (!store.isSparringActive) {
      store.startSparring(title: _title, config: _config, techniqueIds: _ids);
    }
    nav.pop();
    final rest = store.sparring?.phase == SparringPhase.rest;
    nav.pushNamed(rest ? '/ronde-rust' : '/live-session');
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final p = widget.planned;
    final active = store.isSparringActive;
    final clearance = store.clearanceForNextRound();
    final cfg = _config;

    // Snelle keuzes: gekozen, focus en de eerste andere eigen technieken.
    final byId = {for (final t in store.techniques) t.id: t};
    final candidates = <Technique>[
      for (final id in _ids)
        if (byId[id] != null) byId[id]!,
      ...store.focusTechniques.where((t) => !_ids.contains(t.id)),
      ...store.techniques.where((t) => !_ids.contains(t.id) && !t.isInFocus).take(8),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Training starten', style: context.t.headline),
        const SizedBox(height: 4),
        Text(
          p == null
              ? 'Kies discipline, format en focus. De rondeklok start meteen.'
              : 'Gepland: ${p.displayTitle} • ${hhmm(p.startsAt)}${p.location.trim().isEmpty ? '' : ' • ${p.location.trim()}'}',
          style: context.t.caption,
        ),
        if (active) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: k.primaryTint, borderRadius: BorderRadius.circular(KRadius.md)),
            child: Row(
              children: [
                LiveDot(color: k.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Er loopt al een sessie (${store.sessionTitle}). Rond die eerst af om een nieuwe te starten.',
                    style: context.t.caption.copyWith(color: k.text),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const FormLabel('Discipline'),
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
            decoration: const InputDecoration(labelText: 'Naam van de training (optioneel)', hintText: 'Bijv. Worstelen'),
          ),
        ],
        const SizedBox(height: 20),
        FormLabel('Format', trailing: 'Totaal ±${configMinutes(cfg)} min'),
        Row(
          children: [
            Expanded(child: _formatTile(0)),
            const SizedBox(width: 8),
            Expanded(child: _formatTile(1)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _formatTile(2)),
            const SizedBox(width: 8),
            Expanded(child: _formatTile(3)),
          ],
        ),
        if (_format == 3) ...[
          const SizedBox(height: 6),
          SparringConfigEditor(value: _custom, onChanged: (c) => setState(() => _custom = c), showTitle: false),
        ],
        const SizedBox(height: 20),
        FormLabel(
          'Focus technieken',
          trailing: _ids.isEmpty ? 'Geen gekozen' : '${_ids.length} gekozen',
          trailingColor: _ids.isEmpty ? null : k.accent,
        ),
        if (store.techniques.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Nog geen eigen technieken. Kies er een uit de vault.', style: context.t.caption),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in candidates)
              KChip(
                label: t.name,
                selected: _ids.contains(t.id),
                icon: _ids.contains(t.id) ? Icons.check : null,
                onTap: () => _toggle(t.id),
              ),
            KChip(
              label: _picking ? 'Bezig…' : 'Uit de vault',
              icon: Icons.add,
              selected: false,
              onTap: _picking ? () {} : _pickFromVault,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Deze technieken krijgen live tellers op de mat.', style: context.t.caption),
        const SizedBox(height: 20),
        const FormLabel('Pre-training check'),
        ClearanceNote(clearance: clearance),
        const SizedBox(height: 20),
        BigButton(
          label: active ? 'Terug naar de mat' : 'Start training',
          icon: active ? Icons.sports_mma : Icons.play_arrow_rounded,
          height: 56,
          onPressed: _picking ? null : _start,
        ),
      ],
    );
  }

  Widget _formatTile(int i) {
    final k = context.k;
    final selected = _format == i;
    final custom = i == kFormatPresets.length;
    final label = custom ? 'Eigen' : kFormatPresets[i].label;
    final sub = custom
        ? (_format == 3 ? '${configShort(_custom)} / ${restClock(_custom)}' : 'Rondes instellen')
        : kFormatPresets[i].sub;
    return Material(
      color: selected ? k.primaryTint : k.well,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.md),
        side: BorderSide(color: selected ? k.primary : k.border, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _format = i),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(custom ? Icons.tune : Icons.timer_outlined, size: 20, color: selected ? k.accent : k.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: context.t.subtitle.copyWith(color: selected ? k.accent : k.text)),
                      Text(sub, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 18, color: k.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------- techniekkiezer

/// Resultaat van de techniekkiezer: technieken uit de vault plus (alleen
/// bij [showTechniquePicker] met allowCustom) zelf ingetypte namen.
class TechniquePick {
  const TechniquePick(this.entries, this.customNames);
  final List<VaultEntry> entries;
  final List<String> customNames;
}

/// Meerkeuze uit de hele vault (eigen technieken + bibliotheek) met zoeken.
Future<TechniquePick?> showTechniquePicker(
  BuildContext context, {
  required bool Function(VaultEntry) initiallySelected,
  String title = 'Techniek kiezen',
  bool allowCustom = false,
}) =>
    showKineticSheet<TechniquePick>(
      context,
      scrollable: false,
      builder: (_) => _TechniquePicker(title: title, initiallySelected: initiallySelected, allowCustom: allowCustom),
    );

class _TechniquePicker extends StatefulWidget {
  const _TechniquePicker({required this.title, required this.initiallySelected, required this.allowCustom});
  final String title;
  final bool Function(VaultEntry) initiallySelected;
  final bool allowCustom;

  @override
  State<_TechniquePicker> createState() => _TechniquePickerState();
}

class _TechniquePickerState extends State<_TechniquePicker> {
  final _query = TextEditingController();
  late final List<VaultEntry> _vault;
  late final Set<String> _keys;
  final List<String> _custom = [];

  @override
  void initState() {
    super.initState();
    _vault = KineticScope.read(context).vault;
    _keys = {for (final e in _vault) if (widget.initiallySelected(e)) e.key};
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _done() {
    final entries = [for (final e in _vault) if (_keys.contains(e.key)) e];
    Navigator.of(context).pop(TechniquePick(entries, _custom));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final q = _query.text.trim();
    final all = _vault.where((e) => e.matches(q)).toList()
      // Gekozen technieken bovenaan.
      ..sort((a, b) {
        final sa = _keys.contains(a.key) ? 0 : 1;
        final sb = _keys.contains(b.key) ? 0 : 1;
        return sa.compareTo(sb);
      });
    const limit = 40;
    final shown = all.take(limit).toList();
    final exact = _vault.any((e) => e.name.toLowerCase() == q.toLowerCase()) ||
        _custom.any((c) => c.toLowerCase() == q.toLowerCase());
    final count = _keys.length + _custom.length;
    final maxList = MediaQuery.sizeOf(context).height * 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: context.t.headline),
        const SizedBox(height: 4),
        Text('Eigen technieken en de Kinetic-bibliotheek.', style: context.t.caption),
        const SizedBox(height: 14),
        TextField(
          controller: _query,
          style: context.t.body,
          decoration: InputDecoration(
            hintText: 'Zoek in je vault',
            prefixIcon: Icon(Icons.search, color: k.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        if (_custom.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _custom)
                RemovablePill(label: c, onRemove: () => setState(() => _custom.remove(c))),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxList),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (widget.allowCustom && q.isNotEmpty && !exact)
                  _row(
                    icon: Icons.add,
                    title: '"$q" toevoegen',
                    subtitle: 'Eigen naam, niet uit de vault',
                    selected: false,
                    onTap: () => setState(() {
                      _custom.add(q);
                      _query.clear();
                    }),
                  ),
                for (final e in shown)
                  _row(
                    icon: groupIcon(e.group),
                    title: e.name,
                    subtitle: [if (e.isOwn) 'Eigen', if (e.subtitle.isNotEmpty) e.subtitle].join(' • '),
                    selected: _keys.contains(e.key),
                    onTap: () => setState(() => _keys.contains(e.key) ? _keys.remove(e.key) : _keys.add(e.key)),
                  ),
                if (shown.isEmpty && !(widget.allowCustom && q.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('Geen technieken gevonden.', textAlign: TextAlign.center, style: context.t.caption),
                  ),
                if (all.length > limit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '${all.length - limit} meer: verfijn je zoekopdracht.',
                      textAlign: TextAlign.center,
                      style: context.t.caption,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        BigButton(
          label: count == 0 ? 'Klaar' : 'Klaar • $count gekozen',
          icon: Icons.check,
          onPressed: _done,
        ),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final k = context.k;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KRadius.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              IconTile(icon: icon, size: 36, color: selected ? k.primary : k.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: context.t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? k.accent : k.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill met naam en een verwijderknop (technieken bij Training loggen).
class RemovablePill extends StatelessWidget {
  const RemovablePill({super.key, required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: k.well,
        borderRadius: BorderRadius.circular(KRadius.full),
        border: Border.all(color: k.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Semantics(
            button: true,
            label: '$label verwijderen',
            child: InkResponse(
              onTap: onRemove,
              radius: 20,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.close, size: 16, color: k.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
