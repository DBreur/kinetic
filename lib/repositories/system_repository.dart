import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/technique_system.dart';

class SystemRepository {
  SystemRepository(this._client);

  final SupabaseClient _client;

  Future<List<TechniqueSystem>> listForUser(String userId) async {
    final rows = await _client
        .from('systems')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => TechniqueSystem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<TechniqueSystem> create(TechniqueSystem system, String userId) async {
    final row = await _client
        .from('systems')
        .insert({...system.toContentJson(), 'user_id': userId})
        .select()
        .single();
    return TechniqueSystem.fromJson(row);
  }

  Future<TechniqueSystem> update(TechniqueSystem system) async {
    final row = await _client
        .from('systems')
        .update(system.toContentJson())
        .eq('id', system.id)
        .select()
        .single();
    return TechniqueSystem.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('systems').delete().eq('id', id);
  }
}
