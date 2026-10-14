import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/circuit.dart';

class CircuitRepository {
  CircuitRepository(this._client);

  final SupabaseClient _client;

  Future<List<Circuit>> listForUser(String userId) async {
    final rows = await _client
        .from('circuits')
        .select()
        .eq('user_id', userId)
        .order('name');
    return (rows as List)
        .map((r) => Circuit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Circuit> create(Circuit circuit, String userId) async {
    final row = await _client
        .from('circuits')
        .insert(circuit.toInsertJson(userId))
        .select()
        .single();
    return Circuit.fromJson(row);
  }

  Future<Circuit> updateContent(Circuit circuit) async {
    final row = await _client
        .from('circuits')
        .update({
          'name': circuit.name,
          'exercise_names': circuit.exerciseNames,
          'rounds': circuit.rounds,
          'work_seconds': circuit.workSeconds,
          'rest_seconds': circuit.restSeconds,
        })
        .eq('id', circuit.id)
        .select()
        .single();
    return Circuit.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('circuits').delete().eq('id', id);
  }
}
