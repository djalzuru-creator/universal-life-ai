import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../household/data/providers.dart';

/// Propuesta de ropa de la IA.
class AiOutfit {
  const AiOutfit(this.garmentIds, this.why, this.tip);
  final List<String> garmentIds;
  final String why;
  final String tip;
}

/// Receta inventada por la IA con lo que hay en la despensa.
class AiRecipe {
  const AiRecipe({
    required this.name,
    required this.minutes,
    required this.ingredients,
    required this.missing,
    required this.steps,
  });
  final String name;
  final int minutes;
  final List<String> ingredients;
  final List<String> missing;
  final List<String> steps;

  factory AiRecipe.fromJson(Map<String, dynamic> j) => AiRecipe(
    name: j['name'] as String? ?? 'Receta',
    minutes: (j['minutes'] as num?)?.toInt() ?? 30,
    ingredients: _strings(j['ingredients']),
    missing: _strings(j['missing']),
    steps: _strings(j['steps']),
  );
}

List<String> _strings(Object? v) =>
    v is List ? [for (final s in v) '$s'] : const [];

/// Error con un mensaje listo para enseñar a la familia.
class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

String aiErrorMessage(String? code) => switch (code) {
  'sin_clave' =>
    'Falta guardar la clave de Gemini en Supabase. Pídeselo al administrador.',
  'limite' => 'Aguilucho ha pensado mucho hoy. Prueba otra vez en un rato.',
  'sin_ropa' => 'Añade primero alguna prenda al armario.',
  'sin_despensa' => 'Añade primero algo a la despensa.',
  _ => 'Aguilucho no ha podido responder. Prueba otra vez.',
};

class AguiluchoAi {
  AguiluchoAi(this._db);
  final SupabaseClient _db;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final r = await _db.functions.invoke('aguilucho', body: body);
      final data = r.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw AiException(aiErrorMessage(data['error'] as String?));
        }
        return data;
      }
      throw const AiException('Respuesta inesperada de Aguilucho.');
    } on FunctionException catch (e) {
      final d = e.details;
      if (e.status == 404) {
        throw const AiException(
          'La IA aún no está instalada en Supabase. Pídeselo al administrador.',
        );
      }
      throw AiException(
        aiErrorMessage(d is Map ? d['error'] as String? : null),
      );
    }
  }

  Future<AiOutfit> outfit({
    required String memberId,
    required String season,
    required String occasion,
    required Map<String, num> weather,
  }) async {
    final d = await _call({
      'mode': 'outfit',
      'member_id': memberId,
      'season': season,
      'occasion': occasion,
      'weather': weather,
    });
    return AiOutfit(
      _strings(d['garment_ids']),
      d['why'] as String? ?? '',
      d['tip'] as String? ?? '',
    );
  }

  Future<List<AiRecipe>> recipes({
    required String householdId,
    String wish = '',
  }) async {
    final d = await _call({
      'mode': 'recipes',
      'household_id': householdId,
      'wish': wish,
    });
    final list = d['recipes'];
    return list is List
        ? [
            for (final r in list)
              AiRecipe.fromJson(Map<String, dynamic>.from(r)),
          ]
        : const [];
  }
}

final aguiluchoAiProvider = Provider(
  (ref) => AguiluchoAi(ref.watch(supabaseProvider)),
);
