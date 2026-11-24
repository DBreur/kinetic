// glucose_timeline.dart: horizontaal scrollbare 12-uurs Dexcom-tijdlijn.
// Tik op een meetpunt voor tijd, waarde en trend; maaltijden staan als
// koolhydraatlabels bovenin (de "auto-annotatie").

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
    this.height = 190,
    this.hours = 12,
    this.pxPerHour = 68,
  });

  final List<GlucosePoint> points;
  final List<FoodLogEntry> meals;
  final DateTime now;
  final double height;
  final int hours;
  final double pxPerHour;

  @override
  State<GlucoseTimeline> createState() => _GlucoseTimelineState();
}

class _GlucoseTimelineState extends State<GlucoseTimeline> {
  final _scroll = ScrollController();
  int? _selected;

  DateTime get _start => widget.now.subtract(Duration(hours: widget.hours));
  double get _width => widget.hours * widget.pxPerHour + 40;

  @override
  void initState() {
    super.initState();
    // Begin rechts, bij "nu".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<GlucosePoint> get _visible =>
      widget.points.where((p) => p.at.isAfter(_start)).toList();

  void _onTap(TapDownDetails d) {
    final pts = _visible;
    if (pts.isEmpty) return;
    final geo = _Geometry(widget, _start, _width, pts);
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dx = (geo.x(pts[i].at) - d.localPosition.dx).abs();
      if (dx < bestDist) {
        bestDist = dx;
        best = i;
      }
    }
    HapticFeedback.selectionClick();
    setState(() => _selected = bestDist < 28 ? best : null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _visible;
    final sel = _selected != null && _selected! < pts.length ? _selected : null;
    final geo = _Geometry(widget, _start, _width, pts);
    return SizedBox(
      height: widget.height,
      child: pts.isEmpty
          ? Center(child: Text('Nog geen glucosedata in de laatste ${widget.hours} uur', style: KText.caption))
          : SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                onTapDown: _onTap,
                child: SizedBox(
                  width: _width,
                  height: widget.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(_width, widget.height),
                        painter: _TimelinePainter(
                          geo: geo,
                          points: pts,
                          meals: widget.meals.where((m) => m.at.isAfter(_start)).toList(),
                          selected: sel,
                          now: widget.now,
                        ),
                      ),
                      if (sel != null) _tooltip(geo, pts, sel),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _tooltip(_Geometry geo, List<GlucosePoint> pts, int i) {
    final p = pts[i];
    final prev = i > 0 ? pts[i - 1] : null;
    final trend = prev == null ? Trend.flat : trendFromDelta(p.mmol - prev.mmol);
    final text = '${hhmm(p.at)} - ${p.mmol.toStringAsFixed(1)} mmol/L • ${trendLabel(trend)}';
    const w = 196.0;
    final left = (geo.x(p.at) - w / 2).clamp(4.0, _width - w - 4);
    final top = math.max(0.0, geo.y(p.mmol) - 46);
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: KColor.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: glucoseColor(p.mmol).withValues(alpha: 0.6)),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12)],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: KText.caption.copyWith(color: KColor.text, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _Geometry {
  _Geometry(this.w, this.start, this.width, List<GlucosePoint> pts) {
    final values = pts.map((p) => p.mmol);
    lo = math.min(2.5, values.isEmpty ? 2.5 : values.reduce(math.min) - 0.5);
    hi = math.max(13.0, values.isEmpty ? 13.0 : values.reduce(math.max) + 1.0);
  }

  final GlucoseTimeline w;
  final DateTime start;
  final double width;
  late final double lo;
  late final double hi;

  static const top = 26.0; // ruimte voor maaltijdlabels
  static const bottom = 22.0; // ruimte voor uurlabels
  static const left = 8.0;

  double x(DateTime t) =>
      left + t.difference(start).inSeconds / 3600.0 * w.pxPerHour;

  double y(double mmol) {
    final h = w.height - top - bottom;
    return top + h * (1 - (mmol - lo) / (hi - lo));
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.geo,
    required this.points,
    required this.meals,
    required this.selected,
    required this.now,
  });

  final _Geometry geo;
  final List<GlucosePoint> points;
  final List<FoodLogEntry> meals;
  final int? selected;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final right = geo.x(now);

    // Doelbereik 4.2 - 9.0
    final band = Rect.fromLTRB(0, geo.y(targetHigh), size.width, geo.y(targetLow));
    canvas.drawRect(band, Paint()..color = KColor.teal.withValues(alpha: 0.07));
    _dashed(canvas, geo.y(targetHigh), size.width, KColor.teal.withValues(alpha: 0.35));
    _dashed(canvas, geo.y(targetLow), size.width, KColor.teal.withValues(alpha: 0.35));
    _dashed(canvas, geo.y(hypoBelow), size.width, KColor.danger.withValues(alpha: 0.45));

    // Uurlabels
    final labelStyle = KText.caption.copyWith(fontSize: 10, color: KColor.textMuted);
    var hour = DateTime(geo.start.year, geo.start.month, geo.start.day, geo.start.hour + 1);
    while (hour.isBefore(now)) {
      final x = geo.x(hour);
      canvas.drawLine(
        Offset(x, _Geometry.top),
        Offset(x, size.height - _Geometry.bottom),
        Paint()..color = KColor.border.withValues(alpha: 0.6),
      );
      if (hour.hour % 2 == 0) _text(canvas, '${two(hour.hour)}:00', Offset(x, size.height - 14), labelStyle);
      hour = hour.add(const Duration(hours: 1));
    }

    // "Nu"-lijn
    canvas.drawLine(
      Offset(right, _Geometry.top - 6),
      Offset(right, size.height - _Geometry.bottom),
      Paint()
        ..color = KColor.tealLight.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    _text(canvas, 'NU', Offset(right, size.height - 14), labelStyle.copyWith(color: KColor.tealLight, fontWeight: FontWeight.w800));

    // Curve, met een onderbreking bij gaten > 15 min.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = KColor.tealLight;
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

    // Meetpunten
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = Offset(geo.x(p.at), geo.y(p.mmol));
      final c = glucoseColor(p.mmol);
      if (i == selected) {
        canvas.drawCircle(o, 9, Paint()..color = c.withValues(alpha: 0.25));
        canvas.drawCircle(o, 5.5, Paint()..color = c);
        canvas.drawCircle(o, 5.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = KColor.text);
      } else {
        canvas.drawCircle(o, 2.6, Paint()..color = c);
      }
    }

    // Maaltijdlabels (koolhydraten) bovenin
    for (final m in meals) {
      final carbs = m.carbs;
      if (carbs == null || carbs <= 0) continue;
      final x = geo.x(m.at);
      canvas.drawLine(
        Offset(x, 18),
        Offset(x, size.height - _Geometry.bottom),
        Paint()
          ..color = KColor.warning.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );
      final label = '${grams(carbs)}g';
      final tp = _layout(label, KText.caption.copyWith(fontSize: 10, color: KColor.bg, fontWeight: FontWeight.w800));
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 10), width: tp.width + 10, height: 16),
        const Radius.circular(8),
      );
      canvas.drawRRect(r, Paint()..color = KColor.warning);
      tp.paint(canvas, Offset(x - tp.width / 2, 10 - tp.height / 2));
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
      old.points != points || old.selected != selected || old.meals != meals || old.now != now;
}
