// dexcom_credentials.dart — bewaart alleen het Dexcom-wachtwoord, los van
// Supabase/AppProfile (daar staan alleen gebruikersnaam en server). Zo komt
// het wachtwoord nooit in de database of in een backup daarvan terecht.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DexcomCredentials {
  static const _key = 'dexcom_password';
  static const _storage = FlutterSecureStorage();

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> write(String password) =>
      _storage.write(key: _key, value: password);

  static Future<void> delete() => _storage.delete(key: _key);
}
