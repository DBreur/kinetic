// live_session_controller.dart — gedeelde vorm van een sessie die op de
// achtergrond kan doorlopen (sambo of kracht), zodat ShellScreen één
// permanente balk kan tonen ongeacht welk type sessie er loopt.

import 'package:flutter/material.dart';

abstract class LiveSessionController implements Listenable {
  String get title;
  Duration get elapsed;
  bool get isPaused;
  double get glucoseMmol;
}
