import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../household/data/household_repository.dart';
import '../household/data/models.dart';
import '../household/data/providers.dart';
import '../household/ui/common.dart';
import '../shopping/ui/shopping_page.dart' show moduleAccessProvider;

const expenseCategories = {
  'supermercado': ('Supermercado', Icons.shopping_basket_outlined),
  'hogar': ('Hogar', Icons.home_outlined),
  'facturas': ('Facturas', Icons.receipt_long_outlined),
  'transporte': ('Transporte', Icons.directions_car_outlined),
  'ocio': ('Ocio', Icons.celebration_outlined),
  'ropa': ('Ropa', Icons.checkroom),
  'salud': ('Salud', Icons.favorite_outline),
  'educacion': ('Educación', Icons.school_outlined),
  'otros': ('Otros', Icons.more_horiz),
};

class Expense {
  const Expense(
    this.id,
    this.memberId,
    this.amount,
    this.category,
    this.description,
    this.spentOn,
  );
  final String id;
  final String? memberId;
  final double amount;
  final String category;
  final String? description;
  final DateTime spentOn;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    j['id'] as String,
    j['member_id'] as String?,
    (j['amount'] as num).toDouble(),
    j['category'] as String,
    j['description'] as String?,
    DateTime.parse(j['spent_on'] as String),
  );
}

class BudgetLimit {
  const BudgetLimit(this.id, this.memberId, this.monthlyLimit);
  final String id;
  final String? memberId;
  final double monthlyLimit;
}

/// Resumen de un mes: total, por categoría y por miembro.
class MonthSummary {
  MonthSummary(List<Expense> all, DateTime month)
    : expenses =
          all
              .where(
                (e) =>
                    e.spentOn.year == month.year &&
                    e.spentOn.month == month.month,
              )
              .toList()
            ..sort((a, b) => b.spentOn.compareTo(a.spentOn));

  final List<Expense> expenses;
  double get total => expenses.fold(0, (s, e) => s + e.amount);
  Map<String, double> get byCategory {
    final m = <String, double>{};
    for (final e in expenses) {
      m[e.category] = (m[e.category] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  double byMember(String memberId) => expenses
      .where((e) => e.memberId == memberId)
      .fold(0, (s, e) => s + e.amount);
}

String euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

final _expensesProvider = StreamProvider.family<List<Expense>, String>(
  (ref, hid) => ref
      .watch(supabaseProvider)
      .from('expenses')
      .stream(primaryKey: ['id'])
      .eq('household_id', hid)
      .map((rows) => rows.map(Expense.fromJson).toList()),
);

final _limitsProvider = FutureProvider.family<List<BudgetLimit>, String>((
  ref,
  hid,
) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('budget_limits')
      .select()
      .eq('household_id', hid);
  return [
    for (final r in rows)
      BudgetLimit(
        r['id'] as String,
        r['member_id'] as String?,
        (r['monthly_limit'] as num).toDouble(),
      ),
  ];
});

class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _addExpense(String? myMemberId) async {
    final amount = TextEditingController();
    final desc = TextEditingController();
    var category = 'supermercado';
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Apuntar gasto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Importe',
                    suffixText: '€',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final e in expenseCategories.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
                  ],
                  onChanged: (v) => setState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: desc,
                  decoration: const InputDecoration(
                    labelText: 'Concepto (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${date.day}/${date.month}/${date.year}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => date = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    if (ok == true && value != null && value > 0) {
      await _run(
        () => _db.from('expenses').insert({
          'household_id': widget.householdId,
          'member_id': myMemberId,
          'amount': value,
          'category': category,
          'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
          'spent_on':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        }),
      );
    } else if (ok == true) {
      if (mounted) showSnack(context, 'Escribe un importe válido.');
    }
    amount.dispose();
    desc.dispose();
  }

