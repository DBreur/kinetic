// muscle_figure.dart — een klein spierfiguurtje als icoon van een oefening:
// voor- en achteraanzicht naast elkaar, met de spiergroepen die de oefening
// traint ingekleurd. Een man of een vrouw, naar het geslacht in je profiel
// (AppController zet [MuscleFigure.female]).

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';

class MuscleFigure extends StatelessWidget {
  const MuscleFigure({super.key, required this.groups, this.size = 40});

  /// Spiergroepen uit kExerciseLibrary's kMuscleGroups.
  final List<String> groups;
  final double size;

  /// Vrouwtje i.p.v. mannetje — gezet vanuit het profiel.
  static final female = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: female,
      builder: (context, isFemale, _) => CustomPaint(
        size: Size.square(size),
        painter: MuscleFigurePainter(
          groups: groups.toSet(),
          female: isFemale,
        ),
      ),
    );
  }
}

class MuscleFigurePainter extends CustomPainter {
  MuscleFigurePainter({required this.groups, required this.female});

  final Set<String> groups;
  final bool female;

  static const _base = Color(0x2EFFFFFF);
  static const _skin = Color(0x1FFFFFFF);
  static const _hair = Color(0x24FFFFFF);
  static const _hit = AppColor.coral;

  @override
  void paint(Canvas canvas, Size size) {
    // Ontwerp in een vlak van 100×100: vooraanzicht links (x 0–50),
    // achteraanzicht rechts (x 50–100).
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate(
      (size.width - 100 * s) / 2,
      (size.height - 100 * s) / 2,
    );
    canvas.scale(s);
    _figure(canvas, 0, front: true);
    _figure(canvas, 50, front: false);
    canvas.restore();
  }

  /// x-coördinaat in een figuur (0–50, midden 25) → canvas, met een vrouwelijk
  /// silhouet: smaller bovenlijf, bredere heupen en benen.
  double _x(double ox, double x, double y) {
    final f = !female ? 1.0 : (y < 44 ? .88 : (y < 60 ? 1.1 : 1.04));
    return ox + 25 + (x - 25) * f;
  }

  Paint _paint(String? group) => Paint()
    ..color = group != null && groups.contains(group) ? _hit : _base;

  void _rect(
    Canvas c,
    double ox,
    double x1,
    double y1,
    double x2,
    double y2,
    String? group, {
    double r = 2.5,
    bool mirror = false,
  }) {
    void one(double a, double b) {
      final l = _x(ox, a, (y1 + y2) / 2);
      final rr = _x(ox, b, (y1 + y2) / 2);
      c.drawRRect(
        RRect.fromLTRBR(
          l < rr ? l : rr,
          y1,
          l < rr ? rr : l,
          y2,
          Radius.circular(r),
        ),
        _paint(group),
      );
    }

    one(x1, x2);
    if (mirror) one(50 - x1, 50 - x2);
  }

  void _circle(
    Canvas c,
    double ox,
    double x,
    double y,
    double r,
    String? group, {
    bool mirror = false,
  }) {
    c.drawCircle(Offset(_x(ox, x, y), y), r, _paint(group));
    if (mirror) c.drawCircle(Offset(_x(ox, 50 - x, y), y), r, _paint(group));
  }

  /// Taps toelopend vlak (lats): breed bovenaan, smaller onderaan.
  void _lat(Canvas c, double ox, {required bool left}) {
    final sign = left ? -1.0 : 1.0;
    Offset p(double dx, double y) => Offset(_x(ox, 25 + sign * dx, y), y);
    final path = Path()
      ..moveTo(p(1, 26).dx, 26)
      ..lineTo(p(9.5, 26).dx, 26)
      ..lineTo(p(6.5, 42).dx, 42)
      ..lineTo(p(1, 42).dx, 42)
      ..close();
    c.drawPath(path, _paint('Lats'));
  }

  void _figure(Canvas c, double ox, {required bool front}) {
    // Haar achter het hoofd (vrouw): langer haar tot op de schouders.
    if (female) {
      c.drawRRect(
        RRect.fromLTRBR(
          ox + 18,
          3,
          ox + 32,
          front ? 20 : 22,
          const Radius.circular(7),
        ),
        Paint()..color = _hair,
      );
    }
    // Hoofd
    c.drawCircle(Offset(ox + 25, 9), 5.5, Paint()..color = _skin);
    if (!front && female) {
      c.drawCircle(Offset(ox + 25, 9), 5.5, Paint()..color = _hair);
    }
    // Nek
    _rect(c, ox, 22.8, 14.5, 27.2, 19, 'Nek', r: 1.5);
    // Schouders
    _circle(c, ox, 15.5, 22.5, 4.3, 'Schouders', mirror: true);
    // Bovenarm: biceps voor, triceps achter
    _rect(
      c,
      ox,
      10.5,
      25,
      15,
      37,
      front ? 'Biceps' : 'Triceps',
      mirror: true,
    );
    // Onderarmen + handen
    _rect(c, ox, 9, 38.5, 13.5, 51, 'Onderarmen', mirror: true);
    _circle(c, ox, 11, 54, 2.2, null, mirror: true);

    if (front) {
      // Borst
      _rect(c, ox, 17.5, 19.5, 24.4, 30, 'Borst', mirror: true, r: 3);
      // Buik
      _rect(c, ox, 19.5, 31, 30.5, 47.5, 'Buik', r: 3);
      // Heup
      _rect(c, ox, 18, 48.5, 32, 54, null, r: 3);
      // Quadriceps
      _rect(c, ox, 17.5, 55, 24.4, 76, 'Quadriceps', mirror: true, r: 3.5);
    } else {
      // Bovenrug (trapezius)
      _rect(c, ox, 18.5, 17.5, 31.5, 25.5, 'Bovenrug', r: 3);
      // Lats
      _lat(c, ox, left: true);
      _lat(c, ox, left: false);
      // Onderrug
      _rect(c, ox, 20.5, 42.5, 29.5, 48.5, 'Onderrug', r: 2);
      // Billen
      _rect(c, ox, 17.5, 49, 24.4, 58, 'Billen', mirror: true, r: 4);
      // Hamstrings
      _rect(c, ox, 17.5, 59, 24.4, 76, 'Hamstrings', mirror: true, r: 3.5);
    }
    // Onderbenen
    _rect(c, ox, 18.5, 78, 23.8, 95, 'Kuiten', mirror: true, r: 2.5);
  }

  @override
  bool shouldRepaint(MuscleFigurePainter old) =>
      old.female != female ||
      old.groups.length != groups.length ||
      !old.groups.containsAll(groups);
}
