import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../household/data/providers.dart';
import 'wardrobe_models.dart';
import 'weather.dart';

class WardrobeRepository {
  WardrobeRepository(this._db);

  final SupabaseClient _db;
  static const bucket = 'wardrobe';

  Future<List<Garment>> garments(String memberId) async {
    final rows = await _db
        .from('garments')
        .select()
        .eq('member_id', memberId)
        .order('created_at');
    return rows.map(Garment.fromJson).toList();
  }

  Future<List<Outfit>> outfits(String memberId) async {
    final rows = await _db
        .from('outfits')
        .select()
        .eq('member_id', memberId)
        .order('is_favorite', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Outfit.fromJson).toList();
  }

  /// Sube la foto (ya reducida por el selector) a una carpeta privada del miembro.
  Future<String> uploadPhoto(
    String householdId,
    String memberId,
    Uint8List bytes,
    String mime,
  ) async {
    final ext = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
        ? 'webp'
        : 'jpg';
    final id =
        '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';
    final path = '$householdId/$memberId/$id.$ext';
    await _db.storage
        .from(bucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return path;
  }

  Future<String> signedUrl(String path) =>
      _db.storage.from(bucket).createSignedUrl(path, 3600);

  Future<void> saveGarment(Garment g) => g.id == null
      ? _db.from('garments').insert(g.toJson())
      : _db.from('garments').update(g.toJson()).eq('id', g.id!);

  Future<void> deleteGarment(Garment g) async {
    await _db.from('garments').delete().eq('id', g.id!);
    if (g.photoPath != null) {
      try {
        await _db.storage.from(bucket).remove([g.photoPath!]);
      } catch (_) {
        // La prenda ya está borrada; una foto huérfana no es un problema para la familia.
      }
    }
  }

  Future<void> saveOutfit(Outfit o) => o.id == null
      ? _db.from('outfits').insert(o.toJson())
      : _db.from('outfits').update(o.toJson()).eq('id', o.id!);

  Future<void> deleteOutfit(String id) =>
      _db.from('outfits').delete().eq('id', id);

  Future<void> setCity(String householdId, CityResult c) => _db
      .from('households')
      .update({
        'city_name': c.name,
        'latitude': c.latitude,
        'longitude': c.longitude,
      })
      .eq('id', householdId);
}

final wardrobeRepositoryProvider = Provider(
  (ref) => WardrobeRepository(ref.watch(supabaseProvider)),
);
final weatherServiceProvider = Provider((ref) => WeatherService());

final garmentsProvider = FutureProvider.family<List<Garment>, String>(
  (ref, memberId) => ref.watch(wardrobeRepositoryProvider).garments(memberId),
);

final outfitsProvider = FutureProvider.family<List<Outfit>, String>(
  (ref, memberId) => ref.watch(wardrobeRepositoryProvider).outfits(memberId),
);

final photoUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(wardrobeRepositoryProvider).signedUrl(path),
);

typedef LatLon = ({double lat, double lon});

final todayWeatherProvider = FutureProvider.family<TodayWeather, LatLon>(
  (ref, p) => ref.watch(weatherServiceProvider).today(p.lat, p.lon),
);
