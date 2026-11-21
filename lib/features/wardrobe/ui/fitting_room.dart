import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../household/data/household_repository.dart';
import '../../household/ui/common.dart';
import '../data/wardrobe_models.dart';
import '../data/wardrobe_repository.dart';
import 'garment_photo.dart';

/// Conjunto puesto "en vertical": abrigo y parte de arriba, debajo el pantalón
/// (o el vestido) y abajo los zapatos. Así se ve cómo quedan juntas las prendas.
class OutfitStack extends StatelessWidget {
  const OutfitStack(this.garments, {super.key, this.width = 220});
  final List<Garment> garments;
  final double width;

  @override
  Widget build(BuildContext context) {
    Garment? of(GarmentCategory c) {
      for (final g in garments) {
        if (g.category == c) return g;
      }
      return null;
    }

    final coat = of(GarmentCategory.outerwear);
    final top = of(GarmentCategory.top);
    final dress = of(GarmentCategory.dress);
    final bottom = of(GarmentCategory.bottom);
    final shoes = of(GarmentCategory.shoes);
    final extras = garments
        .where((g) => g.category == GarmentCategory.accessory)
        .toList();
    Widget tile(Garment g, double w, double h) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: w,
        height: h,
        child: GarmentPhoto(g, size: w),
      ),
    );

    final w = width;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (coat != null || top != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (coat != null) tile(coat, top == null ? w : w * .48, w * .8),
              if (coat != null && top != null) SizedBox(width: w * .04),
              if (top != null) tile(top, coat == null ? w : w * .48, w * .8),
            ],
          ),
        if (dress != null) ...[
          const SizedBox(height: 4),
          tile(dress, w, w * 1.1),
        ] else if (bottom != null) ...[
          const SizedBox(height: 4),
          tile(bottom, w * .8, w * .95),
        ],
        if (shoes != null) ...[
          const SizedBox(height: 4),
          tile(shoes, w * .55, w * .4),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final g in extras.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: tile(g, w * .22, w * .22),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Probador: desliza cada fila para combinar prendas y guarda el conjunto.
class FittingRoom extends ConsumerStatefulWidget {
  const FittingRoom({
    super.key,
    required this.householdId,
    required this.memberId,
    required this.canSave,
  });
  final String householdId;
  final String memberId;
  final bool canSave;

  @override
  ConsumerState<FittingRoom> createState() => _FittingRoomState();
}

class _FittingRoomState extends ConsumerState<FittingRoom> {
  final _pick = <GarmentCategory, int>{};
  bool _dressMode = false;

  @override
  Widget build(BuildContext context) {
    final garments = ref.watch(garmentsProvider(widget.memberId));
    return garments.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
      data: (all) {
        List<Garment> cat(GarmentCategory c) =>
            all.where((g) => g.category == c).toList();
        final dresses = cat(GarmentCategory.dress);
        final rows = <(GarmentCategory, String, bool, double)>[
          (GarmentCategory.outerwear, 'Abrigo', true, 150),
          if (_dressMode)
            (GarmentCategory.dress, 'Vestido', false, 230)
          else ...[
            (GarmentCategory.top, 'Arriba', false, 170),
            (GarmentCategory.bottom, 'Abajo', false, 200),
          ],
          (GarmentCategory.shoes, 'Calzado', true, 110),
        ];
        final chosen = <Garment>[];
        for (final (c, _, optional, _) in rows) {
          final list = cat(c);
          final i = _pick[c] ?? 0;
          // En las filas opcionales la posición 0 es "sin prenda".
          final idx = optional ? i - 1 : i;
          if (idx >= 0 && idx < list.length) chosen.add(list[idx]);
        }
        if (all.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Añade prendas con foto en "Prendas" para probarlas aquí juntas.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return PageBody(
          children: [
            if (dresses.isNotEmpty)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Arriba + abajo')),
                  ButtonSegment(value: true, label: Text('Vestido')),
                ],
                selected: {_dressMode},
                onSelectionChanged: (s) => setState(() => _dressMode = s.first),
              ),
            const SizedBox(height: 8),
            const Text(
              'Desliza cada prenda a los lados para combinarlas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 8),
            for (final (c, label, optional, h) in rows)
              _Row(
                label: label,
                height: h,
                garments: cat(c),
                optional: optional,
                index: _pick[c] ?? 0,
                onChanged: (i) => setState(() => _pick[c] = i),
              ),
            const SizedBox(height: 12),
            if (widget.canSave)
              FilledButton.icon(
                onPressed: chosen.isEmpty ? null : () => _save(chosen),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Guardar este conjunto'),
              ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Future<void> _save(List<Garment> chosen) async {
    final c = TextEditingController(
      text: 'Conjunto del ${DateTime.now().day}/${DateTime.now().month}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar conjunto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutfitStack(chosen, width: 140),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    c.dispose();
    final n = name?.trim() ?? '';
    if (n.isEmpty) return;
    try {
      await ref
          .read(wardrobeRepositoryProvider)
          .saveOutfit(
            Outfit(
              householdId: widget.householdId,
              memberId: widget.memberId,
              name: n.length > 80 ? n.substring(0, 80) : n,
              garmentIds: [for (final g in chosen) g.id!],
            ),
          );
      ref.invalidate(outfitsProvider(widget.memberId));
      if (mounted) showSnack(context, 'Guardado en Conjuntos.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.label,
    required this.height,
    required this.garments,
    required this.optional,
    required this.index,
    required this.onChanged,
  });
  final String label;
  final double height;
  final List<Garment> garments;
  final bool optional;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final _page = PageController(
    viewportFraction: .55,
    initialPage: widget.index,
  );

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.garments.length + (widget.optional ? 1 : 0);
    if (widget.garments.isEmpty) {
      if (widget.optional) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '${widget.label}: aún no tienes prendas de este tipo.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Brand.dim),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _page,
        itemCount: count,
        onPageChanged: widget.onChanged,
        itemBuilder: (_, i) {
          final idx = widget.optional ? i - 1 : i;
          final selected = i == widget.index;
          final child = idx < 0
              ? Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Brand.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Sin ${widget.label.toLowerCase()}',
                    style: const TextStyle(color: Brand.dim),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GarmentPhoto(widget.garments[idx]),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            widget.garments[idx].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
          return AnimatedScale(
            scale: selected ? 1 : .82,
            duration: const Duration(milliseconds: 200),
            child: AnimatedOpacity(
              opacity: selected ? 1 : .45,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: selected ? Brand.glow(Brand.violet, .45) : null,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
