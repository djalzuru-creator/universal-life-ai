import 'package:flutter_test/flutter_test.dart';
import 'package:universal_life_ai/features/agenda/agenda.dart';

FamilyEvent ev(String t, DateTime d) =>
    FamilyEvent(householdId: 'h', title: t, startsAt: d);

void main() {
  test('agrupa por día y oculta lo pasado', () {
    final now = DateTime(2026, 11, 21, 10);
    final g = groupUpcoming([
      ev('Ayer', DateTime(2026, 11, 20, 9)),
      ev('Tarde', DateTime(2026, 11, 21, 18)),
      ev('Mañana', DateTime(2026, 11, 21, 8)),
      ev('Lunes', DateTime(2026, 11, 23, 9)),
    ], now);
    expect(g.keys, [DateTime(2026, 11, 21), DateTime(2026, 11, 23)]);
    expect(g[DateTime(2026, 11, 21)]!.map((e) => e.title), ['Mañana', 'Tarde']);
  });
}
