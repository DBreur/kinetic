// kinetic_widgets.dart: bouwstenen van het Kinetic design system
// (kinetic-design/). Alle kleuren komen uit context.k, zodat licht en donker
// live wisselen. Geen gradients, glows of schaduwen: kaarten zijn vlakken
// met een 1px haarlijn; secundaire info staat in ingezonken "wells".

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/glucose_rules.dart';
import '../models/glucose.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';

/// Maakt de store beschikbaar voor alle schermen; `KineticScope.of` laat een
/// widget opnieuw bouwen zodra de store verandert.
class KineticScope extends InheritedNotifier<KineticStore> {
  const KineticScope({super.key, required KineticStore store, required super.child})
    : super(notifier: store);

  static KineticStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KineticScope>()!.notifier!;

  /// Zonder te abonneren (voor callbacks).
  static KineticStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<KineticScope>()!.notifier!;
}

// ----------------------------------------------------------------- vlakken

/// Level 1-kaart: surface + 1px haarlijn, radius 16.
class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.onTap,
    this.radius = KRadius.lg,
    @Deprecated('Geen gradients in het Kinetic design system') this.gradient,
    @Deprecated('Geen glows in het Kinetic design system') this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;
  final Gradient? gradient;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = BorderRadius.circular(radius);
    return Material(
      color: color ?? k.surface,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: borderColor ?? k.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Level 2: ingezonken vlak binnen een kaart.
class KWell extends StatelessWidget {
  const KWell({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.color, this.onTap, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = BorderRadius.circular(KRadius.md);
    return Material(
      color: color ?? k.well,
      shape: RoundedRectangleBorder(borderRadius: r, side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Vierkant icoonvlak (bv. het trainingsicoon op Vandaag).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 48, this.color, this.filled = false});
  final IconData icon;
  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = color ?? k.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: k.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(size >= 44 ? KRadius.md : KRadius.sm),
      ),
      child: Icon(icon, size: size * 0.52, color: filled ? k.onPrimary : c),
    );
  }
}

// --------------------------------------------------------------- tekst

/// Uppercase label boven een sectie ("TODAY'S PROTOCOL").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.k.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: c), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: context.t.label.copyWith(color: c),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: context.k.accent), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: context.t.title)),
          ?trailing,
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- status

enum KTone { neutral, primary, success, warning, danger, info, purple }

(Color bg, Color fg) toneColors(KineticColors k, KTone tone) => switch (tone) {
  KTone.neutral => (k.well, k.textSecondary),
  KTone.primary => (k.primaryTint, k.accent),
  KTone.success => (k.successTint, k.successInk),
  KTone.warning => (k.warningTint, k.warningInk),
  KTone.danger => (k.dangerTint, k.dangerInk),
  KTone.info => (k.blue.withValues(alpha: 0.14), k.blue),
  KTone.purple => (k.purple.withValues(alpha: 0.14), k.purple),
};

/// Pill-vormige statusbadge, met stip of icoon (nooit alleen kleur).
class KPill extends StatelessWidget {
  const KPill(this.text, {super.key, this.tone = KTone.neutral, this.icon, this.dot = false, this.uppercase = false, this.dense = false});
  final String text;
  final KTone tone;
  final IconData? icon;
  final bool dot;
  final bool uppercase;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context.k, tone);
    final style = (uppercase ? context.t.labelSm : context.t.caption).copyWith(color: fg, fontWeight: FontWeight.w600);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(uppercase ? text.toUpperCase() : text, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ],
      ),
    );
  }
}

