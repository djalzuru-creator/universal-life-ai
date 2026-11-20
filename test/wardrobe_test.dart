import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/wardrobe/data/outfit_suggester.dart';
import 'package:universal_life_ai/features/wardrobe/data/wardrobe_models.dart';
import 'package:universal_life_ai/features/wardrobe/data/weather.dart';

Garment g(
  String id,
  GarmentCategory c, {
  int warmth = 2,
  Set<Season>? seasons,
}) => Garment(
  id: id,
  householdId: 'h',
  memberId: 'm',
  name: id,
  category: c,
  warmth: warmth,
  seasons: seasons ?? Season.values.toSet(),
);

TodayWeather w(
  double feels, {
  int rain = 0,
  double min = 10,
  double max = 15,
}) => TodayWeather(
  current: feels,
  feelsLike: feels,
  min: min,
  max: max,
  rainChance: rain,
  code: 0,
);

void main() {
  final wardrobe = [
    g('camiseta', GarmentCategory.top, warmth: 1, seasons: {Season.summer}),
    g(
      'jersey',
      GarmentCategory.top,
      warmth: 3,
      seasons: {Season.winter, Season.autumn},
    ),
    g('vaquero', GarmentCategory.bottom),
    g('abrigo', GarmentCategory.outerwear, warmth: 3),
    g('zapatillas', GarmentCategory.shoes),
    g('bufanda', GarmentCategory.accessory, warmth: 3),
  ];

  test('Día frío de invierno: jersey, abrigo y complemento', () {
    final s = suggestOutfit(
      wardrobe: wardrobe,
      weather: w(4),
      season: Season.winter,
    );
    final ids = s.garments.map((x) => x.id).toSet();
    expect(
      ids,
      containsAll(['jersey', 'vaquero', 'abrigo', 'zapatillas', 'bufanda']),
    );
    expect(ids, isNot(contains('camiseta')));
  });

  test('Día de calor en verano: sin abrigo', () {
    final s = suggestOutfit(
      wardrobe: wardrobe,
      weather: w(28, min: 20, max: 30),
      season: Season.summer,
    );
    final ids = s.garments.map((x) => x.id).toSet();
    expect(ids, contains('camiseta'));
    expect(ids, isNot(contains('abrigo')));
  });

  test('Avisos de lluvia y de cambio de temperatura', () {
    final s = suggestOutfit(
      wardrobe: wardrobe,
      weather: w(12, rain: 70, min: 5, max: 19),
      season: Season.autumn,
    );
    expect(s.notes.any((n) => n.contains('paraguas')), isTrue);
    expect(s.notes.any((n) => n.contains('capas')), isTrue);
  });

  test('Armario incompleto avisa de lo que falta', () {
    final s = suggestOutfit(
      wardrobe: [g('vaquero', GarmentCategory.bottom)],
      weather: w(25),
      season: Season.summer,
    );
    expect(s.notes.any((n) => n.contains('prenda de arriba')), isTrue);
  });

  test('Estación según mes y hemisferio', () {
    expect(Season.of(DateTime(2026, 11, 20)), Season.autumn);
    expect(Season.of(DateTime(2026, 1, 10)), Season.winter);
    expect(Season.of(DateTime(2026, 1, 10), latitude: -34), Season.summer);
  });

  test('Calidez objetivo', () {
    expect(targetWarmth(5), 3);
    expect(targetWarmth(15), 2);
    expect(targetWarmth(25), 1);
  });

  test('Open-Meteo: lectura de la respuesta', () {
    final t = WeatherService.parseToday({
      'current': {
        'temperature_2m': 11.2,
        'apparent_temperature': 9.1,
        'weather_code': 61,
      },
      'daily': {
        'temperature_2m_max': [14.0],
        'temperature_2m_min': [6.5],
        'precipitation_probability_max': [80],
      },
    });
    expect(t.description, 'Lluvia');
    expect(t.rainChance, 80);
    expect(t.feelsLike, 9.1);
  });

  test('Prenda: JSON de ida y vuelta', () {
    final json = g(
      'jersey',
      GarmentCategory.top,
      warmth: 3,
      seasons: {Season.winter},
    ).toJson();
    final back = Garment.fromJson({...json, 'id': 'x'});
    expect(back.seasons, {Season.winter});
    expect(back.warmth, 3);
    expect(back.category, GarmentCategory.top);
  });
}
