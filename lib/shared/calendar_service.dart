import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/roster_calendar.dart';

/// Telefon takvimine verilen izin.
enum CalendarAccess {
  /// İzin yok.
  none,

  /// Yalnız ekleme (iOS 17+ "yalnız ekle"): eski etkinlikler silinemez.
  addOnly,

  /// Ekleme ve silme.
  full,
}

/// Telefonun takvimine doğrudan etkinlik yazar (varsayılan takvim).
/// Testlerde sahte bir sürümle değiştirilir.
class CalendarService {
  CalendarService();

  DeviceCalendar get _plugin => DeviceCalendar.instance;

  Future<CalendarAccess> requestAccess() async =>
      switch (await _plugin.requestPermissions()) {
        CalendarPermissionStatus.granted => CalendarAccess.full,
        CalendarPermissionStatus.writeOnly => CalendarAccess.addOnly,
        _ => CalendarAccess.none,
      };

  /// Etkinliği ekler, kimliğini döner.
  Future<String> add(CalendarEntry e) => _plugin.createEvent(
    title: e.title,
    startDate: e.start,
    endDate: e.end,
    description: e.description,
    reminders: const [RosterCalendar.reminderBefore],
  );

  /// Etkinliği siler; kullanıcı zaten sildiyse sessiz geçer.
  Future<void> delete(String id) async {
    try {
      await _plugin.deleteEvent(instanceId: id);
    } on DeviceCalendarException {
      // Bulunamadı ya da silinemiyor: yenisi yine eklenir.
    }
  }
}

final calendarServiceProvider = Provider<CalendarService>(
  (ref) => CalendarService(),
);
