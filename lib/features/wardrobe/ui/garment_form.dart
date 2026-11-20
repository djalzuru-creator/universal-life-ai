import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../household/data/household_repository.dart';
import '../../household/ui/common.dart';
import '../data/wardrobe_models.dart';
import '../data/wardrobe_repository.dart';
import 'garment_photo.dart';

Future<bool?> showGarmentForm(
  BuildContext context, {
  required Garment initial,
  bool canDelete = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _GarmentForm(initial: initial, canDelete: canDelete),
  ),
);

class _GarmentForm extends ConsumerStatefulWidget {
  const _GarmentForm({required this.initial, required this.canDelete});
  final Garment initial;
  final bool canDelete;

  @override
  ConsumerState<_GarmentForm> createState() => _GarmentFormState();
}

class _GarmentFormState extends ConsumerState<_GarmentForm> {
  late final _name = TextEditingController(text: widget.initial.name);
  late GarmentCategory _category = widget.initial.category;
  late String _color = widget.initial.color;
  late final Set<Season> _seasons = {...widget.initial.seasons};
  late final Set<String> _styles = {...widget.initial.styles};
  late int _warmth = widget.initial.warmth;
  late bool _shared = widget.initial.isShared;
  Uint8List? _newPhoto;
  String _newPhotoMime = 'image/jpeg';
  bool _busy = false;

  bool get _isNew => widget.initial.id == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        if (mounted) {
          showSnack(context, 'La foto es demasiado grande (máximo 2 MB).');
        }
        return;
      }
      setState(() {
        _newPhoto = bytes;
        _newPhotoMime = file.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      if (mounted) {
        showSnack(context, 'No se pudo abrir la cámara o la galería.');
      }
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Ponle un nombre, por ejemplo "Camisa blanca".');
      return;
    }
    if (_seasons.isEmpty) {
      showSnack(context, 'Elige al menos una estación.');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(wardrobeRepositoryProvider);
    try {
      var photoPath = widget.initial.photoPath;
      if (_newPhoto != null) {
        photoPath = await repo.uploadPhoto(
          widget.initial.householdId,
          widget.initial.memberId,
          _newPhoto!,
          _newPhotoMime,
        );
      }
      await repo.saveGarment(
        Garment(
          id: widget.initial.id,
          householdId: widget.initial.householdId,
          memberId: widget.initial.memberId,
          name: _name.text.trim(),
          category: _category,
          color: _color,
          seasons: _seasons,
          styles: _styles,
          warmth: _warmth,
          photoPath: photoPath,
          isShared: _shared,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showSnack(context, friendlyError(e));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(wardrobeRepositoryProvider).deleteGarment(widget.initial);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showSnack(context, friendlyError(e));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(t, style: theme.textTheme.labelLarge),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isNew ? 'Nueva prenda' : 'Editar prenda',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _newPhoto != null
                    ? Image.memory(
                        _newPhoto!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      )
                    : GarmentPhoto(widget.initial, size: 96),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Hacer foto'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('De la galería'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Camisa blanca de lino',
            ),
          ),
          section('Tipo'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in GarmentCategory.values)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          section('Color'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in garmentColors.entries)
                Tooltip(
                  message: e.key,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = e.key),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == e.key
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _color == e.key ? 3 : 1,
                        ),
                      ),
                      child: _color == e.key
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: e.value.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Color: $_color', style: theme.textTheme.bodySmall),
          ),
          section('¿Cuándo te la pones?'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in Season.values)
                FilterChip(
                  label: Text(s.label),
                  selected: _seasons.contains(s),
                  onSelected: (v) =>
                      setState(() => v ? _seasons.add(s) : _seasons.remove(s)),
                ),
            ],
          ),
          section('Abriga'),
          SegmentedButton<int>(
            segments: [
              for (final e in warmthLabels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_warmth},
            onSelectionChanged: (v) => setState(() => _warmth = v.first),
          ),
          section('Estilo (opcional)'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in garmentStyles)
                FilterChip(
                  label: Text(s),
                  selected: _styles.contains(s),
                  onSelected: (v) =>
                      setState(() => v ? _styles.add(s) : _styles.remove(s)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compartir con la familia'),
            subtitle: const Text(
              'Los demás podrán verla (por ejemplo, para pedírtela prestada).',
            ),
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Guardando…' : 'Guardar'),
          ),
          if (!_isNew && widget.canDelete) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Quitar del armario'),
            ),
          ],
        ],
      ),
    );
  }
}
