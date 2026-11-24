// sheets.dart: bottom sheets: maaltijd/snelle carbs, het centrale
// '+'-actiemenu, vingerprik-kalibratie en de ronde-instellingen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';

double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

Future<void> showMealSheet(BuildContext context, {MealContext? initialContext}) {
  final store = KineticScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => KineticScope(
      store: store,
      child: MealSheet(initialContext: initialContext),
    ),
  );
}

class MealSheet extends StatefulWidget {
  const MealSheet({super.key, this.initialContext});
  final MealContext? initialContext;

  @override
  State<MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends State<MealSheet> {
  final _name = TextEditingController();
  final _carbs = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _insulin = TextEditingController();
  late MealContext _context;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final store = KineticScope.read(context);
    _context = widget.initialContext ??
        (store.isSparringActive ? MealContext.acute : MealContext.recovery);
    for (final c in [_carbs, _insulin]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _carbs, _protein, _fat, _insulin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final carbs = parseNum(_carbs.text);
    final protein = parseNum(_protein.text);
    final fat = parseNum(_fat.text);
    final insulin = parseNum(_insulin.text);
    if (carbs == null && protein == null && fat == null) {
      setState(() => _error = 'Vul minstens één macro in.');
      return;
    }
    if ([carbs, protein, fat, insulin].any((v) => v != null && (v < 0 || v > 1000))) {
      setState(() => _error = 'Controleer de getallen.');
      return;
    }
    if (insulin != null && insulin > 50) {
      setState(() => _error = 'Meer dan 50 E insuline? Controleer de invoer.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final store = KineticScope.read(context);
    final name = _name.text.trim().isEmpty ? 'Maaltijd' : _name.text.trim();
    final saved = await store.logFood(
      description: name,
      carbs: carbs,
      protein: protein,
      fat: fat,
      context: _context,
      insulinUnits: insulin,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _saving = false;
        _error = 'Opslaan mislukt. Controleer je verbinding.';
      });
      return;
    }
    showToast(context, '$name opgeslagen in je dagoverzicht');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final carbs = parseNum(_carbs.text) ?? 0;
    final insulin = parseNum(_insulin.text) ?? 0;
    final impact = predictGlucoseImpact(
      carbs: carbs,
      context: _context,
      insulinUnits: insulin,
      correctionFactor: store.profile?.correctionFactor ?? 2.0,
    );
    final r = store.reading;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Maaltijd of snelle carbs', style: KText.title),
            const SizedBox(height: 4),
            Text('Wordt opgeslagen in Supabase en meteen in je macrobarometer verwerkt.', style: KText.caption),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              style: KText.body,
              decoration: const InputDecoration(
                labelText: 'Maaltijd / brandstof',
                hintText: 'Banaan + Dextrose Gel',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _macroField(_carbs, 'Koolh. (g)', KColor.warning)),
                const SizedBox(width: 8),
                Expanded(child: _macroField(_protein, 'Eiwit (g)', KColor.blue)),
                const SizedBox(width: 8),
                Expanded(child: _macroField(_fat, 'Vet (g)', KColor.purple)),
              ],
            ),
            const SizedBox(height: 8),
            _macroField(_insulin, 'Insuline (E, optioneel)', KColor.teal),
            const SizedBox(height: 18),
            const Eyebrow('Context'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in MealContext.values)
                  KChip(label: c.label, selected: _context == c, onTap: () => setState(() => _context = c)),
              ],
            ),
            const SizedBox(height: 18),
            KCard(
              color: KColor.surface,
              borderColor: KColor.teal.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Verwachte glucose impact', color: KColor.tealLight, icon: Icons.insights),
                  const SizedBox(height: 8),
                  Text(
                    carbs <= 0 ? 'Vul koolhydraten in' : impact.format(),
                    style: KText.metricSmall.copyWith(
                      color: carbs <= 0 ? KColor.textMuted : (impact.high > 3 ? KColor.warning : KColor.tealLight),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Indicatief, binnen ~60-90 min. Geen medisch advies.', style: KText.caption),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      KBadge('Dexcom G7 ${_context.tag}', color: KColor.teal, dot: false),
                      KBadge(
                        r == null || r.isStale
                            ? 'Geen actuele CGM-waarde'
                            : 'Annotatie ${hhmm(store.now())} · ${r.mmol.toStringAsFixed(1)} ${trendArrow(r.trend)}',
                        color: r == null || r.isStale ? KColor.textMuted : glucoseColor(r.mmol),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: KText.caption.copyWith(color: KColor.danger)),
            ],
            const SizedBox(height: 18),
            BigButton(
              label: _saving ? 'Opslaan…' : 'Opslaan in Dagoverzicht',
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroField(TextEditingController c, String label, Color accent) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: KText.subtitle.copyWith(color: accent),
      decoration: InputDecoration(labelText: label),
    );
  }
}

// ------------------------------------------------------------------ '+'

