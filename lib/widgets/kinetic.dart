// kinetic.dart — gedeelde bouwstenen van de Kinetic-stijl.
//
// Vlakke kaarten zonder schaduw (diepte via kleurstappen), uppercase
// label-mono kopjes, statuspillen met een sensor-stip en een ringmeter.
// Zie design/stitch_sambo_diabetic_fitness_tracker/kinetic_sambo_metric.

import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/glucose.dart';
import '../services/system_bars.dart';
import '../theme/kinetic_theme.dart';

// ───────────────────────────── logo ─────────────────────────────────────────

/// Kinetic-merkteken: open ijsblauwe ring met een koraalrode chevron.
class KLogo extends StatelessWidget {
  const KLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size + 8,
    height: size + 8,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColor.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: CustomPaint(painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .38;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi * .35,
      math.pi * 1.75,
      false,
      Paint()
        ..color = AppColor.iceDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * .09
        ..strokeCap = StrokeCap.round,
    );
    final s = r * .42;
    final path = Path()
      ..moveTo(c.dx - s * .45, c.dy - s)
      ..lineTo(c.dx + s * .65, c.dy)
      ..lineTo(c.dx - s * .45, c.dy + s);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColor.coral
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * .1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

// ───────────────────────────── topbalk ──────────────────────────────────────

/// Vaste kop bovenaan elk tabblad: merk + sectienaam, live glucosepil,
/// optionele extra knop en het profielrondje met een menu (Profiel /
/// Instellingen).
class KTopBar extends StatelessWidget {
  const KTopBar({
    super.key,
    required this.section,
    this.glucose,
    this.trailing,
    this.avatarUrl = '',
    this.initials = '',
    this.onProfile,
    this.onSettings,
  });

  final String section;
  final GlucoseSnapshot? glucose;
  final Widget? trailing;
  final String avatarUrl;
  final String initials;
  final VoidCallback? onProfile;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final reading = glucose?.reading;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return tp.width;
    }

    final clockStyle = AppText.bodyStrong.copyWith(
      color: AppColor.inkMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final showClock = SystemBars.hidden;
    final pillColor = reading == null
        ? AppColor.inkFaint
        : (reading.isStale
              ? AppColor.inkFaint
              : glucoseColor(glucoseStateFor(reading.mmol)));
    final value = reading == null ? '' : mmolText(reading.mmol);
    final fullText = '$value mmol/L';

    // Vaste breedtes (niets schaalt): klok, pil (met/zonder "mmol/L"),
    // exportknop, profielrondje.
    final clockW = showClock ? measure('00:00', clockStyle) + _itemGap : 0.0;
    double pillW(String text) => reading == null
        ? 0
        : KPill.widthFor(text, measure) + _itemGap;
    final double actionsW =
        (trailing != null ? _iconButton : 0.0) +
        (onProfile != null || onSettings != null ? _avatarBox : 0.0);

    final title = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KINETIC',
          style: AppText.cardTitle.copyWith(height: 1, letterSpacing: 1.6),
        ),
        const SizedBox(height: 3),
        Text(
          section.toUpperCase(),
          style: AppText.overline.copyWith(letterSpacing: 2),
        ),
      ],
    );

    List<Widget> info({required bool compact}) => [
      if (showClock) ...[
        KClock(style: clockStyle),
        const SizedBox(width: _itemGap),
      ],
      if (reading != null) ...[
        KPill(text: compact ? value : fullText, color: pillColor, dot: true),
        const SizedBox(width: _itemGap),
      ],
    ];
    final actions = <Widget>[
      ?trailing,
      if (onProfile != null || onSettings != null)
        PopupMenuButton<VoidCallback>(
          tooltip: 'Profiel en instellingen',
          offset: const Offset(0, 52),
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            if (onProfile != null)
              PopupMenuItem(
                value: onProfile,
                child: const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Profiel'),
                ),
              ),
            if (onSettings != null)
              PopupMenuItem(
                value: onSettings,
                child: const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('Instellingen'),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: KAvatar(url: avatarUrl, initials: initials, size: 34),
          ),
        ),
    ];
    Widget group(List<Widget> children) => Align(
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    return ColoredBox(
      color: AppColor.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = topBarLayout(
            width: constraints.maxWidth,
            titleWidth: _titleWidth(context),
            // Alleen met verborgen systeembalken staat de balk tegen de
            // bovenrand, en kan de camera er dus in vallen.
            cutout: SystemBars.hidden
                ? topCutout(MediaQuery.displayFeaturesOf(context), _height)
                : null,
            infoWidth: clockW + pillW(value),
            actionsWidth: actionsW,
          );
          // Past de pil mét "mmol/L" in het vak? Anders alleen het getal.
          final infoRoom = layout.split
              ? layout.beforeHole
              : (layout.clusterBeforeHole
                        ? layout.beforeHole
                        : layout.afterHole) -
                    actionsW;
          final compact = clockW + pillW(fullText) > infoRoom;
          final cluster = group([...info(compact: compact), ...actions]);
          final row = Row(
            children: [
              SizedBox(width: KTopBar._leftPad + layout.leftInset),
              const KLogo(),
              const SizedBox(width: _logoGap),
              title,
              const SizedBox(width: _titleGap),
              SizedBox(
                width: layout.beforeHole,
                child: layout.split
                    ? group(info(compact: compact))
                    : (layout.clusterBeforeHole ? cluster : null),
              ),
              SizedBox(width: layout.hole),
              // Flexibel: vangt afrondingsverschillen in de tekstbreedte op.
              Expanded(
                child: layout.split
                    ? group(actions)
                    : (layout.clusterBeforeHole ? const SizedBox() : cluster),
              ),
              const SizedBox(width: _rightPad),
            ],
          );
          final bar = SizedBox(height: _height, child: row);
          // Laatste redmiddel: nergens plek naast de camera → dan toch
          // onder de camera.
          return layout.fallbackBelow ? CutoutAwarePadding(child: bar) : bar;
        },
      ),
    );
  }

  static const _itemGap = 8.0;
  static const _iconButton = 48.0;
  static const _avatarBox = 50.0;
  static const _height = 64.0;
  static const _leftPad = AppSpace.gutter;
  static const _logoWidth = 40.0;
  static const _logoGap = AppSpace.sm + 2;
  static const _titleGap = AppSpace.md;
  static const _rightPad = 8.0;

  double _titleWidth(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double w(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return tp.width;
    }

    return math.max(
      w('KINETIC', AppText.cardTitle.copyWith(height: 1, letterSpacing: 1.6)),
      w(section.toUpperCase(), AppText.overline.copyWith(letterSpacing: 2)),
    );
  }
}

