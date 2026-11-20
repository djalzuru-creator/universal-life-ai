import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tiempo de hoy. Datos de Open-Meteo (gratis, sin clave): https://open-meteo.com
class TodayWeather {
  const TodayWeather({
    required this.current,
    required this.feelsLike,
    required this.min,
    required this.max,
    required this.rainChance,
    required this.code,
  });

  final double current;
  final double feelsLike;
  final double min;
  final double max;
  final int rainChance;
  final int code;

  String get description => switch (code) {
    0 => 'Despejado',
    1 || 2 => 'Poco nuboso',
    3 => 'Nublado',
    45 || 48 => 'Niebla',
    >= 51 && <= 67 => 'Lluvia',
    >= 71 && <= 77 => 'Nieve',
    >= 80 && <= 82 => 'Chubascos',
    >= 85 && <= 86 => 'Nieve',
    >= 95 => 'Tormenta',
    _ => 'Variable',
  };
}

class CityResult {
  const CityResult(this.name, this.detail, this.latitude, this.longitude);
  final String name;
  final String detail;
  final double latitude;
  final double longitude;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<TodayWeather> today(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,apparent_temperature,weather_code',
      'daily':
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('No se pudo consultar el tiempo');
    }
    return parseToday(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static TodayWeather parseToday(Map<String, dynamic> body) {
    final c = body['current'] as Map<String, dynamic>;
    final d = body['daily'] as Map<String, dynamic>;
    double first(String k) => ((d[k] as List).first as num).toDouble();
    return TodayWeather(
      current: (c['temperature_2m'] as num).toDouble(),
      feelsLike: (c['apparent_temperature'] as num).toDouble(),
      min: first('temperature_2m_min'),
      max: first('temperature_2m_max'),
      rainChance:
          ((d['precipitation_probability_max'] as List).first as num?)
              ?.toInt() ??
          0,
      code: (c['weather_code'] as num).toInt(),
    );
  }

  Future<List<CityResult>> searchCity(String name) async {
    if (name.trim().length < 2) return [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': name.trim(),
      'count': '6',
      'language': 'es',
      'format': 'json',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final results =
        (jsonDecode(res.body) as Map<String, dynamic>)['results'] as List? ??
        [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        CityResult(
          r['name'] as String,
          [r['admin1'], r['country']].whereType<String>().join(', '),
          (r['latitude'] as num).toDouble(),
          (r['longitude'] as num).toDouble(),
        ),
    ];
  }
}