  Future<void> _setLimit(
    String? memberId,
    String label,
    BudgetLimit? current,
  ) async {
    final c = TextEditingController(
      text: current?.monthlyLimit.toStringAsFixed(0) ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Límite mensual: $label'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Importe máximo al mes',
            suffixText: '€',
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar'),
            ),
          if (current != null)
            TextButton(
              onPressed: () {
                c.text = '';
                Navigator.pop(ctx, true);
              },
              child: const Text('Quitar límite'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    c.dispose();
    if (ok != true) return;
    await _run(() async {
      if (current != null) {
        await _db.from('budget_limits').delete().eq('id', current.id);
      }
      if (v != null && v > 0) {
        await _db.from('budget_limits').insert({
          'household_id': widget.householdId,
          'member_id': memberId,
          'monthly_limit': v,
        });
      }
      ref.invalidate(_limitsProvider(widget.householdId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final hid = widget.householdId;
    final access =
        ref
            .watch(
              moduleAccessProvider((
                householdId: hid,
                module: AppModule.budget,
              )),
            )
            .value ??
        const {};
    final me = ref.watch(myMemberProvider(hid)).value;
    final members = ref.watch(membersProvider(hid)).value ?? const <Member>[];
    final limits =
        ref.watch(_limitsProvider(hid)).value ?? const <BudgetLimit>[];
    final expenses = ref.watch(_expensesProvider(hid));
    final isOwner = me?.isOwner ?? false;
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Presupuesto')),
      floatingActionButton: access.contains(PermissionAction.create)
          ? FloatingActionButton.extended(
              onPressed: () => _addExpense(me?.id),
              icon: const Icon(Icons.add),
              label: const Text('Apuntar gasto'),
            )
          : null,
      body: expenses.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(e, onRetry: () => ref.invalidate(_expensesProvider(hid))),
        data: (all) {
          final s = MonthSummary(all, _month);
          final householdLimit = limits
              .where((l) => l.memberId == null)
              .firstOrNull;
          Widget bar(double spent, double? limit) {
            if (limit == null) return const SizedBox.shrink();
            final ratio = (spent / limit).clamp(0.0, 1.0);
            final over = spent > limit;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: over
                    ? theme.colorScheme.error
                    : (ratio > 0.8 ? Colors.orange.shade700 : null),
              ),
            );
          }

          return PageBody(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${months[_month.month - 1]} ${_month.year}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gastado en el hogar',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        euros(s.total),
                        style: theme.textTheme.headlineMedium,
                      ),
                      if (householdLimit != null)
                        Text(
                          s.total > householdLimit.monthlyLimit
                              ? 'Te has pasado ${euros(s.total - householdLimit.monthlyLimit)} del límite de ${euros(householdLimit.monthlyLimit)}'
                              : 'Quedan ${euros(householdLimit.monthlyLimit - s.total)} de ${euros(householdLimit.monthlyLimit)}',
                        ),
                      bar(s.total, householdLimit?.monthlyLimit),
                      if (isOwner)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                _setLimit(null, 'hogar', householdLimit),
                            child: Text(
                              householdLimit == null
                                  ? 'Poner límite mensual'
                                  : 'Cambiar límite',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (s.byCategory.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Por categoría', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final e in s.byCategory.entries)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            expenseCategories[e.key]?.$2 ?? Icons.more_horiz,
                          ),
                          title: Text(expenseCategories[e.key]?.$1 ?? e.key),
                          subtitle: LinearProgressIndicator(
                            value: s.total == 0 ? 0 : e.value / s.total,
                          ),
                          trailing: Text(euros(e.value)),
                        ),
                    ],
                  ),
                ),
              ],
              if (members.length > 1) ...[
                const SizedBox(height: 16),
                Text('Por persona', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final m in members)
                        Builder(
                          builder: (context) {
                            final limit = limits
                                .where((l) => l.memberId == m.id)
                                .firstOrNull;
                            final spent = s.byMember(m.id);
                            return ListTile(
                              title: Text(m.displayName),
                              subtitle: limit == null
                                  ? null
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Límite ${euros(limit.monthlyLimit)}',
                                        ),
                                        bar(spent, limit.monthlyLimit),
                                      ],
                                    ),
                              trailing: Text(euros(spent)),
                              onTap: isOwner
                                  ? () => _setLimit(m.id, m.displayName, limit)
                                  : null,
                            );
                          },
                        ),
                    ],
                  ),
                ),
                if (isOwner)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Toca a una persona para ponerle un límite mensual.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text('Movimientos', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (s.expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sin gastos este mes.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final e in s.expenses)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            expenseCategories[e.category]?.$2 ??
                                Icons.more_horiz,
                          ),
                          title: Text(
                            e.description ??
                                expenseCategories[e.category]?.$1 ??
                                e.category,
                          ),
                          subtitle: Text(
                            [
                              '${e.spentOn.day}/${e.spentOn.month}',
                              if (members
                                      .where((m) => m.id == e.memberId)
                                      .firstOrNull
                                  case final m?)
                                m.displayName,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(euros(e.amount)),
                              if (access.contains(PermissionAction.delete))
                                IconButton(
                                  tooltip: 'Borrar',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed: () => _run(
                                    () => _db
                                        .from('expenses')
                                        .delete()
                                        .eq('id', e.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}
