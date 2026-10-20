// exercise_history_screen.dart — voortgang van één oefening
//
// Toont het persoonlijk record en alle eerdere keren dat deze oefening werd
// gedaan (nieuwste eerst), bereikbaar vanuit een lopende krachttraining en
// vanuit de oefeningenlijst in instellingen.

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/training_session.dart';
import '../repositories/session_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/empty_state.dart';

class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({
    super.key,
    required this.exerciseName,
    required this.controller,
  });

  final String exerciseName;
  final AppController controller;

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<ExercisePerformance> _history = const [];

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
      final history = await SessionRepository(client)
          .performanceHistory(userId, widget.exerciseName);
      if (!mounted) return;
      setState(() {
        _history = history;
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

  /// Per set zoals hij gedaan is: "12,5 kg · × 8", "20s" of
  /// "12,5 kg · verzuring" — niet altijd reps.
  String _formatSets(List<ExerciseSet> sets) =>
      sets.map((s) => s.summary).join(', ');

  @override
  Widget build(BuildContext context) {
    final pr = _history.isEmpty
        ? null
        : _history.map((p) => p.heaviest).reduce((a, b) => a > b ? a : b);
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          widget.exerciseName,
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: AppText.caption))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                if (pr != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColor.surface,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          color: AppColor.amber,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PERSOONLIJK RECORD', style: AppText.overline),
                            const SizedBox(height: 2),
                            Text(
                              '${_fmtKg(pr)}kg',
                              style: AppText.display.copyWith(fontSize: 22),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_history.length >= 2) ...[
                  const SizedBox(height: 18),
                  _WeightTrendChart(history: _history),
                ],
                const SizedBox(height: 18),
                Text('GESCHIEDENIS', style: AppText.overline),
                const SizedBox(height: 10),
                if (_history.isEmpty)
                  const EmptyState(
                    icon: Icons.history,
                    message: 'Nog geen eerdere sessies met deze oefening.',
                  )
                else
                  for (final entry in _history)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColor.bgDeep,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dutchShortDate(entry.date),
                            style: AppText.caption.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(_formatSets(entry.sets), style: AppText.body),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Simpele lijn+stippen-grafiek van het zwaarste gewicht per sessie, oudste
/// eerst — geen medisch/mmol-schaal zoals de glucosecurve, dus een eigen
/// kleine painter met auto-schaal op basis van de data.
class _WeightTrendChart extends StatelessWidget {
  const _WeightTrendChart({required this.history});

  /// Nieuwste eerst, zoals de repository 'm teruggeeft.
  final List<ExercisePerformance> history;

  String _fmtKg(double kg) =>
      kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

  @override
  Widget build(BuildContext context) {
    final chronological = history.reversed.toList();
    final weights = chronological.map((p) => p.heaviest).toList();
    final minKg = weights.reduce((a, b) => a < b ? a : b);
    final maxKg = weights.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GEWICHT OVER TIJD', style: AppText.overline),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: CustomPaint(
              painter: _WeightTrendPainter(weights, AppColor.amber),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dutchShortDate(chronological.first.date),
                style: AppText.caption.copyWith(fontSize: 10),
              ),
              Text(
                '${_fmtKg(minKg)}–${_fmtKg(maxKg)}kg',
                style: AppText.caption.copyWith(fontSize: 10),
              ),
              Text(
                dutchShortDate(chronological.last.date),
                style: AppText.caption.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  final List<double> weights;
  final Color color;
  _WeightTrendPainter(this.weights, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;
    final minV = weights.reduce((a, b) => a < b ? a : b);
    final maxV = weights.reduce((a, b) => a > b ? a : b);
    final span = maxV - minV;
    final pad = span < 1e-9 ? 1.0 : span * 0.2;
    final lo = minV - pad;
    final hi = maxV + pad;

    double y(double v) => size.height - ((v - lo) / (hi - lo)) * size.height;
    double x(int i) => size.width * i / (weights.length - 1);

    final path = Path();
    for (var i = 0; i < weights.length; i++) {
      final point = Offset(x(i), y(weights[i]));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < weights.length; i++) {
      canvas.drawCircle(Offset(x(i), y(weights[i])), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightTrendPainter oldDelegate) =>
      oldDelegate.weights != weights;
}
