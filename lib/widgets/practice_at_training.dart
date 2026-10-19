// practice_at_training.dart — bij een techniek kiezen bij welke training je
// hem wilt oefenen: de eerstvolgende training (ook als die niet gepland is)
// of een specifieke geplande training. Die training krijgt dan
// herinneringen (zie AgendaNotificationService).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/agenda.dart';
import '../models/technique.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/technique_repository.dart';
import '../theme/kinetic_theme.dart';

class PracticeAtTrainingCard extends StatefulWidget {
  const PracticeAtTrainingCard({
    super.key,
    required this.technique,
    required this.techniqueRepository,
    required this.agendaRepository,
    required this.userId,
    required this.onTechniqueChanged,
    this.defaultReminders = const [60, 0],
  });

  final Technique technique;
  final TechniqueRepository techniqueRepository;
  final AgendaRepository agendaRepository;
  final String userId;
  final ValueChanged<Technique> onTechniqueChanged;

  /// Herinneringen voor een training die er nog geen heeft.
  final List<int> defaultReminders;

  @override
  State<PracticeAtTrainingCard> createState() => _PracticeAtTrainingCardState();
}

class _PracticeAtTrainingCardState extends State<PracticeAtTrainingCard> {
  List<PlannedTraining> _upcoming = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.agendaRepository.trainings(widget.userId);
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _upcoming = all.where((t) => t.startsAt.isAfter(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _id => widget.technique.id;

  List<PlannedTraining> get _linked =>
      _upcoming.where((t) => t.techniqueIds.contains(_id)).toList();

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setNext(bool value) async {
    try {
      await widget.techniqueRepository.setPracticeNext(_id, value);
      widget.onTechniqueChanged(widget.technique.copyWith(practiceNext: value));
    } catch (_) {
      _snack('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  Future<void> _link(PlannedTraining t, bool add) async {
    final ids = [
      for (final id in t.techniqueIds)
        if (id != _id) id,
      if (add) _id,
    ];
    final next = t.copyWith(
      techniqueIds: ids,
      techniqueReminders: add && t.techniqueReminders.isEmpty
          ? normalizeReminders(widget.defaultReminders)
          : null,
    );
    try {
      final saved = await widget.agendaRepository.saveTraining(
        next,
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _upcoming = [for (final u in _upcoming) u.id == saved.id ? saved : u];
      });
    } catch (_) {
      _snack('Opslaan is niet gelukt. Probeer opnieuw.');
    }
  }

  static String _when(PlannedTraining t) =>
      '${DateFormat('EEE d MMM · HH:mm', 'nl_NL').format(t.startsAt)} · '
      '${t.displayTitle}';

  Future<void> _choose() async {
    final candidates = _upcoming
        .where((t) => !t.techniqueIds.contains(_id))
        .take(12)
        .toList();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Oefenen bij…', style: AppText.title),
            ),
            if (!widget.technique.practiceNext)
              ListTile(
                leading: const Icon(Icons.skip_next_outlined),
                title: const Text('Eerstvolgende training'),
                subtitle: const Text(
                  'Ook als die niet gepland is — je ziet hem bij de start',
                ),
                onTap: () => Navigator.pop(c, 'next'),
              ),
            for (final t in candidates)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(_when(t)),
                subtitle: t.location.isEmpty ? null : Text(t.location),
                onTap: () => Navigator.pop(c, t),
              ),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Geen (andere) geplande trainingen. Plan er een in de '
                  'Agenda.',
                  style: AppText.caption,
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == 'next') {
      await _setNext(true);
    } else if (choice is PlannedTraining) {
      await _link(choice, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.technique.practiceNext;
    final linked = _linked;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                size: 18,
                color: AppColor.coralSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Oefenen bij een training',
                  style: AppText.bodyStrong,
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _choose,
                child: const Text('Kiezen'),
              ),
            ],
          ),
          if (!next && linked.isEmpty)
            Text(
              'Kies een training, dan krijg je vooraf en/of bij de start een '
              'herinnering om deze techniek te oefenen.',
              style: AppText.caption,
            ),
          if (next || linked.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (next)
                  InputChip(
                    avatar: const Icon(Icons.skip_next_outlined, size: 16),
                    label: const Text('Eerstvolgende training'),
                    onDeleted: () => _setNext(false),
                  ),
                for (final t in linked)
                  InputChip(
                    avatar: const Icon(Icons.event_outlined, size: 16),
                    label: Text(_when(t)),
                    onDeleted: () => _link(t, false),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
