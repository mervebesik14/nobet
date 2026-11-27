import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/leave_stretch.dart';

void main() {
  bool weekday(DateTime d) =>
      d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;

  test('5 iş günü izin + önceki ve sonraki hafta sonu = 9 gün', () {
    // Ekim 2026: 12–16 Pzt–Cuma izin; 9 Cuma ve 19 Pzt nöbet.
    final work = {DateTime(2026, 10, 9), DateTime(2026, 10, 19)};
    final s = LeaveStretches.build(
      leaveDays: [for (var d = 12; d <= 16; d++) DateTime(2026, 10, d)],
      isFree: (d) => !work.contains(d),
      isWorkday: weekday,
    );
    expect(s, hasLength(1));
    final x = s.single;
    expect(x.start, DateTime(2026, 10, 10));
    expect(x.end, DateTime(2026, 10, 18));
    expect(x.leaveWorkdays, 5);
    expect(x.gapBefore, 2);
    expect(x.gapAfter, 2);
    expect(x.gapDays, 4);
    expect(x.totalDays, 9);
  });

  test('arada yalnız boş günler varsa tek blok; çalışılan gün ayırır', () {
    // 12–16 ve 19–20 izin, araları hafta sonu → tek blok.
    // 26 izin ayrı: 22 nöbet araya giriyor.
    final work = {
      DateTime(2026, 10, 9),
      DateTime(2026, 10, 22),
      DateTime(2026, 10, 28),
    };
    final s = LeaveStretches.build(
      leaveDays: [
        for (var d = 12; d <= 16; d++) DateTime(2026, 10, d),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 26),
      ],
      isFree: (d) => !work.contains(d),
      isWorkday: weekday,
    );
    expect(s, hasLength(2));
    expect(s[0].leaveStart, DateTime(2026, 10, 12));
    expect(s[0].leaveEnd, DateTime(2026, 10, 20));
    expect(s[0].leaveWorkdays, 7);
    expect(s[0].start, DateTime(2026, 10, 10));
    expect(s[0].end, DateTime(2026, 10, 21));
    expect(s[0].totalDays, 12);
    expect(s[1].start, DateTime(2026, 10, 23));
    expect(s[1].end, DateTime(2026, 10, 27));
    expect(s[1].leaveWorkdays, 1);
  });

  test('listesi olmayan günde (null) boşluk durur', () {
    final s = LeaveStretches.build(
      leaveDays: [DateTime(2026, 10, 30)],
      isFree: (d) => d.month == 10 ? true : null,
      isWorkday: weekday,
    );
    expect(s.single.end, DateTime(2026, 10, 31));
    expect(
      s.single.start,
      DateTime(
        2026,
        10,
        30,
      ).subtract(const Duration(days: LeaveStretches.maxGap)),
    );
    expect(
      LeaveStretches.build(
        leaveDays: const [],
        isFree: (_) => true,
        isWorkday: weekday,
      ),
      isEmpty,
    );
  });
}