/// Oudere badge-API (kleur i.p.v. tone); nog gebruikt door enkele schermen.
class KBadge extends StatelessWidget {
  const KBadge(this.text, {super.key, this.color, this.dot = true, this.filled = false});
  final String text;
  final Color? color;
  final bool dot;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = color ?? k.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: k.isDark ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(KRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: filled ? Colors.white : c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: context.t.caption.copyWith(color: filled ? Colors.white : c, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Voortgangsbalk (macro's, mastery, ronde).
class KProgressBar extends StatelessWidget {
  const KProgressBar({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(KRadius.full),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: k.well)),
            FractionallySizedBox(
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color ?? k.primary, borderRadius: BorderRadius.circular(KRadius.full)),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- knoppen

enum KButtonStyle { primary, secondary, critical, ghost }

/// Knop volgens het design system: primary 52px, critical minimaal 56px.
/// Met [height] 64+ wordt hij handschoenvriendelijk voor de mat.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = KButtonStyle.primary,
    this.height = 52,
    this.onLongPress,
    this.color,
    this.foreground,
    this.outlined = false,
    this.vertical = false,
    this.fitLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData? icon;
  final KButtonStyle style;
  final double height;

  /// Eigen kleur (overschrijft [style]).
  final Color? color;
  final Color? foreground;
  final bool outlined;

  /// Icoon boven het label (zoals de bedieningsknoppen op de mat).
  final bool vertical;

  /// Label altijd op één regel; krimpt mee in smalle knoppen.
  final bool fitLabel;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    var (bg, fg, side) = switch (style) {
      KButtonStyle.primary => (k.primary, k.onPrimary, BorderSide.none),
      KButtonStyle.secondary => (k.well, k.text, BorderSide(color: k.border)),
      KButtonStyle.critical => (k.danger, Colors.white, BorderSide.none),
      KButtonStyle.ghost => (const Color(0x00000000), k.accent, BorderSide(color: k.border)),
    };
    if (color != null) {
      bg = outlined ? color!.withValues(alpha: k.isDark ? 0.12 : 0.08) : color!;
      fg = foreground ?? (outlined ? color! : Colors.white);
      side = outlined ? BorderSide(color: color!.withValues(alpha: 0.6)) : BorderSide.none;
    } else if (foreground != null) {
      fg = foreground!;
    }
    if (onPressed == null) {
      bg = k.well;
      fg = k.textMuted;
      side = BorderSide.none;
    }
    final r = BorderRadius.circular(KRadius.md);
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.t.subtitle.copyWith(color: fg, fontWeight: FontWeight.w700, letterSpacing: vertical ? 0.6 : 0),
    );
    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: r, side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onPressed!();
                },
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: vertical
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[Icon(icon, color: fg, size: 26), const SizedBox(height: 6)],
                      // Eén regel, krimpt mee in smalle knoppen (icoon + 2 regels past niet in 72px).
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: text.style,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 10)],
                      Flexible(
                        child: fitLabel
                            ? FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: text.style))
                            : text,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Filter-/keuzechip, pill-vormig, minimaal 40px hoog.
class KChip extends StatelessWidget {
  const KChip({super.key, required this.label, required this.selected, required this.onTap, this.color, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final active = color ?? k.primary;
    // Eigen kleur: tekst contrasteert met de achtergrond (bv. k.text is wit in dark mode).
    final onColor = ThemeData.estimateBrightnessForColor(active) == Brightness.dark ? Colors.white : const Color(0xFF101419);
    final fg = selected ? (color == null ? k.onPrimary : onColor) : k.textSecondary;
    return Material(
      color: selected ? active : k.well,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.full),
        side: BorderSide(color: selected ? active : k.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            // Eén Text (icoon als WidgetSpan): breekt netjes af in een smalle
            // Wrap en houdt z'n natuurlijke breedte in een horizontale lijst.
            child: Text.rich(
              TextSpan(
                children: [
                  if (icon != null) ...[
                    WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(icon, size: 16, color: fg)),
                    const WidgetSpan(child: SizedBox(width: 6)),
                  ],
                  TextSpan(text: label),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.t.caption.copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented control: één well-track, actieve duim = surface + haarlijn.
class KSegmented<T> extends StatelessWidget {
  const KSegmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.md)),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? k.surface : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(KRadius.sm),
                    border: Border.all(color: v == value ? k.border : const Color(0x00000000)),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyStrong.copyWith(
                      fontSize: 13,
                      color: v == value ? k.text : k.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- metrics

/// Statistiek in een well: label, grote waarde, subregel.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.accent,
    this.subColor,
    this.valueColor,
    this.inWell = false,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? accent;
  final Color? subColor;
  final Color? valueColor;

  /// Als well binnen een kaart in plaats van als losse kaart.
  final bool inWell;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: accent ?? k.accent), const SizedBox(width: 6)],
            Expanded(child: Text(label, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: context.t.metricSm.copyWith(color: valueColor ?? k.text)),
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub!, style: context.t.caption.copyWith(color: subColor ?? k.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
    return inWell ? KWell(padding: const EdgeInsets.all(12), child: content) : KCard(padding: const EdgeInsets.all(16), child: content);
  }
}

/// Grote glucosewaarde met trendpijl; kleur volgt de zone.
class GlucoseReadout extends StatelessWidget {
  const GlucoseReadout({super.key, required this.reading, this.size = 44, this.showUnit = true, this.showArrow = true});
  final GlucoseReading? reading;
  final double size;
  final bool showUnit;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = reading;
    final style = context.t.metric.copyWith(fontSize: size);
    if (r == null) return Text('--', style: style.copyWith(color: k.textMuted));
    final zone = zoneFor(r.mmol);
    final color = r.isStale ? k.textMuted : (zone == GlucoseZone.inTarget ? k.text : glucoseColor(r.mmol));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(r.mmol.toStringAsFixed(1), style: style.copyWith(color: color)),
        if (showUnit) ...[const SizedBox(width: 6), Text('mmol/L', style: context.t.unit)],
        if (showArrow) ...[
          const SizedBox(width: 8),
          Text(trendArrow(r.trend), style: style.copyWith(fontSize: size * 0.6, color: glucoseColor(r.mmol))),
        ],
      ],
    );
  }
}

/// Knipperende stip voor "LIVE".
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color, this.active = true, this.size = 8});
  final Color? color;
  final bool active;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color ?? context.k.danger, shape: BoxShape.circle),
    );
    if (!widget.active) return dot;
    return FadeTransition(opacity: Tween(begin: 0.35, end: 1.0).animate(_c), child: dot);
  }
}

