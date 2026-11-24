// system_graph.dart: tekent een TechniqueSystem als gelaagde flow-graaf
// (wortels boven, pijlen omlaag): de interactieve versie voor de editor en
// een kleine preview voor de systeemkaarten. Kleur per soort node, altijd
// samen met een icoon en de legenda (nooit alleen kleur).

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/technique_system.dart';
import '../../theme/kinetic_theme.dart';

Color systemKindColor(KineticColors k, SystemNodeKind kind) => switch (kind) {
  SystemNodeKind.position => k.blue,
  SystemNodeKind.technique => k.accent,
  SystemNodeKind.finish => k.purple,
};

IconData systemKindIcon(SystemNodeKind kind) => switch (kind) {
  SystemNodeKind.position => Icons.accessibility_new,
  SystemNodeKind.technique => Icons.bolt,
  SystemNodeKind.finish => Icons.flag_outlined,
};

/// Korte naam voor chips en de legenda.
String systemKindShort(SystemNodeKind kind) => switch (kind) {
  SystemNodeKind.position => 'Positie',
  SystemNodeKind.technique => 'Techniek',
  SystemNodeKind.finish => 'Finish',
};

/// "1 positie", "2 technieken", "3 finishes".
String systemKindCount(SystemNodeKind kind, int n) => switch (kind) {
  SystemNodeKind.position => n == 1 ? '1 positie' : '$n posities',
  SystemNodeKind.technique => n == 1 ? '1 techniek' : '$n technieken',
  SystemNodeKind.finish => n == 1 ? '1 finish' : '$n finishes',
};

/// Vlakkleur van een node: de soortkleur getint over het kaartvlak.
Color systemKindFill(KineticColors k, SystemNodeKind kind) =>
    Color.alphaBlend(systemKindColor(k, kind).withValues(alpha: k.isDark ? 0.18 : 0.10), k.surface);

class GraphMetrics {
  const GraphMetrics({this.nodeW = 116, this.nodeH = 52, this.gapX = 14, this.gapY = 56, this.pad = 20});
  final double nodeW;
  final double nodeH;
  final double gapX;
  final double gapY;
  final double pad;
}

/// Rechthoek per node-id. Binnen een laag sorteren we op het gemiddelde van
/// de ouders (barycenter), zodat er minder pijlen kruisen.
Map<String, Rect> layoutSystem(TechniqueSystem s, [GraphMetrics m = const GraphMetrics()]) {
  final layers = systemLayers(s);
  final byLayer = <int, List<SystemNode>>{};
  for (final n in s.nodes) {
    byLayer.putIfAbsent(layers[n.id] ?? 0, () => []).add(n);
  }
  final parents = <String, List<String>>{};
  for (final e in s.edges) {
    parents.putIfAbsent(e.to, () => []).add(e.from);
  }
  final order = byLayer.keys.toList()..sort();
  final slot = <String, double>{};
  for (final layer in order) {
    final row = byLayer[layer]!;
    if (layer > 0) {
      double bary(SystemNode n, int fallback) {
        final ps = (parents[n.id] ?? const []).where(slot.containsKey).toList();
        if (ps.isEmpty) return fallback.toDouble();
        return ps.map((p) => slot[p]!).reduce((a, b) => a + b) / ps.length;
      }

      final indexed = [for (var i = 0; i < row.length; i++) (row[i], bary(row[i], i))];
      indexed.sort((a, b) => a.$2.compareTo(b.$2));
      row
        ..clear()
        ..addAll(indexed.map((x) => x.$1));
    }
    for (var i = 0; i < row.length; i++) {
      slot[row[i].id] = i - (row.length - 1) / 2;
    }
  }
  final maxCount = byLayer.values.fold<int>(0, (mx, l) => math.max(mx, l.length));
  final width = m.pad * 2 + maxCount * m.nodeW + math.max(0, maxCount - 1) * m.gapX;
  final rects = <String, Rect>{};
  for (final layer in order) {
    final row = byLayer[layer]!;
    final rowWidth = row.length * m.nodeW + (row.length - 1) * m.gapX;
    var x = (width - rowWidth) / 2;
    final y = m.pad + layer * (m.nodeH + m.gapY);
    for (final n in row) {
      rects[n.id] = Rect.fromLTWH(x, y, m.nodeW, m.nodeH);
      x += m.nodeW + m.gapX;
    }
  }
  return rects;
}

Size _canvasSize(Map<String, Rect> rects, double pad) {
  var w = 0.0, h = 0.0;
  for (final r in rects.values) {
    w = math.max(w, r.right);
    h = math.max(h, r.bottom);
  }
  return Size(w + pad, h + pad);
}

