// notification_style.dart — gedeelde huisstijl voor Android-meldingen: het
// kleine (witte) Kinetic-logo in de statusbalk krijgt in het meldingenpaneel
// de koraalkleur van de app.

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const kNotificationColor = Color(0xFFFF516A);

/// Ruimt kanalen op die door een nieuwe kanaal-ID zijn vervangen. Android
/// onthoudt een kanaal (geluid, trilling) voorgoed na het aanmaken; een
/// kanaal dat ooit zonder werkend geluid is aangemaakt, wordt nooit meer
/// beter. Dus: nieuwe ID, en de oude weg zodat hij niet blijft rondslingeren
/// in de systeeminstellingen.
Future<void> deleteStaleChannels(
  AndroidFlutterLocalNotificationsPlugin? android,
  List<String> ids,
) async {
  if (android == null) return;
  for (final id in ids) {
    try {
      await android.deleteNotificationChannel(channelId: id);
    } catch (e) {
      debugPrint('Kanaal $id verwijderen mislukt: $e');
    }
  }
}
