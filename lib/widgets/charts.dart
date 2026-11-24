// charts.dart: gewichtscurve met veilige afvalcorridor, intensiteitsbalken,
// de cirkelvormige hersteltimer en een glucose-sparkline. Alle kleuren uit
// het actieve thema (context.k).

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/weight_plan.dart';
import '../models/glucose.dart';
import '../models/weigh_in.dart';
import '../theme/kinetic_theme.dart';

/// Gewichtsverloop (wegingen) plus de corridor van 0.5 - 0.8 kg per week
/// richting de weegdag, en de doellijn.
class WeightCurve extends StatelessWidget {
  const WeightCurve({super.key, required this.weighIns, required this.now, this.plan, this.height = 200});

  final List<WeighIn> weighIns;
  final WeightPlan? plan;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _WeightPainter(weighIns, plan, now, context.k, context.t.labelSm)),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(this.weighIns, this.plan, this.now, this.k, this.label);
  final List<WeighIn> weighIns;
  final WeightPlan? plan;
  final DateTime now;
  final KineticColors k;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 38.0, padR = 10.0, padT = 14.0, padB = 22.0;
    final pts = [...weighIns]..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    final end = plan?.weighDay ?? now.add(const Duration(days: 7));
    var start = pts.isEmpty ? now.subtract(const Duration(days: 28)) : pts.first.measuredAt;
    if (end.difference(start).inDays > 70) start = end.subtract(const Duration(days: 70));
    final shown = pts.where((p) => !p.measuredAt.isBefore(start)).toList();

    final values = <double>[
      ...shown.map((p) => p.weightKg),
      if (plan != null) ...[plan!.targetKg, plan!.currentKg, plan!.corridorAt(end).$1],
    ];
    if (values.isEmpty) return;
    var lo = values.reduce(math.min) - 0.6;
    var hi = values.reduce(math.max) + 0.6;
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    final spanMs = math.max(1, end.difference(start).inMilliseconds).toDouble();
    double x(DateTime t) => padL + (size.width - padL - padR) * (t.difference(start).inMilliseconds / spanMs);
    double y(double kg) => padT + (size.height - padT - padB) * (1 - (kg - lo) / (hi - lo));

    final muted = label.copyWith(color: k.textMuted, fontWeight: FontWeight.w500);
    for (var i = 0; i <= 3; i++) {
      final kg = lo + (hi - lo) * i / 3;
      final yy = y(kg);
      canvas.drawLine(Offset(padL, yy), Offset(size.width - padR, yy), Paint()..color = k.border);
      _text(canvas, kg.toStringAsFixed(1), Offset(0, yy - 7), muted);
    }

    final p = plan;
    if (p != null) {
      if (p.direction == WeightDirection.lose) {
        final (fastEnd, slowEnd) = p.corridorAt(end);
        final corridor = Path()
          ..moveTo(x(now), y(p.currentKg))
          ..lineTo(x(end), y(slowEnd))
          ..lineTo(x(end), y(fastEnd))
          ..close();
        canvas.drawPath(corridor, Paint()..color = k.primary.withValues(alpha: 0.14));
        final edge = Paint()
          ..color = k.primary.withValues(alpha: 0.55)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(x(now), y(p.currentKg)), Offset(x(end), y(slowEnd)), edge);
        canvas.drawLine(Offset(x(now), y(p.currentKg)), Offset(x(end), y(fastEnd)), edge);
      }
      final ty = y(p.targetKg);
      final dash = Paint()
        ..color = k.warning
        ..strokeWidth = 1.4;
      for (double xx = padL; xx < size.width - padR; xx += 9) {
        canvas.drawLine(Offset(xx, ty), Offset(math.min(xx + 5, size.width - padR), ty), dash);
      }
      _text(canvas, 'Doellijn (${dec1(p.targetKg)} kg)', Offset(padL + 4, ty - 16), muted.copyWith(color: k.warningInk, fontWeight: FontWeight.w700));
      final wx = x(end);
      canvas.drawLine(Offset(wx, padT), Offset(wx, size.height - padB), Paint()..color = k.warning.withValues(alpha: 0.5));
      final tp = _layout('Weging (${longDate(end)})', muted.copyWith(color: k.warningInk, fontWeight: FontWeight.w700));
      tp.paint(canvas, Offset(math.min(wx - tp.width / 2, size.width - tp.width), size.height - 14));
    }

    if (shown.isNotEmpty) {
      final path = Path()..moveTo(x(shown.first.measuredAt), y(shown.first.weightKg));
      for (final w in shown.skip(1)) {
        path.lineTo(x(w.measuredAt), y(w.weightKg));
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..color = k.primary,
      );
      for (final w in shown) {
        canvas.drawCircle(Offset(x(w.measuredAt), y(w.weightKg)), 3.2, Paint()..color = k.primary);
      }
      final last = shown.last;
      final o = Offset(x(last.measuredAt), y(last.weightKg));
      canvas.drawCircle(o, 6, Paint()..color = k.surface);
      canvas.drawCircle(o, 6, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = k.primary);
      _text(canvas, shortDate(start), Offset(padL, size.height - 14), muted);
    }
  }

  TextPainter _layout(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  void _text(Canvas canvas, String s, Offset at, TextStyle style) => _layout(s, style).paint(canvas, at);

  @override
  bool shouldRepaint(covariant _WeightPainter old) =>
      old.weighIns != weighIns || old.plan != plan || old.now != now || old.k != k;
}