/// De camera-uitsparing die in een balk van [barHeight] bovenaan valt.
Rect? topCutout(List<DisplayFeature> features, double barHeight) {
  for (final f in features) {
    if (f.type != DisplayFeatureType.cutout) continue;
    if (f.bounds.top < barHeight && f.bounds.bottom > 0) return f.bounds;
  }
  return null;
}

/// Hoe de topbalk om een camera-uitsparing heen loopt.
class TopBarLayout {
  /// Extra ruimte vóór het logo (camera links).
  final double leftInset;

  /// Ruimte vóór en na het "gat" van de camera, en het gat zelf.
  final double beforeHole;
  final double hole;
  final double afterHole;

  /// Klok/glucose/knoppen links van de camera (anders rechts).
  final bool clusterBeforeHole;

  /// Verdeeld: klok + glucose links van de camera, knoppen rechts ervan.
  final bool split;

  /// Geen plek naast de camera: dan zakt de balk eronder.
  final bool fallbackBelow;

  const TopBarLayout({
    required this.leftInset,
    required this.beforeHole,
    required this.hole,
    required this.afterHole,
    required this.clusterBeforeHole,
    this.split = false,
    this.fallbackBelow = false,
  });
}

/// Pure berekening (te testen zonder scherm): de balk blijft tegen de
/// bovenrand; logo/titel en de rechterkant (klok, glucose, knoppen) gaan om
/// de camera heen in plaats van eronder.
TopBarLayout topBarLayout({
  required double width,
  required double titleWidth,
  Rect? cutout,
  double margin = 6,
  double infoWidth = 90,
  double actionsWidth = 98,
}) {
  // Kleinste vorm van de rechterkant: pil met alleen het getal.
  final minInfo = infoWidth;
  final minActions = actionsWidth;
  final minCluster = infoWidth + actionsWidth;
  const fixed =
      KTopBar._leftPad + KTopBar._logoWidth + KTopBar._logoGap + KTopBar._titleGap;
  var leftInset = 0.0;
  var titleEnd = fixed + titleWidth;
  final end = width - KTopBar._rightPad;

  // Uitsparing die niet binnen de breedte van de balk valt telt niet mee.
  if (cutout != null && (cutout.right <= 0 || cutout.left >= width)) {
    cutout = null;
  }
  if (cutout == null) {
    return TopBarLayout(
      leftInset: 0,
      beforeHole: math.max(0, end - titleEnd),
      hole: 0,
      afterHole: 0,
      clusterBeforeHole: true,
    );
  }
  final holeLeft = math.max(0.0, cutout.left - margin);
  final holeRight = math.min(width, cutout.right + margin);

  // Camera over logo/titel: die schuiven op tot rechts van de camera.
  if (holeLeft < titleEnd && holeRight > KTopBar._leftPad) {
    leftInset = holeRight - KTopBar._leftPad;
    titleEnd += leftInset;
    final room = end - titleEnd;
    return TopBarLayout(
      leftInset: leftInset,
      beforeHole: math.max(0, room),
      hole: 0,
      afterHole: 0,
      clusterBeforeHole: true,
      fallbackBelow: room < minCluster,
    );
  }

  // Camera in het rechterdeel: rechterkant links óf rechts van de camera,
  // waar de meeste ruimte is.
  final before = math.max(0.0, holeLeft - titleEnd);
  final after = math.max(0.0, end - holeRight);
  // Aan beide kanten plek: klok + glucose links, knoppen rechts van de
  // camera — dan hoeft niets kleiner.
  final split = before >= minInfo && after >= minActions;
  return TopBarLayout(
    leftInset: 0,
    beforeHole: before,
    hole: math.max(0.0, holeRight - holeLeft),
    afterHole: after,
    clusterBeforeHole: before >= after,
    split: split,
    fallbackBelow: !split && math.max(before, after) < minCluster,
  );
}

