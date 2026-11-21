import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/aguilucho_ai.dart';
import 'open_food_facts.dart';
import 'pantry_repository.dart';

/// Producto escaneado, con el nombre en español y un resumen si se pudo.
class ScannedProduct {
  const ScannedProduct({
    required this.barcode,
    required this.info,
    required this.name,
    this.summary,
  });
  final String barcode;
  final ProductInfo? info;
  final String name;
  final String? summary;
}

/// Busca el código en Open Food Facts y pide a Aguilucho el nombre en
/// español y un resumen. Si la IA falla, se queda el nombre original.
Future<ScannedProduct> lookupScanned(Ref ref, String code) async {
  final info = await ref.read(openFoodFactsProvider).lookup(code);
  if (info == null) return ScannedProduct(barcode: code, info: null, name: '');
  try {
    final ai = await ref
        .read(aguiluchoAiProvider)
        .product(
          name: info.name,
          brand: info.brand,
          generic: info.generic,
          categories: info.categories,
        )
        .timeout(const Duration(seconds: 15));
    return ScannedProduct(
      barcode: code,
      info: info,
      name: info.isSpanish || ai.name.isEmpty ? info.name : ai.name,
      summary: ai.summary.isEmpty ? null : ai.summary,
    );
  } catch (_) {
    return ScannedProduct(barcode: code, info: info, name: info.name);
  }
}

final scanLookupProvider = Provider<Future<ScannedProduct> Function(String)>(
  (ref) =>
      (code) => lookupScanned(ref, code),
);
