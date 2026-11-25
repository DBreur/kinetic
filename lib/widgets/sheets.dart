// sheets.dart: bottom sheets: maaltijd/snelle carbs, het centrale
// '+'-actiemenu, vingerprik-kalibratie en de ronde-instellingen. Allemaal via
// showKineticSheet, zodat de onderkant nooit onder de systeemknoppen valt.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/bolus_calculator.dart';
import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../core/preset_text.dart';
import '../core/sparring_timer.dart';
import '../models/food_log_entry.dart';
import '../models/food_preset.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import 'food_preset_widgets.dart';
import 'kinetic_widgets.dart';
import 'start_training_sheet.dart';

double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Nieuwe maaltijd, of met [existing] een gelogde maaltijd aanpassen.
Future<void> showMealSheet(BuildContext context, {MealContext? initialContext, FoodLogEntry? existing}) =>
    showKineticSheet<void>(context, builder: (_) => MealSheet(initialContext: initialContext, existing: existing));

class MealSheet extends StatefulWidget {
  const MealSheet({super.key, this.initialContext, this.existing});
  final MealContext? initialContext;
  final FoodLogEntry? existing;

  @override
  State<MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends State<MealSheet> {
  final _name = TextEditingController();
  final _carbs = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _insulin = TextEditingController();

  // Bolus-calculator: glucose nu + de drie vakjes (voeding, correctie, totaal).
  final _mmol = TextEditingController();
  final _insulinFood = TextEditingController();
  final _insulinCorrection = TextEditingController();
  late MealContext _context;
  bool _saving = false;
  String? _error;

  /// Preset-enkelvoud → aantal (−/+).
  Map<String, int> _presetCounts = {};

  /// −/+ op een preset: werkt de omschrijving en de koolhydraten bij.
  Map<String, int> _presetDelta(FoodPreset preset, int delta) {
    final r = applyPresetChange(text: _name.text, counts: _presetCounts, preset: preset, delta: delta);
    final carbs = ((parseNum(_carbs.text) ?? 0) + r.carbsDelta).clamp(0.0, 2000.0);
    setState(() {
      _presetCounts = r.counts;
      _name.text = r.text;
      _carbs.text = carbs > 0 ? grams(carbs) : '';
    });
    return r.counts;
  }

  @override
  void initState() {
    super.initState();
    final store = KineticScope.read(context);
    final e = widget.existing;
    _at = e?.at ?? store.now();
    _context = e?.context ??
        widget.initialContext ??
        (store.isTrainingActive ? MealContext.acute : MealContext.recovery);
    if (e != null) {
      String n(double? v) => v == null ? '' : grams(v);
      String u(double? v) => v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
      _name.text = e.description;
      _carbs.text = n(e.carbs);
      _protein.text = n(e.protein);
      _fat.text = n(e.fat);
      _presetCounts = Map.of(e.presetCounts);
      _mmol.text = e.mmol == null ? '' : e.mmol!.toStringAsFixed(1);
      _insulin.text = u(e.insulinUnits);
      if (e.insulinFoodUnits != null || e.insulinCorrectionUnits != null) {
        _insulinFood.text = u(e.insulinFoodUnits ?? 0);
        _insulinCorrection.text = u(e.insulinCorrectionUnits ?? 0);
      } else if (e.insulinUnits != null) {
        // Zonder opsplitsing gelogd: alles als voeding, geen extra correctie.
        _insulinFood.text = u(e.insulinUnits);
        _insulinCorrection.text = '0';
      } else if (store.bolusCalculatorActive) {
        // Zonder insuline gelogd: niet stilletjes een voorstel toevoegen.
        _insulinFood.text = '0';
        _insulinCorrection.text = '0';
      }
    } else {
      final r = store.reading;
      if (r != null && !r.isStaleAt(store.now())) _mmol.text = r.mmol.toStringAsFixed(1);
    }
    for (final c in [_carbs, _insulin, _mmol, _insulinFood, _insulinCorrection]) {
      c.addListener(() => setState(() {}));
    }
  }

  /// Tijdstip van de maaltijd (bij aanpassen te wijzigen).
  late DateTime _at;

  bool get _editing => widget.existing != null;

  bool get _useBolus => KineticScope.read(context).bolusCalculatorActive;

  BolusSuggestion get _suggestion =>
      KineticScope.read(context).bolusSuggestion(carbs: parseNum(_carbs.text), mmol: parseNum(_mmol.text), at: _at);

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      helpText: 'Tijdstip',
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    final store = KineticScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verwijderen?'),
        content: Text('"${e.description.isEmpty ? 'Maaltijd' : e.description}" wordt uit je logboek verwijderd.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.k.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final deleted = await store.deleteFood(e);
    showToastOn(messenger, deleted ? 'Verwijderd' : 'Verwijderen mislukt', error: !deleted);
  }

  /// Eigen invoer (afgerond op 0,5 E), anders het voorstel.
  double? _units(TextEditingController c, double? suggested) {
    final v = parseNum(c.text);
    return v == null ? suggested : roundToHalfUnit(v);
  }

  double? get _foodUnits => _units(_insulinFood, _suggestion.foodDose);
  double? get _correctionUnits => _units(_insulinCorrection, _suggestion.correctionDose);

  double? get _totalUnits {
    if (!_useBolus) return parseNum(_insulin.text);
    final f = _foodUnits;
    final c = _correctionUnits;
    if (f == null && c == null) return null;
    return (f ?? 0) + (c ?? 0);
  }

  @override
  void dispose() {
    for (final c in [_name, _carbs, _protein, _fat, _insulin, _mmol, _insulinFood, _insulinCorrection]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final carbs = parseNum(_carbs.text);
    final protein = parseNum(_protein.text);
    final fat = parseNum(_fat.text);
    final insulin = _totalUnits;
    final mmol = parseNum(_mmol.text);
    if (mmol != null && (mmol < 1 || mmol > 35)) {
      setState(() => _error = 'Glucose moet tussen 1 en 35 mmol/L liggen.');
      return;
    }
    if (carbs == null && protein == null && fat == null && insulin == null) {
      setState(() => _error = 'Vul koolhydraten, een macro of insuline in.');
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
    final name = _name.text.trim().isEmpty
        ? (carbs == null && protein == null && fat == null ? 'Correctie' : 'Maaltijd')
        : _name.text.trim();
    final existing = widget.existing;
    if (existing != null) {
      final ok = await store.updateFood(
        FoodLogEntry(
          id: existing.id,
          at: _at,
          description: name,
          carbs: carbs,
          protein: protein,
          fat: fat,
          context: _context,
          mmol: mmol,
          insulinUnits: insulin,
          insulinTiming: existing.insulinTiming,
          insulinFoodUnits: _useBolus ? _foodUnits : null,
          insulinCorrectionUnits: _useBolus ? _correctionUnits : null,
          insulinNote: existing.insulinNote,
          insulinWaitMinutes: existing.insulinWaitMinutes,
          presetCounts: _presetCounts,
        ),
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _saving = false;
          _error = 'Opslaan mislukt. Controleer je verbinding.';
        });
        return;
      }
      showToast(context, '$name aangepast');
      Navigator.of(context).pop();
      return;
    }
    final saved = await store.logFood(
      description: name,
      carbs: carbs,
      protein: protein,
      fat: fat,
      context: _context,
      insulinUnits: insulin,
      insulinFoodUnits: _useBolus ? _foodUnits : null,
      insulinCorrectionUnits: _useBolus ? _correctionUnits : null,
      mmolOverride: _useBolus ? mmol : null,
      presetCounts: _presetCounts,
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
    final k = context.k;
    final carbs = parseNum(_carbs.text) ?? 0;
    final insulin = _totalUnits ?? 0;
    final impact = predictGlucoseImpact(
      carbs: carbs,
      context: _context,
      insulinUnits: insulin,
      correctionFactor: store.profile?.correctionFactor ?? 2.0,
    );
    final r = store.reading;
    final fresh = r != null && !r.isStale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_editing ? 'Maaltijd aanpassen' : 'Maaltijd of correctie', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Wordt opgeslagen in Supabase en meteen in je macrobarometer verwerkt.', style: context.t.caption),
        if (_editing) ...[
          const SizedBox(height: 12),
          KWell(
            onTap: _pickTime,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.schedule, color: k.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Tijdstip', style: context.t.body)),
                Text(hhmm(_at), style: context.t.subtitle.copyWith(color: k.accent)),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 18, color: k.textMuted),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        PresetQuickPicker(counts: _presetCounts, onDelta: _presetDelta),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Maaltijd / brandstof', hintText: 'Banaan + Dextrose Gel'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _macroField(_carbs, 'Koolh. (g)', k.warning)),
            const SizedBox(width: 8),
            Expanded(child: _macroField(_protein, 'Eiwit (g)', k.blue)),
            const SizedBox(width: 8),
            Expanded(child: _macroField(_fat, 'Vet (g)', k.purple)),
          ],
        ),
        const SizedBox(height: 8),
        if (store.bolusCalculatorActive) _bolusBlock(store) else _macroField(_insulin, 'Insuline (E, optioneel)', k.accent),
        const SizedBox(height: 20),
        const Eyebrow('Context'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in MealContext.values)
              KChip(label: c.label, selected: _context == c, onTap: () => setState(() => _context = c)),
          ],
        ),
        const SizedBox(height: 20),
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Verwachte glucose impact', icon: Icons.insights, color: k.accent),
              const SizedBox(height: 10),
              Text(
                carbs <= 0 ? 'Vul koolhydraten in' : impact.format(),
                style: context.t.metricMd.copyWith(
                  color: carbs <= 0 ? k.textMuted : (impact.high > 3 ? k.warning : k.accent),
                ),
              ),
              const SizedBox(height: 6),
              Text('Indicatief, binnen ~60-90 min. Geen medisch advies.', style: context.t.caption),
              const SizedBox(height: 12),
              KWell(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.sensors, size: 18, color: k.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fresh
                            ? 'Dexcom G7 ${_context.tag} • ${hhmm(store.now())} • ${r.mmol.toStringAsFixed(1)} ${trendArrow(r.trend)}'
                            : 'Dexcom G7 ${_context.tag} • geen actuele CGM-waarde',
                        style: context.t.caption.copyWith(color: k.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: context.t.caption.copyWith(color: k.danger)),
        ],
        const SizedBox(height: 20),
        BigButton(
          label: _saving ? 'Opslaan…' : (_editing ? 'Wijzigingen opslaan' : 'Opslaan in Dagoverzicht'),
          icon: Icons.check_circle_outline,
          height: 56,
          onPressed: _saving ? null : _save,
        ),
        if (_editing) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
        ],
      ],
    );
  }

  /// Bolus-calculator: glucose nu, het actieve tijdvak en de drie vakjes.
  /// Leeg laten = het voorstel (grijze hint) wordt opgeslagen.
  Widget _bolusBlock(KineticStore store) {
    final k = context.k;
    final p = store.profile!;
    final s = _suggestion;
    final night = isNight(store.now(), p.correctionNightStart, p.correctionNightEnd);
    final target = night ? p.correctionTargetNight : p.correctionTargetDay;
    String fmt(double? v) => v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
    final total = _totalUnits;
    return KWell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: k.accent),
              const SizedBox(width: 6),
              Expanded(child: Text('Bolus-calculator', style: context.t.bodyStrong)),
              if (s.period != null)
                Flexible(
                  child: Text(
                    '${s.period!.label.isEmpty ? s.period!.startTime : s.period!.label} • 1 E : ${fmt(s.period!.carbRatio)} g',
                    style: context.t.caption.copyWith(color: k.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _macroField(_mmol, 'Glucose nu (mmol/L)', k.text),
          const SizedBox(height: 4),
          Text(
            'Correctie naar ${fmt(target)} mmol/L (${night ? 'nacht' : 'dag'}) • ${fmt(p.correctionFactor)} mmol/L per E',
            style: context.t.caption,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _unitField(_insulinFood, 'Voeding (E)', fmt(s.foodDose))),
              const SizedBox(width: 8),
              Expanded(child: _unitField(_insulinCorrection, 'Correctie (E)', fmt(s.correctionDose))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Totaal ${fmt(total)} eenheden',
                  excludeSemantics: true,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: k.primaryTint,
                      borderRadius: BorderRadius.circular(KRadius.md),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text('Totaal te spuiten', style: context.t.bodyStrong.copyWith(color: k.accent))),
                        Text(
                          total == null ? '—' : fmt(total),
                          key: const ValueKey('bolus-total'),
                          style: context.t.metricSm.copyWith(color: k.accent),
                        ),
                        Text(' E', style: context.t.unit.copyWith(color: k.accent)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Leeg = voorstel. Afgerond op 0,5 E. Controleer altijd zelf; geen medisch advies.', style: context.t.caption.copyWith(color: k.textMuted)),
        ],
      ),
    );
  }

  Widget _unitField(TextEditingController c, String label, String suggestion) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    style: context.t.subtitle.copyWith(color: context.k.accent, fontFeatures: const [FontFeature.tabularFigures()]),
    decoration: InputDecoration(
      labelText: label,
      hintText: suggestion,
      floatingLabelBehavior: suggestion.isEmpty ? null : FloatingLabelBehavior.always,
    ),
  );

  Widget _macroField(TextEditingController c, String label, Color accent) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: context.t.subtitle.copyWith(color: accent, fontFeatures: const [FontFeature.tabularFigures()]),
      decoration: InputDecoration(labelText: label),
    );
  }
}