/// Rond profielplaatje: foto als die er is, anders initialen.
class KAvatar extends StatelessWidget {
  const KAvatar({
    super.key,
    required this.url,
    required this.initials,
    this.size = 40,
  });

  final String url;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: AppText.bodyStrong.copyWith(
          color: AppColor.ice,
          fontSize: size * .36,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColor.surfaceHigh,
        shape: BoxShape.circle,
        // Alleen een rand rond de initialen — rond een foto zou hij als
        // blauwe streepjes langs de randen van de foto ogen.
        border: url.isEmpty
            ? Border.all(color: AppColor.ice, width: size > 60 ? 2.5 : 1.5)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

// ───────────────────────────── kaarten ──────────────────────────────────────

/// Basiskaart: surface-container-low, 12px hoek, geen schaduw. Met [glow]
/// krijgt hij de HUD-gloed voor kritieke/piekmomenten.
class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.glow,
    this.color = AppColor.surface,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glow;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: glow == null
            ? null
            : Border.all(color: glow!.withValues(alpha: .35)),
        boxShadow: glow == null
            ? null
            : [BoxShadow(color: glow!.withValues(alpha: .12), blurRadius: 24)],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Kop van een kaart: icoon + uppercase label links, iets kleins rechts.
class KCardHeader extends StatelessWidget {
  const KCardHeader({
    super.key,
    required this.label,
    this.icon,
    this.iconColor = AppColor.ice,
    this.trailing,
    this.large = false,
  });

  final String label;
  final IconData? icon;
  final Color iconColor;
  final Widget? trailing;

  /// Groot = headline-sm (sectietitel), anders label-mono.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Text(
            large ? label : label.toUpperCase(),
            style: large
                ? AppText.cardTitle
                : AppText.overline.copyWith(color: AppColor.ink),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpace.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// Sectiekop buiten een kaart.
class KSectionTitle extends StatelessWidget {
  const KSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, AppSpace.md),
    child: Row(
      children: [
        Expanded(child: Text(title, style: AppText.cardTitle)),
        if (trailing != null)
          Text(trailing!.toUpperCase(), style: AppText.overline),
      ],
    ),
  );
}

// ───────────────────────────── labels & pillen ──────────────────────────────

/// Klein uppercase label (label-mono).
class KLabel extends StatelessWidget {
  const KLabel(this.text, {super.key, this.color = AppColor.inkFaint});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppText.overline.copyWith(color: color));
}

/// Afgeronde statuspil, optioneel met sensor-stip.
class KPill extends StatelessWidget {
  const KPill({
    super.key,
    required this.text,
    this.color = AppColor.ice,
    this.background = AppColor.surfaceHigh,
    this.dot = false,
  });

