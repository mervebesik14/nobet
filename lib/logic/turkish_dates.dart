/// `intl` başlatması gerektirmeden kısa Türkçe tarih metinleri.
library;

const turkishMonthNames = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', //
  'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// "14 Ekim"
String formatDayMonth(int day, int month) =>
    '$day ${turkishMonthNames[month - 1]}';

const turkishWeekdayNames = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar', //
];

/// "14 Ekim Çarşamba"
String formatDayMonthWeekday(int year, int month, int day) =>
    '${formatDayMonth(day, month)} '
    '${turkishWeekdayNames[DateTime(year, month, day).weekday - 1]}';
