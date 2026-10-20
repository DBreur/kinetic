// weigh_in_sheet.dart — wegen met datum: een korte regel ("Laatst gewogen:
// 3 dagen geleden · Volgende: vr 24 okt") en een paneel met de
// geschiedenis, "Nu wegen" en hoe vaak je wilt wegen.

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/weigh_in_plan.dart';
import '../models/weigh_in.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic.dart';

String _kg(double kg) => kg.toStringAsFixed(1).replaceAll('.', ',');

String _daysAgo(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'vandaag';
  if (days == 1) return 'gisteren';
  return '$days dagen geleden';
}

/// "Laatst gewogen: … · Volgende: …" — tikken opent [showWeighInSheet].
class WeighInSummary extends StatelessWidget {
  const WeighInSummary({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WeighIn>>(
      valueListenable: controller.weighIns,
      builder: (context, list, _) {
        final now = DateTime.now();
        final profile = controller.profile;
        final last = list.isEmpty ? null : list.first.measuredAt;
        final next = nextWeighIn(
          last: last,
          intervalDays: profile?.weighInIntervalDays ?? 0,
          reminderTime: profile?.weighInReminderTime ?? '08:00',
          now: now,
        );
        final parts = [
          last == null
              ? 'Nog niet gewogen'
              : 'Laatst gewogen: ${_daysAgo(last, now)}',
          if (next != null) 'Volgende: ${planningLabel(next, now: now)}',
        ];
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: AppColor.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.monitor_weight_outlined,
                size: 22,
                color: AppColor.ice,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => showWeighInSheet(context, controller),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Wegen', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        parts.join(' · '),
                        style: AppText.caption.copyWith(
                          color: AppColor.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => showWeighInSheet(context, controller),
                style: FilledButton.styleFrom(
                  // Thema-knoppen zijn standaard volle breedte; in een rij
                  // moet hij zijn eigen breedte houden.
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Nu wegen'),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> showWeighInSheet(BuildContext context, AppController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColor.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => _WeighInSheet(controller: controller),
  );
}

class _WeighInSheet extends StatefulWidget {
  const _WeighInSheet({required this.controller});

  final AppController controller;

  @override
  State<_WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<_WeighInSheet> {
  late final _weight = TextEditingController(
    text: widget.controller.profile?.weightKg == null
        ? ''
        : _kg(widget.controller.profile!.weightKg!),
  );
  late int _interval = widget.controller.profile?.weighInIntervalDays ?? 7;
  late String _time = widget.controller.profile?.weighInReminderTime ?? '08:00';
  bool _saving = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _weighNow() async {
    final kg = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (kg == null || kg < 20 || kg > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vul een gewicht tussen 20 en 300 kg in.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.controller.addWeighIn(kg);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Opslaan is niet gelukt. Is de nieuwste database-migratie al '
            'uitgevoerd?',
          ),
        ),
      );
    }
  }

  Future<void> _saveSchedule({int? interval, String? time}) async {
    final p = widget.controller.profile;
    if (p == null) return;
    setState(() {
      _interval = interval ?? _interval;
      _time = time ?? _time;
    });
    await widget.controller.saveProfile(
      p.copyWith(weighInIntervalDays: _interval, weighInReminderTime: _time),
    );
    await widget.controller.loadWeighIns();
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
      helpText: 'Herinnering om',
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    await _saveSchedule(time: '$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, scroll) => ValueListenableBuilder<List<WeighIn>>(
        valueListenable: widget.controller.weighIns,
        builder: (context, list, _) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + insets.viewInsets.bottom + insets.padding.bottom,
          ),
          children: [
            Text('Wegen', style: AppText.title),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppText.body,
                    decoration: const InputDecoration(
                      labelText: 'Gewicht nu',
                      suffixText: 'kg',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saving ? null : _weighNow,
                  style: FilledButton.styleFrom(
                    // Thema-knoppen zijn standaard volle breedte; in een rij
                    // moet hij zijn eigen breedte houden.
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Nu wegen'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const KLabel('Hoe vaak wegen'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (days, label) in const [
                  (0, 'Geen herinnering'),
                  (1, 'Elke dag'),
                  (3, 'Om de 3 dagen'),
                  (7, 'Elke week'),
                  (14, 'Om de 2 weken'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _interval == days,
                    showCheckmark: false,
                    onSelected: (_) => _saveSchedule(interval: days),
                  ),
              ],
            ),
            if (_interval > 0) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('Herinnering om $_time'),
              ),
            ],
            const SizedBox(height: 16),
            const KLabel('Geschiedenis'),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Text('Nog geen wegingen.', style: AppText.caption)
            else ...[
              if (list.length >= 2) _Trend(list: list),
              for (var i = 0; i < list.length; i++)
                _WeighInRow(
                  weighIn: list[i],
                  previous: i + 1 < list.length ? list[i + 1] : null,
                  onDelete: () => widget.controller.deleteWeighIn(list[i]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Verschil tussen de nieuwste en de oudste weging in de lijst.
class _Trend extends StatelessWidget {
  const _Trend({required this.list});

  final List<WeighIn> list;

  @override
  Widget build(BuildContext context) {
    final diff = list.first.weightKg - list.last.weightKg;
    final sign = diff > 0
        ? '+'
        : diff < 0
        ? '−'
        : '±';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$sign${_kg(diff.abs())} kg sinds ${dutchShortDate(list.last.measuredAt)}',
        style: AppText.bodyStrong.copyWith(color: AppColor.ice),
      ),
    );
  }
}

class _WeighInRow extends StatelessWidget {
  const _WeighInRow({
    required this.weighIn,
    required this.previous,
    required this.onDelete,
  });

  final WeighIn weighIn;
  final WeighIn? previous;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final prev = previous;
    final diff = prev == null ? null : weighIn.weightKg - prev.weightKg;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dutchShortDate(weighIn.measuredAt),
              style: AppText.body,
            ),
          ),
          if (diff != null && diff != 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${diff > 0 ? '+' : '−'}${_kg(diff.abs())}',
                style: AppText.caption,
              ),
            ),
          Text('${_kg(weighIn.weightKg)} kg', style: AppText.bodyStrong),
          IconButton(
            tooltip: 'Verwijderen',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 16, color: AppColor.inkFaint),
          ),
        ],
      ),
    );
  }
}