  final String text;
  final Color color;
  final Color background;
  final bool dot;

  static TextStyle _style(Color color) =>
      AppText.overline.copyWith(color: color, letterSpacing: 1);

  /// Breedte van een pil met stip voor [text], zonder hem te tekenen.
  static double widthFor(
    String text,
    double Function(String, TextStyle) measure,
  ) => 10 + 6 + 6 + measure(text.toUpperCase(), _style(AppColor.ink)) + 10 + 1;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[KDot(color: color, size: 6), const SizedBox(width: 6)],
        Text(
          text.toUpperCase(),
          style: AppText.overline.copyWith(color: color, letterSpacing: 1),
        ),
      ],
    ),
  );
}

/// Rechthoekige tag (4px hoek) — meetvlaggen en badges.
class KTag extends StatelessWidget {
  const KTag(
    this.text, {
    super.key,
    this.color = AppColor.ice,
    this.background = AppColor.surfaceHighest,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      text.toUpperCase(),
      style: AppText.overline.copyWith(
        color: color,
        fontSize: 10,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class KDot extends StatelessWidget {
  const KDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ───────────────────────────── meetwaarden ──────────────────────────────────

/// Tegel met label, grote waarde en eenheid (surface-container).
class KMetricTile extends StatelessWidget {
  const KMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.valueColor = AppColor.ink,
    this.captionColor = AppColor.ice,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final Color valueColor;
  final Color captionColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColor.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KLabel(label),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: value,
            style: AppText.cardTitle.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            children: [
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: AppText.caption.copyWith(color: AppColor.inkFaint),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: AppText.caption.copyWith(color: captionColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

/// Ringmeter: buitenring = [value] (0–1) in [color], binnenring = optionele
/// tweede waarde in koraal (bv. trainingsgrens). Inhoud in het midden.
class KRing extends StatelessWidget {
  const KRing({
    super.key,
    required this.value,
    required this.color,
    required this.child,
    this.inner,
    this.size = 192,
    this.stroke = 9,
  });

  final double value;
  final double? inner;
  final Color color;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _RingPainter(value.clamp(0, 1), inner?.clamp(0, 1), color, stroke),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.inner, this.color, this.stroke);

  final double value;
  final double? inner;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColor.surfaceHigh
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * .65,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    if (inner != null) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * .83),
        -math.pi / 2,
        math.pi * 2 * inner!,
        false,
        Paint()
          ..color = AppColor.coral.withValues(alpha: .4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * .33
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.inner != inner || old.color != color;
}

// ───────────────────────────── bediening ────────────────────────────────────

/// Gesegmenteerde schakelaar (pil-vorm), zoals "Combat Sambo | S&C".
class KSegmented<T> extends StatelessWidget {
  const KSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.activeColor = AppColor.coralSoft,
    this.activeInk = AppColor.coralInk,
  });

  final List<(T, String, IconData?)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color activeColor;
  final Color activeInk;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColor.bgDeep,
      borderRadius: BorderRadius.circular(AppRadius.xl),
    ),
    child: Row(
      children: [
        for (final (value, label, icon) in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == selected ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 18,
                        color: value == selected
                            ? activeInk
                            : AppColor.inkMuted,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          color: value == selected
                              ? activeInk
                              : AppColor.inkMuted,
                          fontWeight: value == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Rij voor een snelle actie: icoonvak, titel, ondertitel en een pijl/plus.
class KActionRow extends StatelessWidget {
  const KActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColor.coral,
    this.trailingIcon = Icons.arrow_forward,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) => KCard(
    padding: const EdgeInsets.all(16),
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColor.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.cardTitle),
              Text(subtitle, style: AppText.caption),
            ],
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColor.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(trailingIcon, size: 20, color: AppColor.ink),
        ),
      ],
    ),
  );
}

/// − waarde + teller.
class KStepper extends StatelessWidget {
  const KStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColor.bgDeep,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          filled: false,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppText.cardTitle.copyWith(
              fontSize: 22,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          filled: true,
          onTap: () => onChanged(value + 1),
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.filled, this.onTap});

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: filled ? AppColor.coralSoft : AppColor.surfaceHigh,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 20,
          color: filled
              ? AppColor.coralInk
              : (onTap == null ? AppColor.inkGhost : AppColor.ink),
        ),
      ),
    ),
  );
}

