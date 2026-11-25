// competition_editor.dart: wedstrijd plannen, aanpassen of verwijderen:
// naam, datum + tijd van de weging, locatie, discipline, gewichtsklasse
// (max of min) met grens, doelgewicht en eigen doel. Na afloop ook de
// uitslag (plaats, winst/verlies, notitie).

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../models/competition.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'sheets.dart';
import 'start_training_sheet.dart';

Future<void> showCompetitionEditor(BuildContext context, {Competition? existing}) =>
    showKineticSheet<void>(context, builder: (_) => _CompetitionEditor(existing: existing));

class _CompetitionEditor extends StatefulWidget {
  const _CompetitionEditor({this.existing});
  final Competition? existing;

  @override
  State<_CompetitionEditor> createState() => _CompetitionEditorState();
}

class _CompetitionEditorState extends State<_CompetitionEditor> {
  late final Competition? _e = widget.existing;
  late final _name = TextEditingController(text: _e?.name ?? '');
  late final _location = TextEditingController(text: _e?.location ?? '');
  late final _limit = TextEditingController(text: _e?.weightLimitKg == null ? '' : dec1(_e!.weightLimitKg!));
  late final _target = TextEditingController(text: _e?.targetWeightKg == null ? '' : dec1(_e!.targetWeightKg!));
  late final _goal = TextEditingController(text: _e?.goal ?? '');
  late final _place = TextEditingController(text: _e?.resultPlace?.toString() ?? '');
  late final _wins = TextEditingController(text: _e?.resultWins?.toString() ?? '');
  late final _losses = TextEditingController(text: _e?.resultLosses?.toString() ?? '');
  late final _resultNote = TextEditingController(text: _e?.resultNote ?? '');
  late String _discipline = _e?.discipline ?? 'sport';
  late WeightLimitType _limitType = _e?.weightLimitType ?? WeightLimitType.under;
  late DateTime _at;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = KineticScope.read(context).now();
    _at = _e?.startsAt ?? DateTime(now.year, now.month, now.day + 28, 9, 0);
  }

  @override
  void dispose() {
    for (final c in [_name, _location, _limit, _target, _goal, _place, _wins, _losses, _resultNote]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isPast => _at.isBefore(KineticScope.read(context).now());

  Future<void> _pickDate() async {
    final now = KineticScope.read(context).now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 3),
      helpText: 'Datum van de wedstrijd',
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      helpText: 'Tijd van de weging',
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final name = _name.text.trim();
    final limit = parseNum(_limit.text);
    final target = parseNum(_target.text);
    if (name.isEmpty) return setState(() => _error = 'Geef de wedstrijd een naam.');
    if (_limitType != WeightLimitType.none && (limit == null || limit < 20 || limit > 300)) {
      return setState(() => _error = 'Vul de gewichtsgrens in (20-300 kg), of kies "Open".');
    }
    if (target != null && (target < 20 || target > 300)) return setState(() => _error = 'Doelgewicht moet tussen 20 en 300 kg liggen.');
    final place = _int(_place);
    if (place != null && place < 1) return setState(() => _error = 'Plaats moet 1 of hoger zijn.');
    final type = _limitType;
    final weightClass = switch (type) {
      WeightLimitType.under => '-${dec1(limit!).replaceAll('.', ',')} kg',
      WeightLimitType.over => '+${dec1(limit!).replaceAll('.', ',')} kg',
      WeightLimitType.none => '',
    };
    final base = _e ?? Competition(id: '', name: name, startsAt: _at);
    final comp = base.copyWith(
      name: name,
      startsAt: _at,
      discipline: _discipline,
      location: _location.text.trim(),
      weightClass: weightClass,
      weightLimitType: type,
      weightLimitKg: limit,
      clearWeightLimit: type == WeightLimitType.none,
      targetWeightKg: target,
      clearTarget: target == null,
      goal: _goal.text.trim(),
      clearResult: true,
      resultNote: _resultNote.text.trim(),
    ).copyWith(resultPlace: place, resultWins: _int(_wins), resultLosses: _int(_losses));
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await KineticScope.read(context).saveCompetition(comp);
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _saving = false;
        _error = 'Opslaan mislukt. Controleer je verbinding.';
      });
      return;
    }
    Navigator.of(context).pop();
    showToast(context, _e == null ? '$name gepland' : '$name bijgewerkt');
  }

  Future<void> _delete() async {
    final store = KineticScope.read(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wedstrijd verwijderen?'),
        content: Text('"${_e!.name}" wordt uit je agenda gehaald. Je wegingen blijven bewaard.'),
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
    if (ok != true) return;
    final done = await store.deleteCompetition(_e!);
    if (!mounted) return;
    if (done) {
      nav.pop();
    } else {
      setState(() => _error = 'Verwijderen mislukt. Controleer je verbinding.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final numFormat = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final intFormat = [FilteringTextInputFormatter.digitsOnly];
    Widget tile(IconData icon, String label, String value, VoidCallback onTap) => Expanded(
      child: KWell(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: k.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.t.caption),
                  Text(value, style: context.t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_e == null ? 'Wedstrijd plannen' : 'Wedstrijd aanpassen', style: context.t.headline),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Naam', hintText: 'Bijv. Lichtstad Open'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile(
              Icons.event,
              'Datum',
              _at.year == KineticScope.read(context).now().year ? shortDate(_at) : '${shortDate(_at)} ${_at.year}',
              _pickDate,
            ),
            const SizedBox(width: 8),
            tile(Icons.monitor_weight_outlined, 'Weging', hhmm(_at), _pickTime),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Locatie (optioneel)', prefixIcon: Icon(Icons.place_outlined)),
        ),
        const SizedBox(height: 16),
        const FormLabel('Discipline'),
        KSegmented<String>(
          options: const [('sport', 'Sport'), ('combat', 'Combat'), ('both', 'Beide')],
          value: _discipline,
          onChanged: (v) => setState(() => _discipline = v),
        ),
        const SizedBox(height: 16),
        const FormLabel('Gewichtsklasse'),
        KSegmented<WeightLimitType>(
          options: const [
            (WeightLimitType.under, 'Max (−)'),
            (WeightLimitType.over, 'Min (+)'),
            (WeightLimitType.none, 'Open'),
          ],
          value: _limitType,
          onChanged: (v) => setState(() => _limitType = v),
        ),
        if (_limitType != WeightLimitType.none) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: numFormat,
            style: context.t.body,
            decoration: InputDecoration(
              labelText: _limitType == WeightLimitType.under ? 'Maximaal gewicht (kg)' : 'Klassegrens (kg, je moet erboven zitten)',
              hintText: _limitType == WeightLimitType.under ? '82' : '88',
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: numFormat,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Doelgewicht op de weging (optioneel, kg)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _goal,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Eigen doel (optioneel)', hintText: 'Bijv. Podium halen'),
        ),
        if (_e != null && _isPast) ...[
          const SizedBox(height: 20),
          const FormLabel('Uitslag'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _place,
                  keyboardType: TextInputType.number,
                  inputFormatters: intFormat,
                  style: context.t.body,
                  decoration: const InputDecoration(labelText: 'Plaats'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _wins,
                  keyboardType: TextInputType.number,
                  inputFormatters: intFormat,
                  style: context.t.body,
                  decoration: const InputDecoration(labelText: 'Gewonnen'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _losses,
                  keyboardType: TextInputType.number,
                  inputFormatters: intFormat,
                  style: context.t.body,
                  decoration: const InputDecoration(labelText: 'Verloren'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _resultNote,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: context.t.body,
            decoration: const InputDecoration(labelText: 'Notitie over de wedstrijd'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: context.t.caption.copyWith(color: k.danger)),
        ],
        const SizedBox(height: 20),
        BigButton(
          label: _saving ? 'Opslaan…' : (_e == null ? 'Wedstrijd plannen' : 'Opslaan'),
          icon: Icons.check,
          height: 56,
          onPressed: _saving ? null : _save,
        ),
        if (_e != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Wedstrijd verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
        ],
      ],
    );
  }
}
