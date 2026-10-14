// live_session_store.dart — bewaart een lopende training lokaal op de
// telefoon, zodat hij terugkomt als de app per ongeluk wordt gesloten (of
// door Android wordt opgeruimd). Wordt gewist zodra de training is
// opgeslagen of weggegooid.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LiveSessionStore {
  LiveSessionStore._();

  static const _key = 'kinetic_live_session_v1';

  /// Een training die langer geleden begon wordt niet meer hersteld — dan
  /// is hij vrijwel zeker vergeten in plaats van nog bezig.
  static const maxAge = Duration(hours: 12);

  static Future<void> save(Map<String, dynamic> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(snapshot));
    } catch (_) {
      // Niet kunnen bewaren mag de training zelf nooit hinderen.
    }
  }

  /// De bewaarde training, of null als er geen is (of hij te oud is).
  static Future<Map<String, dynamic>?> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
      if (startedAt == null ||
          (now ?? DateTime.now()).difference(startedAt) > maxAge) {
        await clear();
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
