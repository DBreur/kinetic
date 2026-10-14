import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_log_entry.dart';

class FoodLogRepository {
  FoodLogRepository(this._client);

  final SupabaseClient _client;

  Future<List<FoodLogEntry>> listForUser(String userId) async {
    final rows = await _client
        .from('food_log_entries')
        .select()
        .eq('user_id', userId)
        .order('at', ascending: false);
    return (rows as List)
        .map((r) => FoodLogEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<FoodLogEntry> create(
    String userId,
    DateTime at,
    String description,
    Map<String, int> presetCounts,
    double? carbs,
    double? mmol, {
    double? insulinUnits,
    InsulinTiming? insulinTiming,
    double? insulinFoodUnits,
    double? insulinCorrectionUnits,
    String insulinNote = '',
    double? insulinWaitMinutes,
  }) async {
    final row = await _client
        .from('food_log_entries')
        .insert({
          'user_id': userId,
          'at': at.toUtc().toIso8601String(),
          'description': description,
          'preset_counts': presetCounts,
          'carbs': carbs,
          'mmol': mmol,
          'insulin_units': insulinUnits,
          'insulin_timing': insulinTiming?.name,
          'insulin_food_units': insulinFoodUnits,
          'insulin_correction_units': insulinCorrectionUnits,
          'insulin_note': insulinNote,
          'insulin_wait_minutes': insulinWaitMinutes,
        })
        .select()
        .single();
    return FoodLogEntry.fromJson(row);
  }

  Future<FoodLogEntry> update(FoodLogEntry entry) async {
    final row = await _client
        .from('food_log_entries')
        .update({
          'at': entry.at.toUtc().toIso8601String(),
          'description': entry.description,
          'preset_counts': entry.presetCounts,
          'carbs': entry.carbs,
          'mmol': entry.mmol,
          'insulin_units': entry.insulinUnits,
          'insulin_timing': entry.insulinTiming?.name,
          'insulin_food_units': entry.insulinFoodUnits,
          'insulin_correction_units': entry.insulinCorrectionUnits,
          'insulin_note': entry.insulinNote,
          'insulin_wait_minutes': entry.insulinWaitMinutes,
        })
        .eq('id', entry.id)
        .select()
        .single();
    return FoodLogEntry.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('food_log_entries').delete().eq('id', id);
  }
}