Future<void> showQuickActions(BuildContext context) {
  final store = KineticScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      Widget tile(String title, String sub, IconData icon, Color color, VoidCallback onTap) {
        return KCard(
          onTap: () {
            Navigator.of(sheetContext).pop();
            onTap();
          },
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(KRadius.md),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: KText.subtitle),
                    const SizedBox(height: 2),
                    Text(sub, style: KText.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: KColor.textMuted),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Snelle actie', style: KText.title),
            const SizedBox(height: 14),
            tile(
              store.isSparringActive ? 'Terug naar sparring' : 'Start Sparring',
              store.isSparringActive ? 'Sessie loopt' : store.sparringConfig.summary,
              Icons.sports_mma,
              KColor.teal,
              () => openLiveSession(context),
            ),
            const SizedBox(height: 10),
            tile('Snelle Carbs', 'Maaltijd of dextrose loggen', Icons.bolt, KColor.warning, store.requestMealSheet),
            const SizedBox(height: 10),
            tile('Inwegen', 'Gewicht registreren & fight prep', Icons.monitor_weight_outlined, KColor.blue,
                () => Navigator.of(context).pushNamed('/competitions')),
            const SizedBox(height: 10),
            tile('Sensor Kalibratie', 'Vingerprik vergelijken met je CGM', Icons.water_drop_outlined, KColor.purple,
                () => showFingerstickSheet(context)),
          ],
        ),
      );
    },
  );
}

/// Start (of hervat) de live sessie en opent het juiste scherm.
void openLiveSession(BuildContext context) {
  final store = KineticScope.read(context);
  if (!store.isSparringActive) store.startSparring();
  final rest = store.sparring?.phase == SparringPhase.rest;
  Navigator.of(context).pushNamed(rest ? '/ronde-rust' : '/live-session');
}

// ------------------------------------------------------------- vingerprik

Future<void> showFingerstickSheet(BuildContext context) {
  final store = KineticScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => KineticScope(store: store, child: const _FingerstickSheet()),
  );
}

class _FingerstickSheet extends StatefulWidget {
  const _FingerstickSheet();

  @override
  State<_FingerstickSheet> createState() => _FingerstickSheetState();
}

class _FingerstickSheetState extends State<_FingerstickSheet> {
  final _value = TextEditingController();
  bool _saving = false;
  String? _result;
  Color _resultColor = KColor.textSecondary;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseNum(_value.text);
    if (v == null || v < 1 || v > 33) {
      setState(() => _result = 'Vul een waarde tussen 1 en 33 mmol/L in.');
      return;
    }
    setState(() => _saving = true);
    final store = KineticScope.read(context);
    double? diff;
    try {
      diff = await store.addFingerstick(v);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = 'Opslaan mislukt.';
        _resultColor = KColor.danger;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (diff == null) {
        _result = 'Opgeslagen. Geen actuele CGM-waarde om mee te vergelijken.';
        _resultColor = KColor.textSecondary;
      } else {
        final pct = (diff.abs() / v * 100).round();
        // Dexcom-vuistregel: binnen 20% (of 1.1 mmol/L onder 5.6) is normaal.
        final off = v < 5.6 ? diff.abs() > 1.1 : pct > 20;
        _result = off
            ? 'Verschil ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} mmol/L ($pct%). Groot verschil: kalibreer in de Dexcom G7-app (vochtverschuivingen bij gewichtscut beïnvloeden de sensor).'
            : 'Verschil ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} mmol/L ($pct%). Sensor zit binnen de marge, geen kalibratie nodig.';
        _resultColor = off ? KColor.warning : KColor.success;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final r = store.reading;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sensor kalibratie-check', style: KText.title),
            const SizedBox(height: 4),
            Text(
              'Vergelijk een vingerprik met je Dexcom G7. De waarde wordt opgeslagen in je glucoselog.',
              style: KText.caption,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Eyebrow('CGM nu'),
                const SizedBox(width: 10),
                GlucoseReadout(reading: r, size: 22),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: KText.metricSmall,
              decoration: const InputDecoration(labelText: 'Vingerprik (mmol/L)'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!, style: KText.body.copyWith(color: _resultColor)),
            ],
            const SizedBox(height: 16),
            BigButton(
              label: _saving ? 'Opslaan…' : 'Vergelijken & opslaan',
              icon: Icons.water_drop,
              color: KColor.purple,
              foreground: KColor.text,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------- rondes instellen

Future<void> showSparringConfigSheet(BuildContext context) {
  final store = KineticScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => KineticScope(store: store, child: const _SparringConfigSheet()),
  );
}

class _SparringConfigSheet extends StatelessWidget {
  const _SparringConfigSheet();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final c = store.sparringConfig;
    void set({int? rounds, int? work, int? rest}) => store.setSparringConfig(
      SparringConfig(
        rounds: (rounds ?? c.rounds).clamp(1, 15),
        workSeconds: (work ?? c.workSeconds).clamp(30, 900),
        restSeconds: (rest ?? c.restSeconds).clamp(15, 300),
      ),
    );
    Widget row(String label, String value, VoidCallback minus, VoidCallback plus) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: KText.subtitle)),
          _StepButton(icon: Icons.remove, onTap: minus),
          SizedBox(width: 84, child: Text(value, textAlign: TextAlign.center, style: KText.metricSmall)),
          _StepButton(icon: Icons.add, onTap: plus),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rondes instellen', style: KText.title),
          const SizedBox(height: 12),
          row('Rondes', '${c.rounds}', () => set(rounds: c.rounds - 1), () => set(rounds: c.rounds + 1)),
          row('Werk', mmss(c.workSeconds), () => set(work: c.workSeconds - 30), () => set(work: c.workSeconds + 30)),
          row('Rust', mmss(c.restSeconds), () => set(rest: c.restSeconds - 15), () => set(rest: c.restSeconds + 15)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: KColor.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
        child: InkWell(
          borderRadius: BorderRadius.circular(KRadius.md),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Icon(icon, color: KColor.text),
        ),
      ),
    );
  }
}
