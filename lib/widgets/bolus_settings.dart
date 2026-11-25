// bolus_settings.dart: instellingen van de bolus-calculator (Instellingen):
// aan/uit, tijdvakken met starttijd en KH-ratio (g per E), correctiefactor,
// streefwaarde overdag en 's nachts en het nachtvenster. Alles wordt meteen
// in `profiles` opgeslagen (kolommen bestonden al).

import 'package:material_ui/material_ui.dart';

import '../core/bolus_calculator.dart';
import '../models/bolus_period.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'sheets.dart';
import 'training_sheets.dart';

String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _parse(String hhmm) {
  final m = minutesOfDay(hhmm);
  return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
}

Future<String?> _pickTime(BuildContext context, String current, String help) async {
  final t = await showTimePicker(
    context: context,
    initialTime: _parse(current),
    helpText: help,
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  return t == null ? null : _hhmm(t);
}

class BolusSettingsCard extends StatelessWidget {
  const BolusSettingsCard({super.key});

  Future<void> _save(BuildContext context, Future<bool> Function() op) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await op()) showToastOn(messenger, 'Opslaan mislukt. Controleer je verbinding.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final p = store.profile;
    if (p == null) return const SizedBox.shrink();
    final periods = [...p.bolusPeriods]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final active = activePeriod(periods, store.now());

    Future<void> editPeriod({int? index}) async {
      final result = await showKineticSheet<(BolusPeriod?, bool)>(
        context,
        builder: (_) => _PeriodSheet(existing: index == null ? null : periods[index]),
      );
      if (result == null || !context.mounted) return;
      final (period, delete) = result;
      final next = [...periods];
      if (index != null) next.removeAt(index);
      if (!delete && period != null) next.add(period);
      await _save(context, () => store.updateBolusSettings(periods: next));
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Bolus-calculator', style: context.t.bodyStrong),
            subtitle: Text(
              'Rekent bij een maaltijd voeding- en correctie-insuline uit (drie vakjes: voeding, correctie, totaal).',
              style: context.t.caption,
            ),
            value: p.bolusCalculatorEnabled,
            onChanged: (v) => _save(context, () => store.updateBolusSettings(enabled: v)),
          ),
          if (p.bolusCalculatorEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Tijdvakken & KH-ratio', style: context.t.bodyStrong)),
                TextButton.icon(
                  onPressed: () => editPeriod(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tijdvak'),
                ),
              ],
            ),
            Text(
              'Een tijdvak loopt van zijn starttijd tot de start van het volgende. Ratio = gram koolhydraten per 1 E.',
              style: context.t.caption,
            ),
            const SizedBox(height: 10),
            if (periods.isEmpty)
              KWell(
                child: Text(
                  'Nog geen tijdvakken. Voeg er minstens één toe (bv. Ochtend 06:00, 1 E : 8 g); zonder tijdvak blijft het gewone insulineveld staan.',
                  style: context.t.caption.copyWith(color: k.warningInk),
                ),
              ),
            for (final (i, x) in periods.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: KWell(
                  onTap: () => editPeriod(index: i),
                  borderColor: identical(x, active) ? k.accent : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Text(x.startTime, style: context.t.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          x.label.isEmpty ? 'Tijdvak ${i + 1}' : x.label,
                          style: context.t.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (identical(x, active)) ...[
                        const KPill('Nu', tone: KTone.primary, dense: true),
                        const SizedBox(width: 8),
                      ],
                      Text('1 E : ${_num(x.carbRatio)} g', style: context.t.bodyStrong.copyWith(color: k.accent)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_outlined, size: 18, color: k.textMuted),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Divider(height: 1, color: k.border),
            const SizedBox(height: 12),
            _Row(
              title: 'Correctiefactor',
              sub: 'mmol/L daling per 1 E',
              child: ValueStepper(
                value: _num(p.correctionFactor),
                semanticsLabel: 'Correctiefactor',
                onMinus: p.correctionFactor <= 0.5
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(correctionFactor: p.correctionFactor - 0.1 < 0.5 ? 0.5 : double.parse((p.correctionFactor - 0.1).toStringAsFixed(1)))),
                onPlus: p.correctionFactor >= 10
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(correctionFactor: double.parse((p.correctionFactor + 0.1).toStringAsFixed(1)))),
              ),
            ),
            const SizedBox(height: 10),
            _Row(
              title: 'Streefwaarde overdag',
              sub: 'Corrigeren naar (mmol/L)',
              child: ValueStepper(
                value: _num(p.correctionTargetDay),
                semanticsLabel: 'Streefwaarde overdag',
                onMinus: p.correctionTargetDay <= 4.5
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(targetDay: p.correctionTargetDay - 0.5)),
                onPlus: p.correctionTargetDay >= 15
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(targetDay: p.correctionTargetDay + 0.5)),
              ),
            ),
            const SizedBox(height: 10),
            _Row(
              title: "Streefwaarde 's nachts",
              sub: 'Corrigeren naar (mmol/L)',
              child: ValueStepper(
                value: _num(p.correctionTargetNight),
                semanticsLabel: "Streefwaarde 's nachts",
                onMinus: p.correctionTargetNight <= 4.5
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(targetNight: p.correctionTargetNight - 0.5)),
                onPlus: p.correctionTargetNight >= 15
                    ? null
                    : () => _save(context, () => store.updateBolusSettings(targetNight: p.correctionTargetNight + 0.5)),
              ),
            ),
            const SizedBox(height: 10),
            _Row(
              title: 'Nachtvenster',
              sub: 'Wanneer de nacht-streefwaarde geldt',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final v = await _pickTime(context, p.correctionNightStart, 'Nacht begint');
                      if (v != null && context.mounted) await _save(context, () => store.updateBolusSettings(nightStart: v));
                    },
                    child: Text(p.correctionNightStart),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('–', style: context.t.body)),
                  OutlinedButton(
                    onPressed: () async {
                      final v = await _pickTime(context, p.correctionNightEnd, 'Nacht eindigt');
                      if (v != null && context.mounted) await _save(context, () => store.updateBolusSettings(nightEnd: v));
                    },
                    child: Text(p.correctionNightEnd),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Het voorstel wordt afgerond op 0,5 E en is nooit een negatieve correctie. Controleer altijd zelf; geen medisch advies.',
              style: context.t.caption.copyWith(color: k.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.sub, required this.child});
  final String title;
  final String sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.t.bodyStrong),
              Text(sub, style: context.t.caption),
            ],
          ),
        ),
        const SizedBox(width: 8),
        child,
      ],
    );
  }
}

