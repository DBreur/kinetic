// technique_map_screen.dart — "Voortgang": een visuele kaart van technieken
// als verbindingen tussen posities. Van/naar, hernoemen en verwijderen gaan
// via technique_edit_screen.dart (het tabblad Technieken) — dit scherm is
// alleen om te bekijken en knopen/verbindingen te selecteren. Zie
// lib/core/positions.dart voor de posities, de transitieparser en de
// gedeelde kleur-/meetkundehelpers (ook gebruikt door de CustomPainter
// hieronder).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/positions.dart';
import '../models/technique.dart';
import '../repositories/technique_repository.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/ground_position_tags.dart';
import 'technique_detail_screen.dart';
import 'technique_edit_screen.dart';

class TechniqueMapScreen extends StatefulWidget {
  const TechniqueMapScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.techniques,
  });

  final TechniqueRepository repository;
  final String userId;
  final List<Technique> techniques;

  @override
  State<TechniqueMapScreen> createState() => _TechniqueMapScreenState();
}

class _TechniqueMapScreenState extends State<TechniqueMapScreen> {
  late List<Technique> _techniques;

  /// Null = geen selectie. Een `String` = een geselecteerd knooppunt
  /// (positienaam). Een `(String, String)`-record = een geselecteerde
  /// verbinding (van, naar) — records vergelijken op waarde, dus "nogmaals
  /// tikken heft de selectie op" blijft werken ook al wordt de lijst van
  /// verbindingen bij elke build opnieuw opgebouwd.
  Object? _selection;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _techniques = List.of(widget.techniques);
  }

  void _selectNode(String position) {
    setState(() => _selection = _selection == position ? null : position);
  }

  void _selectConnection(String from, String to) {
    final key = (from, to);
    setState(() => _selection = _selection == key ? null : key);
  }

  Future<void> _openTechnique(Technique t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueDetailScreen(
          repository: widget.repository,
          userId: widget.userId,
          technique: t,
        ),
      ),
    );
    if (changed == true) {
      _changed = true;
      final list = await widget.repository.listForUser(widget.userId);
      if (mounted) setState(() => _techniques = list);
    }
  }

  Future<void> _editTechnique(Technique t) async {
    final result = await Navigator.push<TechniqueEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueEditScreen(
          repository: widget.repository,
          userId: widget.userId,
          technique: t,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _changed = true;
    setState(() {
      if (result.deleted) {
        _techniques.removeWhere((x) => x.id == t.id);
      } else if (result.technique != null) {
        final i = _techniques.indexWhere((x) => x.id == t.id);
        if (i != -1) _techniques[i] = result.technique!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          backgroundColor: AppColor.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
          title: Text(
            'Voortgang',
            style: AppText.bodyStrong.copyWith(fontSize: 14),
          ),
        ),
        body: _buildMapView(),
      ),
    );
  }

  Widget _buildMapView() {
    final connections = groupConnections(_techniques);
    final onMap = _techniques.where(isOnMap).toList();
    final offMap = _techniques.where((t) => !isOnMap(t)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _buildProgressSummary(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(constraints.maxWidth, 420.0);
            final size = Size(width, width * kMapHeight / kMapWidth);
            return Center(
              child: SizedBox(
                key: const Key('techniqueMapCanvas'),
                width: size.width,
                height: size.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      _handleMapTap(details.localPosition, size, connections),
                  child: CustomPaint(
                    size: size,
                    painter: _MapPainter(
                      techniques: onMap,
                      connections: connections,
                      selection: _selection,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildSelectionList(),
        if (offMap.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('NIET OP DE KAART', style: AppText.overline),
          const SizedBox(height: 10),
          for (final t in offMap)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _editTechnique(t),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColor.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(t.name, style: AppText.bodyStrong),
                      ),
                      Text(
                        'Indelen',
                        style: AppText.caption.copyWith(
                          color: AppColor.tealBright,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16, color: AppColor.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildProgressSummary() {
    final mastered = _techniques.where((t) => masteryScore(t) >= 4).length;
    final inProgress = _techniques
        .where((t) => masteryScore(t) >= 1 && masteryScore(t) < 4)
        .length;
    final notDone = _techniques.length - mastered - inProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (_techniques.isEmpty) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(height: 8, width: w, color: AppColor.surfaceMuted),
              );
            }
            final total = _techniques.length;
            final masteredW = w * mastered / total;
            final inProgressW = w * inProgress / total;
            final notDoneW = (w - masteredW - inProgressW).clamp(0.0, w);
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Container(width: masteredW, height: 8, color: AppColor.greenBright),
                  Container(width: inProgressW, height: 8, color: AppColor.teal),
                  Container(width: notDoneW, height: 8, color: AppColor.surfaceMuted),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '$mastered beheerst · $inProgress bezig · $notDone nog niet gedaan',
          style: AppText.caption,
        ),
      ],
    );
  }

  void _handleMapTap(Offset pos, Size canvasSize, List<ConnectionStats> connections) {
    for (final name in kAllNodes) {
      final rect = nodeRect(name, canvasSize);
      final hit = Rect.fromCenter(
        center: rect.center,
        width: math.max(rect.width, 44),
        height: math.max(rect.height, 44),
      );
      if (hit.contains(pos)) {
        _selectNode(name);
        return;
      }
    }
    for (final conn in connections) {
      final from = positionOffset(conn.from, canvasSize);
      final to = positionOffset(conn.to, canvasSize);
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final hit = Rect.fromCenter(center: mid, width: 44, height: 44);
      if (hit.contains(pos)) {
        _selectConnection(conn.from, conn.to);
        return;
      }
    }
  }

  Widget _buildSelectionList() {
    final sel = _selection;
    String title;
    List<Technique> items;
    if (sel == null) {
      title = 'Waar moet je aan werken';
      items = _techniques
          .where(
            (t) =>
                masteryScore(t) <= 2 ||
                t.learningStatus == LearningStatus.learning,
          )
          .toList();
    } else if (sel is String) {
      final departing = _techniques
          .where((t) => parseTransition(t.transition)?.from == sel)
          .toList();
      if (departing.isNotEmpty) {
        title = 'Vanuit $sel';
        items = departing;
      } else {
        title = 'Naar $sel';
        items = _techniques.where((t) => arrivesAt(t, sel)).toList();
      }
    } else if (sel is (String, String)) {
      final (from, to) = sel;
      title = '$from → $to';
      items = _techniques.where((t) {
        final p = parseTransition(t.transition);
        return p?.from == from && p?.to == to;
      }).toList();
    } else {
      title = '';
      items = const [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: AppText.overline),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text('Niets te zien hier.', style: AppText.caption)
        else
          for (final t in items)
            _TechniqueMapRow(technique: t, onTap: () => _openTechnique(t)),
      ],
    );
  }
}

class _TechniqueMapRow extends StatelessWidget {
  const _TechniqueMapRow({required this.technique, required this.onTap});
  final Technique technique;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = masteryScore(technique);
    final color = colorForMasteryScore(score);
    final rating = score.round();
    final count = technique.updates.length;
    final lastDate = technique.updates.isEmpty
        ? null
        : technique.updates.map((u) => u.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final stars = rating > 0 ? '★' * rating + '☆' * (5 - rating) : 'nog niet beoordeeld';
    final meta = [
      '$count×',
      if (lastDate != null) 'laatst ${dutchShortDate(lastDate)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              technique.name,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (technique.learningStatus ==
                              LearningStatus.learning) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColor.tealBright,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(meta, style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stars,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: rating > 0
                          ? AppColor.amberBright
                          : AppColor.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
            if (technique.groundPositions.isNotEmpty ||
                technique.transition.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: GroundPositionTags(
                  transition: technique.transition,
                  positions: technique.groundPositions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<Technique> techniques;
  final List<ConnectionStats> connections;
  final Object? selection;

  _MapPainter({
    required this.techniques,
    required this.connections,
    required this.selection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final conn in connections) {
      final from = positionOffset(conn.from, size);
      final to = positionOffset(conn.to, size);
      final targetRect = nodeRect(conn.to, size);
      final anchor = arrowAnchorPoint(from, to, targetRect);
      final linePaint = Paint()
        ..color = conn.color
        ..strokeWidth = conn.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (conn.everRated) {
        canvas.drawLine(from, anchor, linePaint);
      } else {
        _drawDashedLine(canvas, from, anchor, linePaint);
      }
      _drawArrowHead(canvas, anchor, to, conn.color);
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      _drawBadge(canvas, mid, conn.techniques.length, selection == (conn.from, conn.to));
    }

    for (final name in kAllNodes) {
      final rect = nodeRect(name, size);
      final departing = techniques
          .where((t) => parseTransition(t.transition)?.from == name)
          .toList();
      // Via arrivesAt() telt een Submission-techniek ook zonder kaart-
      // transitie mee bij het Submission-knooppunt — net zo gewoon als een
      // techniek met een echte verbinding, zodat kleur én aantal kloppen.
      final arriving = techniques.where((t) => arrivesAt(t, name)).toList();
      final hasLearning = [...departing, ...arriving].any(
        (t) => t.learningStatus == LearningStatus.learning,
      );
      _drawNode(
        canvas,
        rect,
        name,
        departing,
        arriving,
        selection == name,
        hasLearning,
      );
    }
  }

  void _drawNode(
    Canvas canvas,
    Rect rect,
    String name,
    List<Technique> departing,
    List<Technique> arriving,
    bool selected,
    bool hasLearning,
  ) {
    // Randkleur = gemiddelde beheersing van de vertrekkende technieken — voor
    // een knoop waar nooit iets vertrekt (een afgeronde score, zie
    // kOutcomes) telt in plaats daarvan de beheersing van wat er aankomt.
    final masteryGroup = departing.isNotEmpty ? departing : arriving;
    final borderColor = masteryGroup.isNotEmpty
        ? colorForMasteryScore(
            masteryGroup.fold<double>(0, (s, t) => s + masteryScore(t)) /
                masteryGroup.length,
          )
        : const Color(0x33FFFFFF);
    final bg = selected ? AppColor.surfaceHighest : AppColor.surface;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = bg);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (hasLearning) {
      canvas.drawCircle(
        Offset(rect.right - 7, rect.top + 7),
        3.5,
        Paint()..color = AppColor.tealBright,
      );
    }
    // Voor een gewone positie telt wat er vertrekt; voor een afgeronde score
    // (Takedown/Submission) vertrekt nooit iets, dus telt wat er aankomt —
    // in beide gevallen gewoon het aantal, net als elk ander knooppunt.
    final count = departing.isNotEmpty ? departing.length : arriving.length;
    final subtitle = count == 0
        ? 'nog leeg'
        : '$count techniek${count == 1 ? '' : 'en'}';
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$name\n',
            style: AppText.bodyStrong.copyWith(
              color: AppColor.ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          TextSpan(
            text: subtitle,
            style: AppText.caption.copyWith(
              color: AppColor.inkFaint,
              fontSize: 8,
              height: 1.15,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 6);
    tp.paint(
      canvas,
      Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
    );
  }

  void _drawBadge(Canvas canvas, Offset center, int count, bool selected) {
    const radius = 11.0;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = selected ? AppColor.tealWash : AppColor.bgDeep,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColor.lineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: AppText.bodyStrong.copyWith(
          color: AppColor.ink,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset towards, Color color) {
    final dir = towards - tip;
    final len = dir.distance;
    if (len == 0) return;
    final unit = Offset(dir.dx / len, dir.dy / len);
    final normal = Offset(-unit.dy, unit.dx);
    const arrowSize = 7.0;
    final p2 = tip - unit * arrowSize + normal * (arrowSize * 0.6);
    final p3 = tip - unit * arrowSize - normal * (arrowSize * 0.6);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    final total = (to - from).distance;
    if (total == 0) return;
    final dir = Offset((to.dx - from.dx) / total, (to.dy - from.dy) / total);
    var drawn = 0.0;
    while (drawn < total) {
      final segStart = from + dir * drawn;
      final segEnd = from + dir * math.min(drawn + dash, total);
      canvas.drawLine(segStart, segEnd, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.techniques != techniques ||
      oldDelegate.connections != connections ||
      oldDelegate.selection != selection;
}
