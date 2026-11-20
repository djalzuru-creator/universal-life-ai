import 'dart:math';

import 'wardrobe_models.dart';
import 'weather.dart';

class OutfitSuggestion {
  const OutfitSuggestion(this.garments, this.notes);
  final List<Garment> garments;
  final List<String> notes;
}

/// Calidez que pide el día según la sensación térmica (1 fresca, 2 media, 3 abrigo).
int targetWarmth(double feelsLike) => feelsLike < 10
    ? 3
    : feelsLike < 18
    ? 2
    : 1;

/// Propone un conjunto con la ropa disponible, sin IA: reglas de estación y temperatura.
/// [seed] cambia la propuesta con "Otra combinación".
OutfitSuggestion suggestOutfit({
  required List<Garment> wardrobe,
  required TodayWeather weather,
  required Season season,
  int seed = 0,
}) {
  final rnd = Random(seed);
  final target = targetWarmth(weather.feelsLike);
  final notes = <String>[];

  List<Garment> pool(GarmentCategory c) {
    final inSeason = wardrobe
        .where((g) => g.category == c && g.seasons.contains(season))
        .toList();
    final base = inSeason.isNotEmpty
        ? inSeason
        : wardrobe.where((g) => g.category == c).toList();
    final exact = base.where((g) => g.warmth == target).toList();
    final near = base.where((g) => (g.warmth - target).abs() <= 1).toList();
    return exact.isNotEmpty ? exact : (near.isNotEmpty ? near : base);
  }

  Garment? pick(GarmentCategory c) {
    final p = pool(c);
    return p.isEmpty ? null : p[rnd.nextInt(p.length)];
  }

  final picked = <Garment>[];
  final dresses = pool(GarmentCategory.dress);
  final useDress = dresses.isNotEmpty && target < 3 && rnd.nextInt(3) == 0;
  if (useDress) {
    picked.add(dresses[rnd.nextInt(dresses.length)]);
  } else {
    final top = pick(GarmentCategory.top);
    final bottom = pick(GarmentCategory.bottom);
    if (top != null) picked.add(top);
    if (bottom != null) picked.add(bottom);
    if (top == null) {
      notes.add('Añade alguna prenda de arriba para completar las propuestas.');
    }
    if (bottom == null) {
      notes.add('Añade algún pantalón o falda para completar las propuestas.');
    }
  }
  if (weather.feelsLike < 18) {
    final coat = pick(GarmentCategory.outerwear);
    if (coat != null) {
      picked.add(coat);
    } else {
      notes.add('Hace fresco: te vendría bien una chaqueta o abrigo.');
    }
  }
  final shoes = pick(GarmentCategory.shoes);
  if (shoes != null) picked.add(shoes);
  if (target == 3) {
    final acc = pool(GarmentCategory.accessory);
    if (acc.isNotEmpty) picked.add(acc[rnd.nextInt(acc.length)]);
  }
  if (weather.rainChance >= 50) {
    notes.add(
      'Probabilidad de lluvia del ${weather.rainChance}%: lleva paraguas.',
    );
  }
  if (weather.max - weather.min >= 10) {
    notes.add(
      'Hoy cambia mucho la temperatura (${weather.min.round()}° a ${weather.max.round()}°): mejor ir por capas.',
    );
  }
  return OutfitSuggestion(picked, notes);
}