/// Tekent de pijlen tussen de rechthoeken.
void paintEdges(Canvas canvas, List<SystemEdge> edges, Map<String, Rect> rects, Color color, {double width = 1.6, double head = 7}) {
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  final fill = Paint()..color = color;
  for (final e in edges) {
    final a = rects[e.from];
    final b = rects[e.to];
    if (a == null || b == null) continue;
    final Offset start, end, c1, c2;
    if (b.top >= a.bottom - 0.5) {
      start = a.bottomCenter;
      end = b.topCenter;
      final midY = (start.dy + end.dy) / 2;
      c1 = Offset(start.dx, midY);
      c2 = Offset(end.dx, midY);
    } else if (b.bottom <= a.top + 0.5) {
      // Terug naar een hogere laag (cyclus): langs de zijkant omhoog.
      start = a.centerRight;
      end = b.centerRight;
      final bulge = math.max(a.right, b.right) + 36;
      c1 = Offset(bulge, start.dy);
      c2 = Offset(bulge, end.dy);
    } else {
      // Zelfde laag: zijkant naar zijkant met een boog.
      final leftToRight = a.center.dx < b.center.dx;
      start = leftToRight ? a.centerRight : a.centerLeft;
      end = leftToRight ? b.centerLeft : b.centerRight;
      final lift = a.height * 0.9;
      c1 = Offset(start.dx + (end.dx - start.dx) / 3, start.dy - lift);
      c2 = Offset(end.dx - (end.dx - start.dx) / 3, end.dy - lift);
    }
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    canvas.drawPath(path, line);
    var dir = end - c2;
    if (dir.distance < 0.01) dir = end - start;
    final u = dir / dir.distance;
    final n = Offset(-u.dy, u.dx);
    final tip = end;
    final base = tip - u * head;
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + n.dx * head * 0.55, base.dy + n.dy * head * 0.55)
      ..lineTo(base.dx - n.dx * head * 0.55, base.dy - n.dy * head * 0.55)
      ..close();
    canvas.drawPath(arrow, fill);
  }
}

/// Interactieve graaf (knijpen om te zoomen, slepen om te schuiven).
class SystemGraph extends StatelessWidget {
  const SystemGraph({super.key, required this.system, required this.onNodeTap, this.highlightNodeId});

  final TechniqueSystem system;
  final ValueChanged<SystemNode> onNodeTap;
  final String? highlightNodeId;

  static const metrics = GraphMetrics();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final rects = layoutSystem(system, metrics);
    final size = _canvasSize(rects, metrics.pad);
    return LayoutBuilder(
      builder: (context, box) {
        final canvas = Size(math.max(size.width, box.maxWidth), math.max(size.height, box.maxHeight));
        final shift = Offset((canvas.width - size.width) / 2, 0);
        final placed = rects.map((id, r) => MapEntry(id, r.shift(shift)));
        return InteractiveViewer(
          constrained: false,
          minScale: 0.5,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(48),
          child: SizedBox(
            width: canvas.width,
            height: canvas.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _EdgePainter(edges: system.edges, rects: placed, color: k.textMuted)),
                ),
                for (final n in system.nodes)
                  if (placed[n.id] != null)
                    Positioned.fromRect(
                      rect: placed[n.id]!,
                      child: _NodeBox(node: n, highlighted: n.id == highlightNodeId, onTap: () => onNodeTap(n)),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({required this.node, required this.highlighted, required this.onTap});
  final SystemNode node;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = systemKindColor(k, node.kind);
    return Semantics(
      button: true,
      label: '${systemKindShort(node.kind)}: ${node.label}',
      child: Material(
        color: systemKindFill(k, node.kind),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.sm + 2),
          side: BorderSide(color: highlighted ? k.text : c, width: highlighted ? 2.5 : 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(systemKindIcon(node.kind), size: 14, color: c),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    node.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.caption.copyWith(color: k.text, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
                if (node.techniqueId != null) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.link, size: 12, color: k.textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.rects, required this.color});
  final List<SystemEdge> edges;
  final Map<String, Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintEdges(canvas, edges, rects, color);

  @override
  bool shouldRepaint(_EdgePainter old) => old.edges != edges || old.rects != rects || old.color != color;
}

/// Kleine, niet-interactieve preview van een systeem (voor de lijstkaarten).
class SystemPreview extends StatelessWidget {
  const SystemPreview({super.key, required this.system, this.height = 96});
  final TechniqueSystem system;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _PreviewPainter(system: system, k: k)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({required this.system, required this.k});
  final TechniqueSystem system;
  final KineticColors k;

  static const _m = GraphMetrics(nodeW: 64, nodeH: 20, gapX: 10, gapY: 22, pad: 6);

  @override
  void paint(Canvas canvas, Size size) {
    if (system.nodes.isEmpty) return;
    final rects = layoutSystem(system, _m);
    final graph = _canvasSize(rects, _m.pad);
    final scale = math.min(1.0, math.min(size.width / graph.width, size.height / graph.height));
    canvas.save();
    canvas.translate((size.width - graph.width * scale) / 2, (size.height - graph.height * scale) / 2);
    canvas.scale(scale);
    paintEdges(canvas, system.edges, rects, k.textMuted, width: 1.2, head: 5);
    for (final n in system.nodes) {
      final r = rects[n.id];
      if (r == null) continue;
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
      canvas.drawRRect(rr, Paint()..color = systemKindFill(k, n.kind));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = systemKindColor(k, n.kind)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.system != system || old.k != k;
}

/// Legenda: kleur + icoon + naam per soort.
class SystemLegend extends StatelessWidget {
  const SystemLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final kind in SystemNodeKind.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: systemKindFill(k, kind),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: systemKindColor(k, kind), width: 1.2),
                ),
                child: Icon(systemKindIcon(kind), size: 13, color: systemKindColor(k, kind)),
              ),
              const SizedBox(width: 6),
              Text(systemKindShort(kind), style: context.t.caption),
            ],
          ),
      ],
    );
  }
}