// ------------------------------------------------------------------ '+'

Future<void> showQuickActions(BuildContext context) {
  final store = KineticScope.read(context);
  return showKineticSheet<void>(
    context,
    builder: (sheetContext) {
      final k = sheetContext.k;
      Widget tile(String title, String sub, IconData icon, Color color, VoidCallback onTap) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: KCard(
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconTile(icon: icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: sheetContext.t.subtitle),
                      const SizedBox(height: 2),
                      Text(sub, style: sheetContext.t.caption),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: k.textMuted),
              ],
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Snelle actie', style: sheetContext.t.headline),
          const SizedBox(height: 16),
          tile(
            store.isTrainingActive ? 'Terug naar de training' : 'Start training',
            store.isTrainingActive ? 'Sessie loopt' : 'Discipline en begin- en eindtijd kiezen',
            Icons.sports_martial_arts,
            k.primary,
            () => openLiveSession(context),
          ),
          tile('Maaltijd of correctie', 'Koolhydraten en/of insuline loggen', Icons.restaurant, k.warning, store.requestMealSheet),
          tile('Inwegen', 'Gewicht registreren & fight prep', Icons.monitor_weight_outlined, k.blue,
              () => Navigator.of(context).pushNamed('/competitions')),
          tile('Sensor Kalibratie', 'Vingerprik vergelijken met je CGM', Icons.water_drop_outlined, k.purple,
              () => showFingerstickSheet(context)),
        ],
      );
    },
  );
}