/// Staafjes per dag/week met minuten op de mat.
class IntensityBars extends StatelessWidget {
  const IntensityBars({super.key, required this.values, required this.labels, this.highlightLast = true, this.height = 120});
  final List<int> values;
  final List<String> labels;
  final bool highlightLast;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final maxV = values.isEmpty ? 1 : math.max(1, values.reduce(math.max));
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (values[i] > 0) Text('${values[i]}', style: context.t.labelSm.copyWith(color: k.textMuted, fontSize: 9)),
                    const SizedBox(height: 3),
                    Container(
                      height: math.max(4.0, (height - 36) * values[i] / maxV),
                      decoration: BoxDecoration(
                        color: values[i] == 0
                            ? k.well
                            : (highlightLast && i == values.length - 1 ? k.accent : k.primary.withValues(alpha: 0.75)),
                        borderRadius: BorderRadius.circular(KRadius.sm),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i], style: context.t.labelSm.copyWith(color: k.textMuted), maxLines: 1, overflow: TextOverflow.clip),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cirkelvormige countdown (rustfase).
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, required this.child, this.size = 230, this.color, this.stroke = 12});
  final double progress; // 0 = net begonnen, 1 = voorbij
  final Widget child;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress, color ?? context.k.primary, context.k.well, stroke),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.track, this.stroke);
  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    final remaining = (1 - progress).clamp(0.0, 1.0);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * remaining, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Mini-lijn van een glucoseverloop (sessiekaarten, maaltijdrespons).
class GlucoseSparkline extends StatelessWidget {
  const GlucoseSparkline({super.key, required this.points, this.height = 36});
  final List<GlucosePoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(points, context.k)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.k);
  final List<GlucosePoint> points;
  final KineticColors k;

  @override
  void paint(Canvas canvas, Size size) {
    // Stippellijn op de bovengrens van het doelbereik als referentie.
    if (points.length < 2) return;
    final lo = math.min(3.5, points.map((p) => p.mmol).reduce(math.min) - 0.3);
    final hi = math.max(10.0, points.map((p) => p.mmol).reduce(math.max) + 0.3);
    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, points.last.at.millisecondsSinceEpoch - t0);
    double x(GlucosePoint p) => (p.at.millisecondsSinceEpoch - t0) / span * size.width;
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));
    final ref = Paint()
      ..color = k.border
      ..strokeWidth = 1;
    for (double xx = 0; xx < size.width; xx += 6) {
      canvas.drawLine(Offset(xx, y(targetHigh)), Offset(xx + 3, y(targetHigh)), ref);
    }
    final path = Path()..moveTo(x(points.first), y(points.first.mmol));
    for (final p in points.skip(1)) {
      path.lineTo(x(p), y(p.mmol));
    }
    final lowest = points.map((p) => p.mmol).reduce(math.min);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = lowest < hypoBelow ? k.danger : k.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.points != points || old.k != k;
}
