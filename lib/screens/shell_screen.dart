// shell_screen.dart: de app-shell uit kinetic-design: top app bar (logo,
// "Kinetic" + schermnaam, thema-schakelaar, avatar) en de 5-tabs navigatie
// (Vandaag, Training, '+', Technieken, Eten) met de centrale quick action.
// Loopt er een sessie, dan staat er een "terug naar de mat"-balk boven.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/sparring_timer.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';
import 'eten_screen.dart';
import 'technieken_screen.dart';
import 'training_screen.dart';
import 'vandaag_screen.dart';

class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key});

  static int _stackIndex(int tab) => switch (tab) {
    KTab.training => 1,
    KTab.technieken => 2,
    KTab.eten => 3,
    _ => 0,
  };

  static String tabLabel(int tab) => switch (tab) {
    KTab.training => 'Training',
    KTab.technieken => 'Technieken',
    KTab.eten => 'Eet Logboek',
    _ => 'Vandaag',
  };

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          KineticTopBar(subtitle: tabLabel(store.tab)),
          Expanded(
            child: IndexedStack(
              index: _stackIndex(store.tab),
              children: const [VandaagScreen(), TrainingScreen(), TechniekenScreen(), EtenScreen()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (store.isSparringActive) const _LiveSessionBar(),
          const KineticNavBar(),
        ],
      ),
    );
  }
}

class KineticNavBar extends StatelessWidget {
  const KineticNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    Widget item(int index, IconData icon, IconData activeIcon, String label) {
      final active = store.tab == index;
      final color = active ? k.accent : k.textSecondary;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          label: label,
          child: InkResponse(
            onTap: () {
              HapticFeedback.selectionClick();
              store.selectTab(index);
            },
            radius: 36,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(active ? activeIcon : icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: context.t.labelSm.copyWith(
                    color: color,
                    letterSpacing: 0.2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(top: BorderSide(color: k.border)),
      ),
      // Ruimte voor de Android-navigatieknoppen / gesturebalk.
      padding: EdgeInsets.only(bottom: context.bottomInset),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            item(KTab.vandaag, Icons.calendar_today_outlined, Icons.calendar_today, 'Vandaag'),
            item(KTab.training, Icons.sports_martial_arts_outlined, Icons.sports_martial_arts, 'Training'),
            Expanded(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -16),
                  child: Semantics(
                    button: true,
                    label: 'Snelle actie',
                    child: Material(
                      color: k.primary,
                      shape: CircleBorder(side: BorderSide(color: k.canvas, width: 4)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          showQuickActions(context);
                        },
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Icon(Icons.add_rounded, color: k.onPrimary, size: 34),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            item(KTab.technieken, Icons.menu_book_outlined, Icons.menu_book, 'Technieken'),
            item(KTab.eten, Icons.restaurant_outlined, Icons.restaurant, 'Eten'),
          ],
        ),
      ),
    );
  }
}

class _LiveSessionBar extends StatelessWidget {
  const _LiveSessionBar();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final t = store.sparring!;
    final rest = t.phase == SparringPhase.rest;
    final color = rest ? k.primary : k.danger;
    return Material(
      color: color.withValues(alpha: k.isDark ? 0.16 : 0.10),
      child: InkWell(
        onTap: () => openLiveSession(context),
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: color.withValues(alpha: 0.5)))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              LiveDot(color: color, active: !t.isPaused),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${rest ? 'RUST' : store.sessionTitle.toUpperCase()} • Ronde ${t.round}/${t.config.rounds}${t.isPaused ? ' • gepauzeerd' : ''}',
                  style: context.t.labelSm.copyWith(color: k.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(mmss(store.roundSecondsRemaining), style: context.t.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              Icon(Icons.open_in_full, size: 18, color: k.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
