import 'dart:convert';

import 'package:http/http.dart' as http;

/// Datos básicos de un producto encontrado por su código de barras.
class ProductInfo {
  const ProductInfo({
    required this.name,
    this.brand,
    this.quantity,
    this.unit,
    this.imageUrl,
    this.isSpanish = false,
    this.generic,
    this.categories,
  });

  final String name;
  final String? brand;
  final double? quantity;
  final String? unit;
  final String? imageUrl;

  /// El nombre ya venía en español.
  final bool isSpanish;
  final String? generic;
  final String? categories;
}

/// Consulta Open Food Facts (base de datos abierta y gratuita).
/// https://openfoodfacts.github.io/openfoodfacts-server/api/
class OpenFoodFacts {
  OpenFoodFacts({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static bool isValidBarcode(String code) =>
      RegExp(r'^[0-9]{8,14}$').hasMatch(code);

  /// Devuelve null si el producto no está en la base de datos o no hay conexión.
  Future<ProductInfo?> lookup(String barcode) async {
    if (!isValidBarcode(barcode)) return null;
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$barcode.json',
      {
        'fields': 'product_name,product_name_es,generic_name,generic_name_es,categories,lang,brands,product_quantity,product_quantity_unit,image_front_small_url',
      },
    );
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parse(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static ProductInfo? parse(Map<String, dynamic> body) {
    if (body['status'] != 1) return null;
    final p = body['product'] as Map<String, dynamic>? ?? const {};
    String? text(String k) {
      final v = p[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final es = text('product_name_es');
    final name = es ?? text('product_name');
    if (name == null) return null;
    final brand = text('brands')?.split(',').first.trim();
    final rawQty = p['product_quantity'];
    final qty = rawQty is num
        ? rawQty.toDouble()
        : double.tryParse('${rawQty ?? ''}');
    final rawUnit = text('product_quantity_unit')?.toLowerCase();
    const units = {'g': 'g', 'kg': 'kg', 'ml': 'ml', 'l': 'l', 'cl': 'ml'};
    final unit = units[rawUnit];
    final image = text('image_front_small_url');
    return ProductInfo(
      name: name,
      brand: brand,
      quantity: qty == null || unit == null
          ? null
          : (rawUnit == 'cl' ? qty * 10 : qty),
      unit: qty == null ? null : unit,
      imageUrl: image != null && image.startsWith('https://') ? image : null,
      isSpanish: es != null || text('lang') == 'es',
      generic: text('generic_name_es') ?? text('generic_name'),
      categories: text('categories'),
    );
  }
}
