// shell_screen.dart: 5-tabs bottom navigation (Vandaag, Training, '+',
// Technieken, Eten) met de zwevende centrale quick-action-knop. Loopt er
// een sparringsessie, dan staat er een "terug naar de mat"-balk boven.

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

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _stackIndex(store.tab),
        children: const [VandaagScreen(), TrainingScreen(), TechniekenScreen(), EtenScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (store.isSparringActive) const _LiveSessionBar(),
          const _KineticNavBar(),
        ],
      ),
    );
  }
}

class _KineticNavBar extends StatelessWidget {
  const _KineticNavBar();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    Widget item(int index, IconData icon, IconData activeIcon, String label) {
      final active = store.tab == index;
      final color = active ? KColor.teal : KColor.textMuted;
      return Expanded(
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
                style: KText.caption.copyWith(
                  fontSize: 11,
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: KColor.surface,
        border: Border(top: BorderSide(color: KColor.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              item(KTab.vandaag, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Vandaag'),
              item(KTab.training, Icons.insights_outlined, Icons.insights, 'Training'),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -14),
                    child: Semantics(
                      button: true,
                      label: 'Snelle actie',
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          showQuickActions(context);
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [KColor.tealLight, KColor.teal],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: KColor.bg, width: 4),
                            boxShadow: const [BoxShadow(color: KColor.tealGlow, blurRadius: 18, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.add_rounded, color: KColor.bg, size: 32),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              item(KTab.technieken, Icons.sports_martial_arts_outlined, Icons.sports_martial_arts, 'Technieken'),
              item(KTab.eten, Icons.restaurant_outlined, Icons.restaurant, 'Eten'),
            ],
          ),
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
    final t = store.sparring!;
    final rest = t.phase == SparringPhase.rest;
    return Material(
      color: rest ? KColor.teal.withValues(alpha: 0.18) : KColor.danger.withValues(alpha: 0.18),
      child: InkWell(
        onTap: () => openLiveSession(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              LiveDot(color: rest ? KColor.teal : KColor.danger, active: !t.isPaused),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${rest ? 'RUST' : 'SPARRING'} • Ronde ${t.round}/${t.config.rounds}${t.isPaused ? ' • gepauzeerd' : ''}',
                  style: KText.caption.copyWith(color: KColor.text, fontWeight: FontWeight.w700),
                ),
              ),
              Text(mmss(store.roundSecondsRemaining), style: KText.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_full, size: 18, color: KColor.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
