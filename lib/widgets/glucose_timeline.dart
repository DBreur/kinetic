// glucose_timeline.dart: Dexcom-stijl trendgrafiek. Horizontaal scrollen
// door de laatste 24 uur, met een tijdvenster (3/6/12/24 uur) dat bepaalt
// hoeveel er tegelijk in beeld is. Elk meetpunt (per 5 min) is een stip:
// teal in bereik, amber erboven, rood eronder. Tik of sleep voor een
// scrubber met tijd, waarde en trend; maaltijden staan als koolhydraatlabel
// bovenin (de auto-annotatie).

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/food_log_entry.dart';
import '../models/glucose.dart';
import '../theme/kinetic_theme.dart';

class GlucoseTimeline extends StatefulWidget {
  const GlucoseTimeline({
    super.key,
    required this.points,
    required this.now,
    this.meals = const [],
    this.height = 200,
    this.windowHours = 6,
    this.totalHours = 24,
  });

  final List<GlucosePoint> points;
  final List<FoodLogEntry> meals;
  final DateTime now;
  final double height;

  /// Hoeveel uur er tegelijk in beeld is.
  final int windowHours;

  /// Hoe ver je terug kunt scrollen.
  final int totalHours;

  @override
  State<GlucoseTimeline> createState() => _GlucoseTimelineState();
}

class _GlucoseTimelineState extends State<GlucoseTimeline> {
  final _scroll = ScrollController();
  int? _selected;
  double _viewport = 0;

  DateTime get _start => widget.now.subtract(Duration(hours: widget.totalHours));