/// Tijdvak toevoegen/aanpassen: naam, starttijd en ratio. Geeft
/// (tijdvak, verwijderen) terug.
class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({this.existing});
  final BolusPeriod? existing;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _ratio = TextEditingController(text: widget.existing == null ? '' : _num(widget.existing!.carbRatio));
  late String _start = widget.existing?.startTime ?? '06:00';
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _ratio.dispose();
    super.dispose();
  }

  void _submit() {
    final ratio = parseNum(_ratio.text);
    if (ratio == null || ratio <= 0 || ratio > 100) {
      setState(() => _error = 'Vul een ratio in tussen 1 en 100 gram per E.');
      return;
    }
    Navigator.of(context).pop((BolusPeriod(label: _label.text.trim(), startTime: _start, carbRatio: ratio), false));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.existing == null ? 'Nieuw tijdvak' : 'Tijdvak aanpassen', style: context.t.headline),
        const SizedBox(height: 16),
        TextField(
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Naam (optioneel)', hintText: 'Bijv. Ochtend'),
        ),
        const SizedBox(height: 12),
        KWell(
          onTap: () async {
            final v = await _pickTime(context, _start, 'Starttijd');
            if (v != null) setState(() => _start = v);
          },
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.schedule, color: k.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('Starttijd', style: context.t.body)),
              Text(_start, style: context.t.subtitle.copyWith(color: k.accent)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ratio,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: context.t.subtitle,
          decoration: const InputDecoration(labelText: 'KH-ratio (gram per 1 E)', prefixText: '1 E : ', suffixText: 'g'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: context.t.caption.copyWith(color: k.dangerInk)),
        ],
        const SizedBox(height: 16),
        BigButton(label: 'Opslaan', icon: Icons.check, onPressed: _submit),
        if (widget.existing != null)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop((null, true)),
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Tijdvak verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
      ],
    );
  }
}