// --------------------------------------------------------------- branding

/// Het Kinetic-logo (assets/brand).
class KineticLogo extends StatelessWidget {
  const KineticLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        size > 48 ? 'assets/brand/kinetic_logo_192.png' : 'assets/brand/kinetic_logo_96.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Ronde avatar met initialen.
class KAvatar extends StatelessWidget {
  const KAvatar({super.key, required this.initials, this.size = 36, this.onTap});
  final String initials;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: onTap != null,
      label: 'Profiel en instellingen',
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.75,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: k.primaryTint, shape: BoxShape.circle, border: Border.all(color: k.border)),
          child: Text(initials, style: context.t.bodyStrong.copyWith(color: k.accent, fontSize: size * 0.38)),
        ),
      ),
    );
  }
}

/// Top app bar uit de mockups: logo + "Kinetic" + schermnaam, rechts de
/// thema-schakelaar (zon/maan) en de avatar (naar Instellingen).
class KineticTopBar extends StatelessWidget {
  const KineticTopBar({super.key, required this.subtitle, this.showBack = false, this.title = 'Kinetic', this.actions = const []});
  final String title;
  final String subtitle;
  final bool showBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final store = KineticScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: k.canvas,
        border: Border(bottom: BorderSide(color: k.border)),
      ),
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: EdgeInsets.only(left: showBack ? 4 : 16, right: 8),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  tooltip: 'Terug',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: k.text),
                ),
              const KineticLogo(size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.t.subtitle.copyWith(height: 1.15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              ...actions,
              // Thema wisselen kan alleen nog via de schakelaar in Instellingen.
              const SizedBox(width: 6),
              KAvatar(
                initials: store.initials,
                onTap: () => Navigator.of(context).pushNamed('/telemetrie-export'),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scaffold voor gepushte schermen met de Kinetic top bar.
class KineticPage extends StatelessWidget {
  const KineticPage({super.key, required this.subtitle, required this.body, this.title = 'Kinetic', this.bottomBar, this.actions = const []});
  final String title;
  final String subtitle;
  final Widget body;
  final Widget? bottomBar;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          KineticTopBar(title: title, subtitle: subtitle, showBack: true, actions: actions),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// Vaste balk onderin (bv. pauze/volgende) met ruimte voor de systeemknoppen.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      decoration: BoxDecoration(color: k.surface, border: Border(top: BorderSide(color: k.border))),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + context.bottomInset),
      child: child,
    );
  }
}

// --------------------------------------------------------------- sheets

/// Bottom sheet met de juiste ruimte onderin: toetsenbord én de Android-
/// navigatieknoppen/gesturebalk, zodat niets overlapt.
Future<T?> showKineticSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  final store = KineticScope.read(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => KineticScope(
      store: store,
      child: Builder(
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.viewPaddingOf(ctx).bottom;
          final content = Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
            child: builder(ctx),
          );
          return scrollable ? SingleChildScrollView(child: content) : content;
        },
      ),
    ),
  );
}

// --------------------------------------------------------------- feedback

void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, bool error = false}) =>
    showToastOn(ScaffoldMessenger.of(context), message, actionLabel: actionLabel, onAction: onAction, error: error);

/// Voor als de widget die de toast vraagt zelf al weg is (na navigeren).
void showToastOn(ScaffoldMessengerState messenger, String message, {String? actionLabel, VoidCallback? onAction, bool error = false}) {
  final k = messenger.context.k;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle, color: error ? k.danger : k.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      // Met "Ongedaan" iets langer zichtbaar, maar altijd vanzelf weg
      // (een SnackBar met actie blijft anders staan tot je hem wegtikt).
      duration: Duration(seconds: actionLabel == null ? 3 : 4),
      persist: false,
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Rode alertbalk bij een actuele hypo, met snelle koolhydraten-knop.
class HypoBanner extends StatelessWidget {
  const HypoBanner({super.key, required this.reading, required this.onDextrose, this.grams = 15});
  final GlucoseReading reading;
  final VoidCallback onDextrose;
  final int grams;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: k.dangerTint,
        borderRadius: BorderRadius.circular(KRadius.lg),
        border: Border.all(color: k.danger),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: k.danger, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HYPO ${reading.mmol.toStringAsFixed(1)} mmol/L ${trendArrow(reading.trend)}',
                  style: context.t.subtitle.copyWith(color: k.dangerInk, fontWeight: FontWeight.w800),
                ),
                Text('Stop, neem ${grams}g snelle koolhydraten, meet na 15 min.', style: context.t.caption.copyWith(color: k.text)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: k.danger, foregroundColor: Colors.white),
              onPressed: onDextrose,
              child: Text('+${grams}g', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
