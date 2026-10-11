import '../models/day_assignment.dart';
import '../models/role.dart';

/// Elle düzenleme sırasında yapısal olarak yapılamayan bir değişiklik.
class RosterEditException implements Exception {
  const RosterEditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Nöbet listesinde elle düzenleme (saf Dart). Kural ihlallerine izin verir
/// (onları [RosterValidator] gösterir) ama aynı kişinin aynı güne iki kez
/// yazılması gibi yapısal hataları [RosterEditException] ile reddeder.
/// Girdi haritası değiştirilmez, yeni harita döner.
class RosterEditor {
  const RosterEditor._();

  /// [day] gününde [role] koltuğundaki [oldId] yerine [newId] yazar.
  /// [oldId] boşsa boş koltuğa ekler; [newId] boşsa nöbeti kaldırır
  /// (koltuk boş kalır). Hemşire sırası korunur.
  static Map<int, DayAssignment> replace(
    Map<int, DayAssignment> assignments, {
    required int day,
    required Role role,
    String? oldId,
    String? newId,
    required int nursesPerDay,
  }) {
    final current = assignments[day] ?? DayAssignment(day: day);
    if (newId != null && current.includes(newId) && newId != oldId) {
      throw const RosterEditException('Bu kişi o gün zaten nöbetçi.');
    }
    final DayAssignment updated;
    switch (role) {
      case Role.nurse:
        final nurses = [...current.nurseIds];
        if (oldId != null) {
          final i = nurses.indexOf(oldId);
          if (i < 0) {
            throw const RosterEditException('Değiştirilecek kişi o gün yok.');
          }
          if (newId == null) {
            nurses.removeAt(i);
          } else {
            nurses[i] = newId;
          }
        } else if (newId != null) {
          if (nurses.length >= nursesPerDay) {
            throw const RosterEditException('O gün boş hemşire koltuğu yok.');
          }
          nurses.add(newId);
        }
        updated = current.copyWith(nurseIds: nurses);
      case Role.radiologyTech:
        if (oldId != null && current.techId != oldId) {
          throw const RosterEditException('Değiştirilecek kişi o gün yok.');
        }
        if (oldId == null && newId != null && current.techId != null) {
          throw const RosterEditException('O gün boş tekniker koltuğu yok.');
        }
        updated = newId == null
            ? current.copyWith(clearTech: true)
            : current.copyWith(techId: newId);
    }
    return {...assignments, day: updated};
  }

  /// [a] kişisinin [dayA] nöbeti ile [b] kişisinin [dayB] nöbetini takas
  /// eder: a → dayB, b → dayA. İkisi aynı rolde olmalı.
  static Map<int, DayAssignment> swap(
    Map<int, DayAssignment> assignments, {
    required String a,
    required int dayA,
    required String b,
    required int dayB,
    required Role role,
    required int nursesPerDay,
  }) {
    if (a == b) {
      throw const RosterEditException('Aynı kişinin iki nöbeti takas edilmez.');
    }
    if (dayA == dayB) {
      throw const RosterEditException('Aynı gündeki iki nöbet takas edilmez.');
    }
    final onA = assignments[dayA];
    final onB = assignments[dayB];
    if (onA == null || !onA.includes(a) || onB == null || !onB.includes(b)) {
      throw const RosterEditException('Takas edilecek nöbet bulunamadı.');
    }
    if (onA.includes(b)) {
      throw const RosterEditException('İkinci kişi ilk gün zaten nöbetçi.');
    }
    if (onB.includes(a)) {
      throw const RosterEditException('İlk kişi ikinci gün zaten nöbetçi.');
    }
    final step = replace(
      assignments,
      day: dayA,
      role: role,
      oldId: a,
      newId: b,
      nursesPerDay: nursesPerDay,
    );
    return replace(
      step,
      day: dayB,
      role: role,
      oldId: b,
      newId: a,
      nursesPerDay: nursesPerDay,
    );
  }
}
