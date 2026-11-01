import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/logic/summary_columns.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final summary = RosterSummary.build(
    year: 2026,
    month: 11,
    assignments: const {
      1: DayAssignment(day: 1, nurseIds: ['a']),
      3: DayAssignment(day: 3, nurseIds: ['b']),
    },
    people: const [
      Person(id: 'a', name: 'Ayşe', role: Role.nurse),
      Person(id: 'b', name: 'Banu', role: Role.nurse),
    ],
    holidays: const [],
    settings: const RosterSettings(),
  );

  test('seçilenler sabit sırayla; kimsede olmayan tatil/7A düşer', () {
    expect(
      SummaryColumn.visible(summary, {
        SummaryColumn.overtime,
        SummaryColumn.shifts,
        SummaryColumn.nationalHoliday,
        SummaryColumn.dayShifts,
      }),
      [SummaryColumn.shifts, SummaryColumn.overtime],
    );
  });

  test('değerler ve ortalama', () {
    final ayse = summary.people.firstWhere((p) => p.name == 'Ayşe');
    expect(SummaryColumn.shifts.valueOf(ayse), 1);
    expect(SummaryColumn.weekend.valueOf(ayse), 1); // 1 Kasım Pazar
    final avg = summary.averages[Role.nurse]!;
    expect(SummaryColumn.shifts.averageOf(avg, summary), 1);
    expect(SummaryColumn.longGaps.averageOf(avg, summary), isNull);
    expect(
      SummaryColumn.required.averageOf(avg, summary),
      summary.requiredHours,
    );
  });

  test('adlardan geri okuma', () {
    expect(SummaryColumn.fromNames(['overtime', 'yok', 'shifts']), {
      SummaryColumn.overtime,
      SummaryColumn.shifts,
    });
  });
}
