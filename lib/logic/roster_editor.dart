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
  /// [secondary] true ise teknikerin 16B koltuğu, değilse 24 koltuğu
  /// düzenlenir (hemşire rolünde yok sayılır).
  static Map<int, DayAssignment> replace(
    Map<int, DayAssignment> assignments, {
    required int day,
    required Role role,
    String? oldId,
    String? newId,
    required int nursesPerDay,
    bool secondary = false,
  }) {
    final current = assignments[day] ?? DayAssignment(day: day);
    if (newId != null && current.includes(newId) && newId != oldId) {
      throw const RosterEditException('Bu kişi o gün zaten nöbetçi.');
    }
    final DayAssignment updated;
    switch (role) {
      case Role.nurse:
        final nurses = [...current.nurseIds];
        // 16A koltuğun özelliğidir: yerine geçen de 16A tutar.
        final night = [...current.shift16aIds];
        final custom = {...current.customShifts};
        if (oldId != null) {
          final i = nurses.indexOf(oldId);
          if (i < 0) {
            throw const RosterEditException('Değiştirilecek kişi o gün yok.');
          }
          final was16a = night.remove(oldId);
          final code = custom.remove(oldId);
          if (newId == null) {
            nurses.removeAt(i);
          } else {
            nurses[i] = newId;
            if (was16a) night.add(newId);
            if (code != null) custom[newId] = code;
          }
        } else if (newId != null) {
          if (nurses.length >= nursesPerDay) {
            throw const RosterEditException('O gün boş hemşire koltuğu yok.');
          }
          nurses.add(newId);
        }
        updated = current.copyWith(
          nurseIds: nurses,
          shift16aIds: night,
          customShifts: custom,
        );
      case Role.radiologyTech:
        final slotId = secondary ? current.tech16bId : current.techId;
        if (oldId != null && slotId != oldId) {
          throw const RosterEditException('Değiştirilecek kişi o gün yok.');
        }
        if (oldId == null && newId != null && slotId != null) {
          throw const RosterEditException('O gün boş tekniker koltuğu yok.');
        }
        if (secondary) {
          updated = newId == null
              ? current.copyWith(clearTech16b: true)
              : current.copyWith(tech16bId: newId);
        } else {
          // 16A koltuğun özelliğidir: yerine geçen de 16A tutar.
          final was16a = oldId != null && current.is16a(oldId);
          final code = oldId == null ? null : current.customShiftOf(oldId);
          updated = newId == null
              ? current.copyWith(clearTech: true)
              : current.copyWith(
                  techId: newId,
                  shift16aIds: [
                    for (final id in current.shift16aIds)
                      if (id != oldId) id,
                    if (was16a) newId,
                  ],
                  customShifts: {
                    for (final e in current.customShifts.entries)
                      if (e.key != oldId) e.key: e.value,
                    newId: ?code,
                  },
                );
        }
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
    // Her kişi kendi günündeki koltuğunu (24 ya da 16B) korur.
    final secondaryA = onA.isSecondaryTech(a);
    final secondaryB = onB.isSecondaryTech(b);
    final step = replace(
      assignments,
      day: dayA,
      role: role,
      oldId: a,
      newId: b,
      nursesPerDay: nursesPerDay,
      secondary: secondaryA,
    );
    return replace(
      step,
      day: dayB,
      role: role,
      oldId: b,
      newId: a,
      nursesPerDay: nursesPerDay,
      secondary: secondaryB,
    );
  }

  /// Serbest düzenleme: kişi [day] gününde nöbetçiyse çıkarır, değilse
  /// ekler. Koltuk sınırı ve kurallar uygulanmaz (ihlaller uyarı olarak
  /// görünür): hemşire dolu güne de eklenir. Teknikerde 24 koltuğu boşsa
  /// oraya, değilse ([twoTechs] ise) 16B koltuğuna yazılır; ikisi de doluysa
  /// [RosterEditException].
  static Map<int, DayAssignment> toggle(
    Map<int, DayAssignment> assignments, {
    required int day,
    required String personId,
    required Role role,
    bool twoTechs = false,
  }) {
    final current = assignments[day] ?? DayAssignment(day: day);
    final DayAssignment updated;
    if (current.includes(personId)) {
      updated = current.nurseIds.contains(personId)
          ? current.copyWith(
              nurseIds: [
                for (final id in current.nurseIds)
                  if (id != personId) id,
              ],
            )
          : current.techId == personId
          ? current.copyWith(clearTech: true)
          : current.copyWith(clearTech16b: true);
    } else {
      switch (role) {
        case Role.nurse:
          updated = current.copyWith(nurseIds: [...current.nurseIds, personId]);
        case Role.radiologyTech:
          if (current.techId == null) {
            updated = current.copyWith(techId: personId);
          } else if (twoTechs && current.tech16bId == null) {
            updated = current.copyWith(tech16bId: personId);
          } else {
            throw const RosterEditException(
              'O gün tekniker koltuğu dolu; önce birini çıkarın.',
            );
          }
      }
    }
    return {...assignments, day: updated};
  }

  /// Teknikeri [day] gününde 24 ya da ([secondary] ise) 16B koltuğuna
  /// yazar. Kişi o gün öteki koltuktaysa oradan alınır (24 → 16B ya da
  /// tersi); koltukta başkası varsa onun yerine geçer.
  /// [day] gününde nöbetçi hemşire ya da 24 koltuğundaki tekniker
  /// [personId]'yi 16A ([night] true) ya da 24 vardiyasına çevirir.
  static Map<int, DayAssignment> set16a(
    Map<int, DayAssignment> assignments, {
    required int day,
    required String personId,
    required bool night,
  }) {
    final current = assignments[day];
    if (current == null ||
        !(current.nurseIds.contains(personId) || current.techId == personId)) {
      throw const RosterEditException('Bu kişi o gün 24 nöbette değil.');
    }
    final ids = {...current.shift16aIds};
    night ? ids.add(personId) : ids.remove(personId);
    return {
      ...assignments,
      day: current.copyWith(
        shift16aIds: [
          for (final id in [...current.nurseIds, ?current.techId])
            if (ids.contains(id)) id,
        ],
        // 16A ile özel mesai birlikte olmaz.
        customShifts: {
          for (final e in current.customShifts.entries)
            if (e.key != personId) e.key: e.value,
        },
      ),
    };
  }

  /// [day] gününde koltuktaki (hemşire ya da 24 teknikeri) [personId]'nin
  /// vardiyasını [code] özel mesaisine çevirir; [code] null ise 24'e döner.
  /// 16A işareti düşer.
  static Map<int, DayAssignment> setCustomShift(
    Map<int, DayAssignment> assignments, {
    required int day,
    required String personId,
    required String? code,
  }) {
    final current = assignments[day];
    if (current == null ||
        !(current.nurseIds.contains(personId) || current.techId == personId)) {
      throw const RosterEditException('Bu kişi o gün 24 nöbette değil.');
    }
    return {
      ...assignments,
      day: current.copyWith(
        shift16aIds: [
          for (final id in current.shift16aIds)
            if (id != personId) id,
        ],
        customShifts: {
          for (final e in current.customShifts.entries)
            if (e.key != personId) e.key: e.value,
          personId: ?code,
        },
      ),
    };
  }

  /// [day] gününde koltukta olmayan [personId]'ye ek özel mesai [code]
  /// yazar; [code] null ise kaldırır.
  static Map<int, DayAssignment> setExtraShift(
    Map<int, DayAssignment> assignments, {
    required int day,
    required String personId,
    required String? code,
  }) {
    final current = assignments[day] ?? DayAssignment(day: day);
    if (code != null && current.includes(personId)) {
      throw const RosterEditException('Bu kişi o gün nöbette.');
    }
    return {
      ...assignments,
      day: current.copyWith(
        extraShifts: {
          for (final e in current.extraShifts.entries)
            if (e.key != personId) e.key: e.value,
          personId: ?code,
        },
      ),
    };
  }

  static Map<int, DayAssignment> setTechSeat(
    Map<int, DayAssignment> assignments, {
    required int day,
    required String personId,
    required bool secondary,
  }) {
    final current = assignments[day] ?? DayAssignment(day: day);
    final other = secondary ? current.techId : current.tech16bId;
    final keepOther = other == personId ? null : other;
    final updated = DayAssignment(
      day: day,
      nurseIds: current.nurseIds,
      techId: secondary ? keepOther : personId,
      tech16bId: secondary ? personId : keepOther,
      // 16B'ye geçen teknikerin 16A işareti ve özel mesaisi düşer.
      shift16aIds: [
        for (final id in current.shift16aIds)
          if (current.nurseIds.contains(id) ||
              id == (secondary ? keepOther : personId))
            id,
      ],
      customShifts: {
        for (final e in current.customShifts.entries)
          if (current.nurseIds.contains(e.key) ||
              e.key == (secondary ? keepOther : personId))
            e.key: e.value,
      },
      extraShifts: {
        for (final e in current.extraShifts.entries)
          if (e.key != personId) e.key: e.value,
      },
    );
    return {...assignments, day: updated};
  }
}