/// Opent de lopende training (of de start-sheet als er geen loopt).
void openLiveSession(BuildContext context) {
  final store = KineticScope.read(context);
  if (!store.isTrainingActive) {
    showStartTrainingSheet(context);
    return;
  }
  final rest = store.sparring?.phase == SparringPhase.rest;
  Navigator.of(context).pushNamed(rest ? '/ronde-rust' : '/live-session');
}

// ------------------------------------------------------------- vingerprik

Future<void> showFingerstickSheet(BuildContext context) =>
    showKineticSheet<void>(context, builder: (_) => const _FingerstickSheet());

class _FingerstickSheet extends StatefulWidget {
  const _FingerstickSheet();

  @override
  State<_FingerstickSheet> createState() => _FingerstickSheetState();
}

class _FingerstickSheetState extends State<_FingerstickSheet> {
  final _value = TextEditingController();
  bool _saving = false;
  String? _result;
  KTone _tone = KTone.neutral;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseNum(_value.text);
    if (v == null || v < 1 || v > 33) {
      setState(() {
        _result = 'Vul een waarde tussen 1 en 33 mmol/L in.';
        _tone = KTone.danger;
      });
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
        _tone = KTone.danger;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (diff == null) {
        _result = 'Opgeslagen. Geen actuele CGM-waarde om mee te vergelijken.';
        _tone = KTone.neutral;
      } else {
        final pct = (diff.abs() / v * 100).round();
        // Dexcom-vuistregel: binnen 20% (of 1.1 mmol/L onder 5.6) is normaal.
        final off = v < 5.6 ? diff.abs() > 1.1 : pct > 20;
        final d = '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} mmol/L ($pct%)';
        _result = off
            ? 'Verschil $d. Groot verschil: kalibreer in de Dexcom G7-app (vochtverschuivingen bij een gewichtscut beïnvloeden de sensor).'
            : 'Verschil $d. Sensor zit binnen de marge, geen kalibratie nodig.';
        _tone = off ? KTone.warning : KTone.success;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final (bg, fg) = toneColors(context.k, _tone);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sensor kalibratie-check', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Vergelijk een vingerprik met je Dexcom G7. De waarde wordt opgeslagen in je glucoselog.', style: context.t.caption),
        const SizedBox(height: 16),
        KWell(
          child: Row(
            children: [
              Text('CGM nu', style: context.t.caption),
              const Spacer(),
              GlucoseReadout(reading: store.reading, size: 24),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: context.t.metricSm,
          decoration: const InputDecoration(labelText: 'Vingerprik (mmol/L)'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KRadius.md)),
            child: Text(_result!, style: context.t.body.copyWith(color: fg)),
          ),
        ],
        const SizedBox(height: 16),
        BigButton(
          label: _saving ? 'Opslaan…' : 'Vergelijken & opslaan',
          icon: Icons.water_drop,
          height: 56,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

// --------------------------------------------------------- rondes instellen

Future<void> showSparringConfigSheet(BuildContext context) =>
    showKineticSheet<void>(context, builder: (_) => const SparringConfigEditor());

/// Rondes / werk / rust instellen. Zonder [onChanged] past hij de
/// standaardinstelling in de store aan.
class SparringConfigEditor extends StatelessWidget {
  const SparringConfigEditor({super.key, this.value, this.onChanged, this.showTitle = true});
  final SparringConfig? value;
  final ValueChanged<SparringConfig>? onChanged;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final c = value ?? store.sparringConfig;
    void set({int? rounds, int? work, int? rest}) {
      final next = SparringConfig(
        rounds: (rounds ?? c.rounds).clamp(1, 15),
        workSeconds: (work ?? c.workSeconds).clamp(30, 900),
        restSeconds: (rest ?? c.restSeconds).clamp(15, 300),
      );
      if (onChanged != null) {
        onChanged!(next);
      } else {
        store.setSparringConfig(next);
      }
    }

    Widget row(String label, String v, VoidCallback minus, VoidCallback plus) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: KWell(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.t.bodyStrong)),
            StepButton(icon: Icons.remove, onTap: minus),
            SizedBox(width: 84, child: Text(v, textAlign: TextAlign.center, style: context.t.metricSm)),
            StepButton(icon: Icons.add, onTap: plus),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[Text('Rondes instellen', style: context.t.headline), const SizedBox(height: 12)],
        row('Rondes', '${c.rounds}', () => set(rounds: c.rounds - 1), () => set(rounds: c.rounds + 1)),
        row('Werk', mmss(c.workSeconds), () => set(work: c.workSeconds - 30), () => set(work: c.workSeconds + 30)),
        row('Rust', mmss(c.restSeconds), () => set(rest: c.restSeconds - 15), () => set(rest: c.restSeconds + 15)),
      ],
    );
  }
}

/// Vierkante +/- knop (52px, handschoenvriendelijk).
class StepButton extends StatelessWidget {
  const StepButton({super.key, required this.icon, required this.onTap, this.size = 52});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: k.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.md),
          side: BorderSide(color: k.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Icon(icon, color: k.text),
        ),
      ),
    );
  }
}
