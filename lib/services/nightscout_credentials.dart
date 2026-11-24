// nightscout_credentials.dart — bewaart het Nightscout API-token alleen op
// het toestel (versleutelde opslag), net als het Dexcom-wachtwoord in
// dexcom_credentials.dart. De kolom profiles.nightscout_token blijft leeg.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NightscoutCredentials {
  static const _key = 'nightscout_token';
  static const _storage = FlutterSecureStorage();

  /// null als er niets bewaard is of de opslag niet beschikbaar is (tests).
  static Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  /// Leeg token = verwijderen. Geeft false als opslaan niet lukte.
  static Future<bool> write(String token) async {
    try {
      if (token.trim().isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: token.trim());
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
