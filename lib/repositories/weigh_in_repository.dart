import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/weigh_in.dart';

class WeighInRepository {
  WeighInRepository(this._client);

  final SupabaseClient _client;

  /// Nieuwste eerst.
  Future<List<WeighIn>> listForUser(String userId, {int limit = 120}) async {
    final rows = await _client
        .from('weigh_ins')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => WeighIn.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<WeighIn> create(WeighIn weighIn, String userId) async {
    final row = await _client
        .from('weigh_ins')
        .insert(weighIn.toInsertJson(userId))
        .select()
        .single();
    return WeighIn.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('weigh_ins').delete().eq('id', id);
  }
}
