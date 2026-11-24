// kinetic_widgets.dart: gedeelde bouwstenen in het Kinetic Dark Theme.

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

class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = KColor.surfaceContainer,
    this.borderColor = KColor.border,
    this.onTap,
    this.gradient,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(KRadius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: glow
            ? const [BoxShadow(color: KColor.tealGlow, blurRadius: 24, spreadRadius: -4)]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = KColor.textMuted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: KText.eyebrow.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Afgeronde badge met optionele stip ("● Stabiel doelbereik").
class KBadge extends StatelessWidget {
  const KBadge(this.text, {super.key, this.color = KColor.teal, this.dot = true, this.filled = false});
  final String text;
  final Color color;
  final bool dot;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(KRadius.full),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: filled ? KColor.bg : color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: KText.caption.copyWith(
                color: filled ? KColor.bg : color,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontale voortgangsbalk (macrobarometer, mastery).
class KProgressBar extends StatelessWidget {
  const KProgressBar({super.key, required this.value, this.color = KColor.teal, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(KRadius.full),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: KColor.surfaceHigh)),
            FractionallySizedBox(
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(KRadius.full),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grote, handschoenvriendelijke knop: minimaal 64px hoog.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = KColor.teal,
    this.foreground = KColor.bg,
    this.outlined = false,
    this.height = 64,
    this.onLongPress,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData? icon;
  final Color color;
  final Color foreground;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? color : foreground;
    final radius = BorderRadius.circular(KRadius.lg);
    return SizedBox(
      height: height,
      child: Material(
        color: outlined ? color.withValues(alpha: 0.10) : color,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: outlined ? BorderSide(color: color.withValues(alpha: 0.6), width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onPressed!();
                },
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, color: fg, size: 24), const SizedBox(width: 10)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: KText.subtitle.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kleine selecteerbare chip (filters, context, periodes).
class KChip extends StatelessWidget {
  const KChip({super.key, required this.label, required this.selected, required this.onTap, this.color = KColor.teal});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : KColor.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.full),
        side: BorderSide(color: selected ? color : KColor.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(KRadius.full),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: KText.caption.copyWith(
              color: selected ? color : KColor.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: KText.title)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kleine statistiektegel: label, grote waarde, subregel.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.accent = KColor.teal,
    this.subColor,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color accent;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: accent), const SizedBox(width: 6)],
              Expanded(child: Eyebrow(label)),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: KText.metricSmall),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: KText.caption.copyWith(color: subColor ?? KColor.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Grote glucosewaarde met trendpijl, gekleurd naar zone.
class GlucoseReadout extends StatelessWidget {
  const GlucoseReadout({super.key, required this.reading, this.size = 34, this.showUnit = true});
  final GlucoseReading? reading;
  final double size;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    if (r == null) {
      return Text('--', style: KText.metric.copyWith(fontSize: size, color: KColor.textMuted));
    }
    final color = r.isStale ? KColor.textMuted : glucoseColor(r.mmol);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(r.mmol.toStringAsFixed(1), style: KText.metric.copyWith(fontSize: size, color: color)),
        const SizedBox(width: 6),
        Text(trendArrow(r.trend), style: KText.metric.copyWith(fontSize: size * 0.8, color: color)),
        if (showUnit) ...[
          const SizedBox(width: 6),
          Text('mmol/L', style: KText.caption),
        ],
      ],
    );
  }
}

/// Knipperende rode stip voor "LIVE".
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = KColor.danger, this.active = true});
  final Color color;
  final bool active;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.active) return dot;
    return FadeTransition(opacity: Tween(begin: 0.35, end: 1.0).animate(_c), child: dot);
  }
}

void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, bool error = false}) =>
    showToastOn(ScaffoldMessenger.of(context), message, actionLabel: actionLabel, onAction: onAction, error: error);

/// Voor als de widget die de toast vraagt zelf al weg is (na navigeren).
void showToastOn(ScaffoldMessengerState messenger, String message, {String? actionLabel, VoidCallback? onAction, bool error = false}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle,
            color: error ? KColor.danger : KColor.teal,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: KText.body)),
        ],
      ),
      duration: const Duration(seconds: 3),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Rode balk bovenin bij een actuele hypo, met snelle +15g-knop.
class HypoBanner extends StatelessWidget {
  const HypoBanner({super.key, required this.reading, required this.onDextrose});
  final GlucoseReading reading;
  final VoidCallback onDextrose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: KColor.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(KRadius.lg),
        border: Border.all(color: KColor.danger),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: KColor.danger, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HYPO ${reading.mmol.toStringAsFixed(1)} mmol/L ${trendArrow(reading.trend)}',
                  style: KText.subtitle.copyWith(color: KColor.danger, fontWeight: FontWeight.w900),
                ),
                Text('Stop, neem 15g snelle koolhydraten, meet na 15 min.', style: KText.caption.copyWith(color: KColor.text)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: KColor.danger, foregroundColor: KColor.text),
              onPressed: onDextrose,
              child: const Text('+15g', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}
