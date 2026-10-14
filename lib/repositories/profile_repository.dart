import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<AppProfile> getOrCreate(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row != null) return AppProfile.fromJson(row);

    final profile = AppProfile.defaults(userId);
    try {
      await upsert(profile);
    } on PostgrestException catch (error) {
      // Vlak na inloggen is de auth-context van deze client soms nog niet
      // overal doorgedrongen, waardoor de RLS-policy het aanmaken van het
      // allereerste profiel met code 42501 weigert. Eén korte herkansing
      // lost dat vrijwel altijd op, zonder dat de gebruiker er iets van
      // merkt — een echte weigering (verkeerde gebruiker) blijft wel falen.
      if (error.code == '42501') {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await upsert(profile);
      } else {
        rethrow;
      }
    }
    return profile;
  }

  Future<AppProfile> upsert(AppProfile profile) async {
    final payload = {
      ...profile.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = await _client
        .from('profiles')
        .upsert(payload)
        .select()
        .single();
    return AppProfile.fromJson(row);
  }
}
