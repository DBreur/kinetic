// charts.dart: gewichtscurve met veilige afvalcorridor, intensiteitsbalken
// voor de trainingshistorie en de cirkelvormige hersteltimer.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/weight_plan.dart';
import '../models/weigh_in.dart';
import '../theme/kinetic_theme.dart';

/// Gewichtsverloop (laatste wegingen) plus de corridor van 0.5 - 0.8 kg per
/// week richting de weegdag, en de doellijn.
class WeightCurve extends StatelessWidget {
  const WeightCurve({
    super.key,
    required this.weighIns,
    required this.now,
    this.plan,
    this.height = 190,
  });

  final List<WeighIn> weighIns;
  final WeightPlan? plan;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _WeightPainter(weighIns, plan, now)),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(this.weighIns, this.plan, this.now);
  final List<WeighIn> weighIns;
  final WeightPlan? plan;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 36.0, padR = 10.0, padT = 12.0, padB = 22.0;
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

    final grid = Paint()..color = KColor.border;
    final label = KText.caption.copyWith(fontSize: 10, color: KColor.textMuted);
    for (var i = 0; i <= 3; i++) {
      final kg = lo + (hi - lo) * i / 3;
      final yy = y(kg);
      canvas.drawLine(Offset(padL, yy), Offset(size.width - padR, yy), grid);
      _text(canvas, kg.toStringAsFixed(1), Offset(2, yy - 6), label);
    }

    final p = plan;
    if (p != null) {
      // Corridor als vlak van nu naar de weegdag.
      if (p.direction == WeightDirection.lose) {
        final (fastEnd, slowEnd) = p.corridorAt(end);
        final corridor = Path()
          ..moveTo(x(now), y(p.currentKg))
          ..lineTo(x(end), y(slowEnd))
          ..lineTo(x(end), y(fastEnd))
          ..close();
        canvas.drawPath(corridor, Paint()..color = KColor.teal.withValues(alpha: 0.14));
        final edge = Paint()
          ..color = KColor.teal.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(x(now), y(p.currentKg)), Offset(x(end), y(slowEnd)), edge);
        canvas.drawLine(Offset(x(now), y(p.currentKg)), Offset(x(end), y(fastEnd)), edge);
      }
      // Doellijn
      final ty = y(p.targetKg);
      final dash = Paint()
        ..color = KColor.warning
        ..strokeWidth = 1.4;
      for (double xx = padL; xx < size.width - padR; xx += 9) {
        canvas.drawLine(Offset(xx, ty), Offset(math.min(xx + 5, size.width - padR), ty), dash);
      }
      _text(canvas, 'doel ${dec1(p.targetKg)}', Offset(padL + 4, ty - 15), label.copyWith(color: KColor.warning, fontWeight: FontWeight.w700));
      // Weegdag
      final wx = x(end);
      canvas.drawLine(Offset(wx, padT), Offset(wx, size.height - padB), Paint()..color = KColor.warning.withValues(alpha: 0.5));
      _text(canvas, longDate(end), Offset(wx - 52, size.height - 14), label.copyWith(color: KColor.warning));
    }

    // Gewichtslijn
    if (shown.isNotEmpty) {
      final path = Path()..moveTo(x(shown.first.measuredAt), y(shown.first.weightKg));
      for (final w in shown.skip(1)) {
        path.lineTo(x(w.measuredAt), y(w.weightKg));
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..color = KColor.tealLight,
      );
      for (final w in shown) {
        canvas.drawCircle(Offset(x(w.measuredAt), y(w.weightKg)), 3.2, Paint()..color = KColor.tealLight);
      }
      final last = shown.last;
      canvas.drawCircle(Offset(x(last.measuredAt), y(last.weightKg)), 6, Paint()..color = KColor.teal.withValues(alpha: 0.3));
      _text(canvas, shortDate(start), Offset(padL, size.height - 14), label);
    }
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _WeightPainter old) =>
      old.weighIns != weighIns || old.plan != plan || old.now != now;
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
                    if (values[i] > 0)
                      Text('${values[i]}', style: KText.caption.copyWith(fontSize: 9, color: KColor.textMuted)),
                    const SizedBox(height: 3),
                    Container(
                      height: math.max(4.0, (height - 36) * values[i] / maxV),
                      decoration: BoxDecoration(
                        color: values[i] == 0
                            ? KColor.surfaceHigh
                            : (highlightLast && i == values.length - 1 ? KColor.tealLight : KColor.teal.withValues(alpha: 0.7)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i], style: KText.caption.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.clip),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cirkelvormige countdown voor de rustfase.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, required this.child, this.size = 230, this.color = KColor.teal});
  final double progress; // 0 = net begonnen, 1 = voorbij
  final Widget child;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress, color),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = KColor.surfaceHigh);
    final remaining = (1 - progress).clamp(0.0, 1.0);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * remaining, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.color != color;
}
