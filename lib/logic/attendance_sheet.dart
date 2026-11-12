import '../models/models.dart';
import 'day_shift_planner.dart';

/// Puantajda bir kişinin satırı: gün gün kodlar ve toplamlar.
typedef AttendanceRow = ({
  String personId,
  String name,
  String title,
  List<String> codes,
  int shifts,
  int dayShifts,
  int offDays,
  int leaveDays,
});

/// Puantaj (devam) cetveli (saf Dart): kişi × gün, her hücrede o günün
/// kodu. Nöbet "24" (ya da 16A, 16B, özel mesai adı), gündüz mesaisi "7A",
/// ek mesai "+4A" gibi eklenir; izinler Y.İ. / Ş.İ. / R.; hafta içi
/// çalışmadığı gün "N.İ." (nöbet izni); hafta sonu ve tam gün tatilde boş.
/// Pasif ya da işe başlamadan önceki günler boştur.
class AttendanceSheet {
  const AttendanceSheet._();

  /// Hafta içi çalışmadığı gün.
  static const offCode = 'N.İ.';

  static const _titles = {
    Role.nurse: 'Hemşire',
    Role.radiologyTech: 'Radyoloji Teknikeri',
  };

  /// [rows]: tablodaki kişiler, sırasıyla; [closedDays]: hafta sonu ve tam
  /// gün resmi tatiller (boş kalır).
  static List<AttendanceRow> build({
    required MonthPlan plan,
    required List<({String id, String name, Role role})> rows,
    required Iterable<Person> people,
    required Set<int> closedDays,
    Iterable<DayShift> dayShifts = const [],
  }) {
    final byId = {for (final p in people) p.id: p};
    final dayShiftOn = {for (final s in dayShifts) (s.personId, s.day)};
    final days = plan.daysInMonth;
    return [
      for (final r in rows)
        () {
          final person = byId[r.id];
          final inactive = {...?person?.inactiveDaysIn(plan.year, plan.month)};
          final leaveOn = <int, LeaveType>{
            for (final type in LeaveType.values.reversed)
              for (final d in plan.leaveOf(r.id, type)) d: type,
          };
          var shifts = 0, day7 = 0, off = 0, leave = 0;
          final codes = <String>[];
          for (var d = 1; d <= days; d++) {
            final a = plan.assignments[d];
            final parts = <String>[];
            if (a != null && a.includes(r.id)) {
              parts.add(a.shiftCode(r.id));
              shifts++;
            }
            if (dayShiftOn.contains((r.id, d))) {
              parts.add('7A');
              day7++;
            }
            if (a?.extraShiftOf(r.id) case final code?) parts.add(code);
            String code;
            if (parts.isNotEmpty) {
              code = parts.join('+');
            } else if (leaveOn[d] case final type?) {
              code = type.shortLabel;
              leave++;
            } else if (inactive.contains(d) || closedDays.contains(d)) {
              code = '';
            } else {
              code = offCode;
              off++;
            }
            codes.add(code);
          }
          return (
            personId: r.id,
            name: r.name,
            title: person?.isChargeNurse ?? false
                ? 'Sorumlu Hemşire'
                : _titles[r.role]!,
            codes: codes,
            shifts: shifts,
            dayShifts: day7,
            offDays: off,
            leaveDays: leave,
          );
        }(),
    ];
  }

  /// Açıklama satırları.
  static List<String> legend({Iterable<String> customCodes = const []}) => [
    '24 = 24 saat nöbet (08:00–08:00)',
    '16A = 16:00–08:00 nöbet',
    '16B = 08:00–24:00',
    '7A = gündüz mesaisi',
    '$offCode = nöbet izni (hafta içi çalışmadığı gün)',
    for (final t in LeaveType.values) '${t.shortLabel} = ${t.label}',
    for (final c in customCodes) '$c = özel mesai',
    'Boş = hafta sonu / resmi tatil',
  ];
}
