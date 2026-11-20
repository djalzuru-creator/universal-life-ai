import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wardrobe_models.dart';
import '../data/wardrobe_repository.dart';

/// Foto de la prenda (enlace temporal privado) o su icono si no tiene foto.
class GarmentPhoto extends ConsumerWidget {
  const GarmentPhoto(this.garment, {super.key, this.size});

  final Garment garment;
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color:
          garmentColors[garment.color]?.withValues(alpha: 0.25) ??
          scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        garment.category.icon,
        size: (size ?? 64) * 0.45,
        color: scheme.onSurfaceVariant,
      ),
    );
    final path = garment.photoPath;
    if (path == null) return fallback;
    return ref
        .watch(photoUrlProvider(path))
        .when(
          loading: () => SizedBox(width: size, height: size),
          error: (_, _) => fallback,
          data: (url) => Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
        );
  }
}