  @override
  void didUpdateWidget(covariant GlucoseTimeline old) {
    super.didUpdateWidget(old);
    if (old.windowHours != widget.windowHours) {
      _selected = null;
      _jumpToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  List<GlucosePoint> get _visible => widget.points.where((p) => p.at.isAfter(_start)).toList();

  void _select(Offset local, _Geometry geo, List<GlucosePoint> pts) {
    if (pts.isEmpty) return;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dx = (geo.x(pts[i].at) - local.dx).abs();
      if (dx < bestDist) {
        bestDist = dx;
        best = i;
      }
    }
    if (best != _selected) HapticFeedback.selectionClick();
    setState(() => _selected = bestDist < 40 ? best : null);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final pts = _visible;
    if (pts.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(child: Text('Nog geen glucosedata in de laatste ${widget.totalHours} uur', style: context.t.caption)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        if (viewport != _viewport) {
          _viewport = viewport;
          _jumpToEnd();
        }
        final pxPerHour = (viewport - 44) / widget.windowHours;
        final width = widget.totalHours * pxPerHour + 44;
        final geo = _Geometry(widget.height, pxPerHour, _start, pts);
        final sel = _selected != null && _selected! < pts.length ? _selected : null;
        return SizedBox(
          height: widget.height,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              onTapDown: (d) => _select(d.localPosition, geo, pts),
              onLongPressStart: (d) => _select(d.localPosition, geo, pts),
              onLongPressMoveUpdate: (d) => _select(d.localPosition, geo, pts),
              child: SizedBox(
                width: width,
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: Size(width, widget.height),
                      painter: _TimelinePainter(
                        k: k,
                        label: context.t.labelSm,
                        geo: geo,
                        points: pts,
                        meals: widget.meals.where((m) => m.at.isAfter(_start)).toList(),
                        selected: sel,
                        now: widget.now,
                        windowHours: widget.windowHours,
                      ),
                    ),
                    if (sel != null) _tooltip(context, geo, pts, sel, width),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tooltip(BuildContext context, _Geometry geo, List<GlucosePoint> pts, int i, double width) {
    final k = context.k;
    final p = pts[i];
    final prev = i > 0 ? pts[i - 1] : null;
    final trend = prev == null ? Trend.flat : trendFromDelta(p.mmol - prev.mmol);
    const w = 188.0;
    final left = (geo.x(p.at) - w / 2).clamp(0.0, width - w);
    return Positioned(
      left: left,
      top: 0,
      width: w,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: k.isDark ? k.well : k.text,
            borderRadius: BorderRadius.circular(KRadius.sm),
          ),
          child: Text(
            '${hhmm(p.at)} - ${p.mmol.toStringAsFixed(1)} mmol/L ${trendArrow(trend)} ${trendLabel(trend)}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.caption.copyWith(color: k.isDark ? k.text : k.surface, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _Geometry {
  _Geometry(this.height, this.pxPerHour, this.start, List<GlucosePoint> pts) {
    final values = pts.map((p) => p.mmol);
    lo = math.min(2.5, values.isEmpty ? 2.5 : values.reduce(math.min) - 0.5);
    hi = math.max(12.0, values.isEmpty ? 12.0 : values.reduce(math.max) + 1.0);
  }

  final double height;
  final double pxPerHour;
  final DateTime start;
  late final double lo;
  late final double hi;

  static const top = 34.0; // tooltip + maaltijdlabels
  static const bottom = 22.0; // uurlabels
  static const left = 6.0;

  double x(DateTime t) => left + t.difference(start).inSeconds / 3600.0 * pxPerHour;

  double y(double mmol) {
    final h = height - top - bottom;
    return top + h * (1 - (mmol - lo) / (hi - lo));
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.k,
    required this.label,
    required this.geo,
    required this.points,
    required this.meals,
    required this.selected,
    required this.now,
    required this.windowHours,
  });

  final KineticColors k;
  final TextStyle label;
  final _Geometry geo;
  final List<GlucosePoint> points;
  final List<FoodLogEntry> meals;
  final int? selected;
  final DateTime now;
  final int windowHours;

  Color _dot(double mmol) => switch (zoneFor(mmol)) {
    GlucoseZone.hypo => k.danger,
    GlucoseZone.low => k.warning,
    GlucoseZone.inTarget => k.primary,
    GlucoseZone.high => k.warning,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final right = geo.x(now);
    final plotBottom = size.height - _Geometry.bottom;

    // Doelcorridor met stippellijnen.
    final band = Rect.fromLTRB(0, geo.y(targetHigh), size.width, geo.y(targetLow));
    canvas.drawRect(band, Paint()..color = k.primary.withValues(alpha: k.isDark ? 0.08 : 0.07));
    _dashed(canvas, geo.y(targetHigh), size.width, k.primary.withValues(alpha: 0.45));
    _dashed(canvas, geo.y(targetLow), size.width, k.primary.withValues(alpha: 0.45));
    _dashed(canvas, geo.y(hypoBelow), size.width, k.danger.withValues(alpha: 0.4));

    // Uurlijnen en labels (dichter bij een korter venster).
    final step = windowHours <= 3 ? 1 : (windowHours <= 6 ? 2 : (windowHours <= 12 ? 3 : 6));
    final labelStyle = label.copyWith(color: k.textMuted, fontWeight: FontWeight.w500);
    var hour = DateTime(geo.start.year, geo.start.month, geo.start.day, geo.start.hour + 1);
    while (hour.isBefore(now)) {
      final x = geo.x(hour);
      if (hour.hour % step == 0) {
        canvas.drawLine(Offset(x, _Geometry.top), Offset(x, plotBottom), Paint()..color = k.border);
        _text(canvas, '${two(hour.hour)}:00', Offset(x, size.height - 10), labelStyle);
      }
      hour = hour.add(const Duration(hours: 1));
    }
    _text(canvas, targetHigh.toStringAsFixed(1), Offset(right + 18, geo.y(targetHigh)), labelStyle);
    _text(canvas, targetLow.toStringAsFixed(1), Offset(right + 18, geo.y(targetLow)), labelStyle);

    // Verbindingslijn, onderbroken bij gaten > 15 min.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..color = k.primary.withValues(alpha: 0.45);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(geo.x(points[i].at), geo.y(points[i].mmol));
      final gap = i > 0 && points[i].at.difference(points[i - 1].at).inMinutes > 15;
      if (i == 0 || gap) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, line);

    // Scrubber
    if (selected != null) {
      final x = geo.x(points[selected!].at);
      canvas.drawLine(Offset(x, _Geometry.top - 4), Offset(x, plotBottom), Paint()
        ..color = k.textSecondary
        ..strokeWidth = 1);
    }

    // Meetpunten
    final dotR = windowHours <= 6 ? 3.2 : (windowHours <= 12 ? 2.6 : 2.0);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = Offset(geo.x(p.at), geo.y(p.mmol));
      final c = _dot(p.mmol);
      if (i == selected) {
        canvas.drawCircle(o, 7, Paint()..color = k.surface);
        canvas.drawCircle(o, 7, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = c);
      } else if (i == points.length - 1) {
        // Laatste meting: open ring, zoals in de mockup.
        canvas.drawCircle(o, 5, Paint()..color = k.surface);
        canvas.drawCircle(o, 5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = c);
      } else {
        canvas.drawCircle(o, dotR, Paint()..color = c);
      }
    }

    // Maaltijdlabels (koolhydraten) bovenin.
    for (final m in meals) {
      final carbs = m.carbs;
      if (carbs == null || carbs <= 0) continue;
      final x = geo.x(m.at);
      canvas.drawLine(Offset(x, 26), Offset(x, plotBottom), Paint()
        ..color = k.warning.withValues(alpha: 0.35)
        ..strokeWidth = 1);
      final tp = _layout('${grams(carbs)}g', label.copyWith(color: k.warningInk, fontWeight: FontWeight.w700));
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 18), width: tp.width + 10, height: 16),
        const Radius.circular(8),
      );
      canvas.drawRRect(r, Paint()..color = k.warningTint);
      tp.paint(canvas, Offset(x - tp.width / 2, 18 - tp.height / 2));
    }
  }

  void _dashed(Canvas canvas, double y, double width, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), p);
    }
  }

  TextPainter _layout(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = _layout(s, style);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.meals != meals ||
      old.now != now ||
      old.k != k ||
      old.windowHours != windowHours ||
      old.geo.pxPerHour != geo.pxPerHour;
}
