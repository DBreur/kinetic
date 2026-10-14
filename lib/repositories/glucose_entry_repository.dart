import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/glucose_entry.dart';

class GlucoseEntryRepository {
  GlucoseEntryRepository(this._client);

  final SupabaseClient _client;

  Future<List<ManualGlucoseEntry>> recentForUser(
    String userId, {
    int limit = 5,
  }) async {
    final rows = await _client
        .from('glucose_entries')
        .select()
        .eq('user_id', userId)
        .order('at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => ManualGlucoseEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ManualGlucoseEntry> create(
    String userId,
    double mmol,
    DateTime at,
  ) async {
    final row = await _client
        .from('glucose_entries')
        .insert({
          'user_id': userId,
          'mmol': mmol,
          'at': at.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return ManualGlucoseEntry.fromJson(row);
  }

  Future<ManualGlucoseEntry> update(String id, double mmol) async {
    final row = await _client
        .from('glucose_entries')
        .update({'mmol': mmol})
        .eq('id', id)
        .select()
        .single();
    return ManualGlucoseEntry.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('glucose_entries').delete().eq('id', id);
  }
}
