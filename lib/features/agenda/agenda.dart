import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../household/data/household_repository.dart';
import '../household/data/models.dart';
import '../household/data/providers.dart';
import '../household/ui/common.dart';
import '../household/ui/dashboard_page.dart' show spanishDate;
import '../shopping/ui/shopping_page.dart' show moduleAccessProvider;

class FamilyEvent {
  const FamilyEvent({
    this.id,
    required this.householdId,
    required this.title,
    required this.startsAt,
    this.allDay = false,
    this.memberId,
    this.note,
    this.createdBy,
  });
  final String? id;
  final String householdId;
  final String title;
  final DateTime startsAt;
  final bool allDay;
  final String? memberId;
  final String? note;
  final String? createdBy;

  factory FamilyEvent.fromJson(Map<String, dynamic> j) => FamilyEvent(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    title: j['title'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    allDay: j['all_day'] as bool? ?? false,
    memberId: j['member_id'] as String?,
    note: j['note'] as String?,
    createdBy: j['created_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'household_id': householdId,
    'title': title,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'all_day': allDay,
    'member_id': memberId,
    'note': note,
  };
}

/// Agrupa por día los eventos de hoy en adelante.
Map<DateTime, List<FamilyEvent>> groupUpcoming(
  List<FamilyEvent> all,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <DateTime, List<FamilyEvent>>{};
  final sorted = [...all]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (final e in sorted) {
    final d = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
    if (d.isBefore(today)) continue;
    out.putIfAbsent(d, () => []).add(e);
  }
  return out;
}

final eventsProvider = StreamProvider.family<List<FamilyEvent>, String>(
  (ref, hid) => ref
      .watch(supabaseProvider)
      .from('events')
      .stream(primaryKey: ['id'])
      .eq('household_id', hid)
      .map((rows) => rows.map(FamilyEvent.fromJson).toList()),
);

class AgendaPage extends ConsumerWidget {
  const AgendaPage({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(householdId));
    final members = ref.watch(membersProvider(householdId)).value ?? const [];
    final access =
        ref
            .watch(
              moduleAccessProvider((
                householdId: householdId,
                module: AppModule.agenda,
              )),
            )
            .value ??
        const {};
    final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
    final canCreate = access.contains(PermissionAction.create);
    bool canChange(FamilyEvent e) =>
        access.contains(PermissionAction.edit) ||
        (canCreate && e.createdBy == uid);
    String? who(String? id) {
      for (final m in members) {
        if (m.id == id) return m.displayName;
      }
      return null;
    }

    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda familiar')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, members, null),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo evento'),
            )
          : null,
      body: events.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          e,
          onRetry: () => ref.invalidate(eventsProvider(householdId)),
        ),
        data: (all) {
          final days = groupUpcoming(all, now);
          final today = DateTime(now.year, now.month, now.day);
          return PageBody(
            children: [
              if (days.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No hay nada apuntado. Pulsa "Nuevo evento" para añadir el primero.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final MapEntry(key: day, value: list) in days.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    day == today
                        ? 'Hoy'
                        : day == today.add(const Duration(days: 1))
                        ? 'Mañana'
                        : spanishDate(day),
                    style: const TextStyle(
                      color: Brand.violet,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      for (final e in list)
                        ListTile(
                          leading: Text(
                            e.allDay
                                ? 'Todo\nel día'
                                : '${e.startsAt.hour.toString().padLeft(2, '0')}:${e.startsAt.minute.toString().padLeft(2, '0')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Brand.muted,
                              fontSize: 13,
                            ),
                          ),
                          title: Text(e.title),
                          subtitle: () {
                            final s = [
                              ?who(e.memberId),
                              if (e.note != null) e.note!,
                            ].join(' · ');
                            return s.isEmpty ? null : Text(s);
                          }(),
                          onTap: canChange(e)
                              ? () => _edit(context, ref, members, e)
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
    FamilyEvent? e,
  ) async {
    final title = TextEditingController(text: e?.title ?? '');
    final note = TextEditingController(text: e?.note ?? '');
    final now = DateTime.now();
    var date =
        e?.startsAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    var allDay = e?.allDay ?? false;
    var memberId = e?.memberId;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(e == null ? 'Nuevo evento' : 'Editar evento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: e == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: '¿Qué? (dentista, cumpleaños…)',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(spanishDate(date)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (d != null) {
                      setState(
                        () => date = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          date.hour,
                          date.minute,
                        ),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Todo el día'),
                  value: allDay,
                  onChanged: (v) => setState(() => allDay = v),
                ),
                if (!allDay)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: Text(
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(date),
                      );
                      if (t != null) {
                        setState(
                          () => date = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            t.hour,
                            t.minute,
                          ),
                        );
                      }
                    },
                  ),
                DropdownButtonFormField<String?>(
                  initialValue: memberId,
                  decoration: const InputDecoration(labelText: '¿Para quién?'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Toda la familia'),
                    ),
                    for (final m in members)
                      DropdownMenuItem(value: m.id, child: Text(m.displayName)),
                  ],
                  onChanged: (v) => setState(() => memberId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Nota'),
                ),
              ],
            ),
          ),
          actions: [
            if (e != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Borrar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final t = title.text.trim();
    final n = note.text.trim();
    title.dispose();
    note.dispose();
    if (result == null) return;
    final db = ref.read(supabaseProvider).from('events');
    try {
      if (result == 'delete') {
        await db.delete().eq('id', e!.id!);
        return;
      }
      if (t.isEmpty) {
        if (context.mounted) showSnack(context, 'Escribe qué es el evento.');
        return;
      }
      final ev = FamilyEvent(
        householdId: householdId,
        title: t,
        startsAt: allDay ? DateTime(date.year, date.month, date.day) : date,
        allDay: allDay,
        memberId: memberId,
        note: n.isEmpty ? null : n,
      );
      if (e == null) {
        await db.insert(ev.toJson());
      } else {
        await db.update(ev.toJson()).eq('id', e.id!);
      }
    } catch (err) {
      if (context.mounted) showSnack(context, friendlyError(err));
    }
  }
}
