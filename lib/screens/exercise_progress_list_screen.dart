// exercise_progress_list_screen.dart — overzicht van alle oefeningen waar
// ooit sets van zijn gelogd, met per oefening het persoonlijk record en
// wanneer je hem voor het laatst deed. Van hieruit naar de volledige
// geschiedenis van één oefening (exercise_history_screen.dart).

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../repositories/session_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/empty_state.dart';
import 'exercise_history_screen.dart';

class ExerciseProgressListScreen extends StatefulWidget {
  const ExerciseProgressListScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ExerciseProgressListScreen> createState() =>
      _ExerciseProgressListScreenState();
}

class _ExerciseProgressListScreenState
    extends State<ExerciseProgressListScreen> {
  bool _loading = true;
  String? _error;
  List<_ExerciseSummary> _summaries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    final client = widget.controller.client;
    if (userId == null || client == null) {
      setState(() {
        _loading = false;
        _error = 'Niet ingelogd.';
      });
      return;
    }
    try {
      final byName = await SessionRepository(
        client,
      ).allExercisePerformances(userId);
      final summaries = byName.entries.map((entry) {
        final performances = entry.value;
        final pr = performances
            .map((p) => p.heaviest)
            .reduce((a, b) => a > b ? a : b);
        final lastDate = performances
            .map((p) => p.date)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return _ExerciseSummary(
          name: entry.key,
          personalRecord: pr,
          lastDone: lastDate,
        );
      }).toList()..sort((a, b) => b.lastDone.compareTo(a.lastDone));
      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kon de voortgang niet laden.';
      });
    }
  }

  String _fmtKg(double kg) =>
      kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          'Voortgang',
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: AppText.caption))
          : _summaries.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.fitness_center_outlined,
                message: 'Nog geen sets gelogd tijdens een krachttraining.',
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                for (final s in _summaries)
                  InkWell(
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseHistoryScreen(
                          exerciseName: s.name,
                          controller: widget.controller,
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColor.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: AppText.cardTitle),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.emoji_events_outlined,
                                      size: 12,
                                      color: AppColor.amber,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_fmtKg(s.personalRecord)}kg',
                                      style: AppText.caption.copyWith(
                                        color: AppColor.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Laatst ${dutchShortDate(s.lastDone)}',
                                      style: AppText.caption,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColor.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ExerciseSummary {
  final String name;
  final double personalRecord;
  final DateTime lastDone;

  const _ExerciseSummary({
    required this.name,
    required this.personalRecord,
    required this.lastDone,
  });
}
