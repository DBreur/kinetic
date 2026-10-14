// system_bars.dart — de systeembalken van de telefoon (navigatieknoppen en
// statusbalk) automatisch verbergen, "immersive sticky": veeg vanaf de rand
// om ze even terug te halen, daarna verdwijnen ze vanzelf weer.
//
// Twee bronnen bepalen samen of ze verborgen zijn:
//   • de instelling "Systeemknoppen verbergen" (hele app);
//   • een live mat-/krachtsessie die in beeld is (altijd verbergen).
// Eén centrale plek, zodat een sessie die sluit niet per ongeluk de
// instelling overschrijft (of andersom).

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class SystemBars {
  SystemBars._();

  static bool _alwaysHidden = false;
  static int _openSessions = 0;

  static bool get hidden => _alwaysHidden || _openSessions > 0;

  /// Luisterbaar: de app haalt bovenaan de veilige zone weg zolang de
  /// balken verborgen zijn, zodat alles tegen de bovenrand aansluit.
  static final ValueNotifier<bool> hiddenListenable = ValueNotifier(false);

  /// De instelling uit het profiel.
  static Future<void> setAlwaysHidden(bool value) {
    if (_alwaysHidden == value) return Future.value();
    _alwaysHidden = value;
    return _apply();
  }

  /// Een live sessie komt in beeld.
  static Future<void> enterSession() {
    _openSessions++;
    return _apply();
  }

  /// Een live sessie gaat uit beeld (afgerond of geminimaliseerd).
  static Future<void> exitSession() {
    if (_openSessions > 0) _openSessions--;
    return _apply();
  }

  /// Opnieuw toepassen, bv. als de app weer op de voorgrond komt (Android
  /// kan de balken intussen hebben teruggezet).
  static Future<void> reapply() => _apply();

  /// Meldt de nieuwe stand. Vanuit initState/dispose van een scherm zitten
  /// we midden in een frame — dan pas na het frame melden, anders bouwt de
  /// app opnieuw terwijl hij al aan het bouwen is.
  static void _publish() {
    final binding = SchedulerBinding.instance;
    final phase = binding.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      binding.addPostFrameCallback((_) => hiddenListenable.value = hidden);
    } else {
      hiddenListenable.value = hidden;
    }
  }

  static bool _callbackRegistered = false;
  static Timer? _rehide;

  /// Hoe lang de knoppen zichtbaar blijven na een veeg.
  static const rehideAfter = Duration(seconds: 3);

  static Future<void> _apply() async {
    _publish();
    _rehide?.cancel();
    try {
      _registerCallback();
      // "immersive" (niet "sticky"): de veeg vanaf de rand gaat naar het
      // systeem, niet naar de app — dus je scrollt niet mee als je de
      // knoppen terughaalt. Ze blijven dan staan tot de app ze opnieuw
      // verbergt; dat doet [_registerCallback] na [rehideAfter].
      await SystemChrome.setEnabledSystemUIMode(
        hidden ? SystemUiMode.immersive : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // Geen platformkanaal (tests, desktop) — niets te doen.
    }
  }

  static void _registerCallback() {
    if (_callbackRegistered) return;
    _callbackRegistered = true;
    SystemChrome.setSystemUIChangeCallback((overlaysVisible) async {
      if (!overlaysVisible || !hidden) return;
      _rehide?.cancel();
      _rehide = Timer(rehideAfter, () {
        if (hidden) _apply();
      });
    });
  }
}

/// `MaterialApp.builder` van Kinetic: tijden in 24-uursnotatie, en zolang
/// de systeembalken verborgen zijn geen veilige zone bovenaan — zodat alles
/// (topbalk, glucosebalk, pagina's) tegen de bovenrand aansluit.
Widget kineticAppBuilder(BuildContext context, Widget? child) =>
    ValueListenableBuilder<bool>(
      valueListenable: SystemBars.hiddenListenable,
      builder: (context, barsHidden, _) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            alwaysUse24HourFormat: true,
            // Ook onderaan geen ruimte: verschijnen de knoppen even na een
            // veeg, dan schuiven ze over de app heen in plaats van dat de
            // hele lay-out drie seconden omhoog springt.
            padding: barsHidden
                ? mq.padding.copyWith(top: 0, bottom: 0)
                : mq.padding,
            viewPadding: barsHidden
                ? mq.viewPadding.copyWith(top: 0, bottom: 0)
                : mq.viewPadding,
          ),
          child: child!,
        );
      },
    );
