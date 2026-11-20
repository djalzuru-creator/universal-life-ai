import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../household/data/household_repository.dart';
import '../../household/ui/common.dart';
import '../data/pantry_models.dart';
import '../data/pantry_repository.dart';

/// Formulario para añadir o editar un producto. Devuelve true si se guardó.
Future<bool?> showPantryItemForm(
  BuildContext context, {
  required PantryItem initial,
  bool canDelete = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _PantryItemForm(initial: initial, canDelete: canDelete),
  ),
);

class _PantryItemForm extends ConsumerStatefulWidget {
  const _PantryItemForm({required this.initial, required this.canDelete});

  final PantryItem initial;
  final bool canDelete;

  @override
  ConsumerState<_PantryItemForm> createState() => _PantryItemFormState();
}

class _PantryItemFormState extends ConsumerState<_PantryItemForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _brand = TextEditingController(text: widget.initial.brand ?? '');
  late final _quantity = TextEditingController(
    text: _num(widget.initial.quantity),
  );
  late final _price = TextEditingController(
    text: widget.initial.price == null ? '' : _num(widget.initial.price!),
  );
  late String _unit = widget.initial.unit;
  late PantryLocation _location = widget.initial.location;
  late DateTime? _expires = widget.initial.expiresOn;
  bool _busy = false;

  bool get _isNew => widget.initial.id == null;

  static String _num(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toString().replaceAll('.', ',');

  static double? _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final item = PantryItem(
      id: widget.initial.id,
      householdId: widget.initial.householdId,
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: widget.initial.barcode,
      quantity: _parse(_quantity.text) ?? 1,
      unit: _unit,
      location: _location,
      expiresOn: _expires,
      price: _parse(_price.text),
      imageUrl: widget.initial.imageUrl,
    );
    final repo = ref.read(pantryRepositoryProvider);
    try {
      await (_isNew ? repo.add(item) : repo.update(item));
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
      await ref.read(pantryRepositoryProvider).delete(widget.initial.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showSnack(context, friendlyError(e));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Fecha de caducidad',
    );
    if (picked != null) setState(() => _expires = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.initial.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.initial.imageUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _isNew ? 'Añadir producto' : 'Editar producto',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            if (widget.initial.barcode != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Código ${widget.initial.barcode}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: _isNew && _name.text.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Producto'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Marca (opcional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    validator: (v) {
                      final n = _parse(v ?? '');
                      return n == null || n < 0 ? 'Número no válido' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    items: [
                      for (final u in pantryUnits)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Dónde está', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final l in PantryLocation.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _location == l,
                    onSelected: (_) => setState(() => _location = l),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _expires == null
                    ? 'Fecha de caducidad (opcional)'
                    : 'Caduca el ${_expires!.day}/${_expires!.month}/${_expires!.year}',
              ),
            ),
            if (_expires != null)
              TextButton(
                onPressed: () => setState(() => _expires = null),
                child: const Text('Quitar fecha'),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Precio pagado (opcional)',
                suffixText: '€',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = _parse(v);
                return n == null || n < 0 ? 'Número no válido' : null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Guardar'),
            ),
            if (!_isNew && widget.canDelete) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar de la despensa'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
