import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/meal_impact.dart';
import '../models/food_log_entry.dart';

/// Tabel `food_log_entries` (de "meals" uit de spec): bestaand schema, met
/// sinds migratie 202611240001 ook `protein`, `fat` en `context`.
class FoodLogRepository {
  FoodLogRepository(this._client);

  final SupabaseClient _client;

  /// Nieuwste eerst. Met [since] alleen regels vanaf dat moment.
  Future<List<FoodLogEntry>> listForUser(String userId, {DateTime? since}) async {
    var query = _client.from('food_log_entries').select().eq('user_id', userId);
    if (since != null) {
      query = query.gte('at', since.toUtc().toIso8601String());
    }
    final rows = await query.order('at', ascending: false);
    return (rows as List)
        .map((r) => FoodLogEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<FoodLogEntry> create({
    required String userId,
    required DateTime at,
    required String description,
    double? carbs,
    double? protein,
    double? fat,
    MealContext? context,
    double? mmol,
    double? insulinUnits,
    double? insulinFoodUnits,
    double? insulinCorrectionUnits,
    Map<String, int> presetCounts = const {},
  }) async {
    final row = await _client
        .from('food_log_entries')
        .insert({
          'user_id': userId,
          'at': at.toUtc().toIso8601String(),
          'description': description,
          'carbs': carbs,
          'protein': protein,
          'fat': fat,
          'context': context?.dbName,
          'mmol': mmol,
          'insulin_units': insulinUnits,
          'insulin_food_units': insulinFoodUnits,
          'insulin_correction_units': insulinCorrectionUnits,
          'preset_counts': presetCounts,
        })
        .select()
        .single();
    return FoodLogEntry.fromJson(row);
  }

  /// Werkt een bestaande regel bij (alle velden die het maaltijdscherm kent).
  Future<FoodLogEntry> update(FoodLogEntry e) async {
    final row = await _client
        .from('food_log_entries')
        .update({
          'at': e.at.toUtc().toIso8601String(),
          'description': e.description,
          'carbs': e.carbs,
          'protein': e.protein,
          'fat': e.fat,
          'context': e.context?.dbName,
          'mmol': e.mmol,
          'insulin_units': e.insulinUnits,
          'insulin_food_units': e.insulinFoodUnits,
          'insulin_correction_units': e.insulinCorrectionUnits,
          'preset_counts': e.presetCounts,
        })
        .eq('id', e.id)
        .select()
        .single();
    return FoodLogEntry.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('food_log_entries').delete().eq('id', id);
  }
}