// ───────────────────────────── glucose-helpers ──────────────────────────────

/// Positie van een waarde op de vaste schaal 2–14 mmol/L (0–1), voor ringen.
double glucoseFraction(double mmol) => ((mmol - 2) / 12).clamp(0.0, 1.0);

const trendArrow = {
  Trend.up: Icons.north,
  Trend.slightUp: Icons.north_east,
  Trend.flat: Icons.east,
  Trend.slightDown: Icons.south_east,
  Trend.down: Icons.south,
  Trend.fastDown: Icons.keyboard_double_arrow_down,
};

const trendLabel = {
  Trend.up: 'stijgend',
  Trend.slightUp: 'licht stijgend',
  Trend.flat: 'stabiel',
  Trend.slightDown: 'licht dalend',
  Trend.down: 'dalend',
  Trend.fastDown: 'snel dalend',
};

/// De vijf hoofdtabbladen van Kinetic, in volgorde van de navigatiebalk.
enum KineticTab { today, train, food, biometrics, agenda }

/// Huidige tijd (HH:mm) die zichzelf elke minuut bijwerkt — voor als de
/// statusbalk van de telefoon verborgen is. Met [avoidCutout] schuift hij
/// naar beneden als hij precies onder de camera-uitsparing zou vallen.
class KClock extends StatefulWidget {
  const KClock({super.key, this.style, this.avoidCutout = false});

  final TextStyle? style;
  final bool avoidCutout;

  @override
  State<KClock> createState() => _KClockState();
}

class _KClockState extends State<KClock> {
  Timer? _timer;
  final _key = GlobalKey();

  /// Hoeveel de klok omlaag geschoven is om de camera te ontwijken.
  double _shift = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// Precies op de volgende minuutwissel verversen, niet "ergens binnen de
  /// minuut".
  void _schedule() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  /// Na het tekenen: raakt de klok een camera-uitsparing? Dan net onder de
  /// uitsparing zetten. Alleen opnieuw tekenen als dat iets verandert.
  void _checkCutout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final placed = box.localToGlobal(Offset.zero) & box.size;
      final base = placed.translate(0, -_shift);
      var needed = 0.0;
      for (final f in MediaQuery.displayFeaturesOf(context)) {
        if (f.type != DisplayFeatureType.cutout) continue;
        final cutout = f.bounds.inflate(4);
        if (cutout.overlaps(base)) {
          needed = math.max(needed, cutout.bottom - base.top);
        }
      }
      if ((needed - _shift).abs() > 0.5) setState(() => _shift = needed);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.avoidCutout) _checkCutout();
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Transform.translate(
      offset: Offset(0, _shift),
      child: Text(
        '$hh:$mm',
        key: _key,
        style: (widget.style ?? AppText.bodyStrong).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Zet zijn inhoud net onder de camera-uitsparing als die er precies
/// overheen zou vallen (bv. met verborgen systeembalken, als alles tegen de
/// bovenrand staat). Raakt niets de uitsparing, dan verandert er niets — dan
/// blijft de inhoud gewoon tegen de bovenrand.
class CutoutAwarePadding extends StatefulWidget {
  const CutoutAwarePadding({super.key, required this.child});

  final Widget child;

  @override
  State<CutoutAwarePadding> createState() => _CutoutAwarePaddingState();
}

class _CutoutAwarePaddingState extends State<CutoutAwarePadding> {
  final _key = GlobalKey();
  double _pad = 0;

  void _check() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final needed = cutoutOverlap(
        rect.translate(0, -_pad),
        MediaQuery.displayFeaturesOf(context),
      );
      if ((needed - _pad).abs() > 0.5) setState(() => _pad = needed);
    });
  }

  @override
  Widget build(BuildContext context) {
    _check();
    return Padding(
      padding: EdgeInsets.only(top: _pad),
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}

/// Hoeveel [rect] omlaag moet om onder alle camera-uitsparingen te vallen
/// die hem raken (0 = raakt niets). Met 4 px marge.
double cutoutOverlap(Rect rect, List<DisplayFeature> features) {
  var needed = 0.0;
  for (final f in features) {
    if (f.type != DisplayFeatureType.cutout) continue;
    final cutout = f.bounds.inflate(4);
    if (cutout.overlaps(rect)) {
      needed = math.max(needed, cutout.bottom - rect.top);
    }
  }
  return needed;
}
