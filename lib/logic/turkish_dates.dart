/// `intl` başlatması gerektirmeden kısa Türkçe tarih metinleri.
library;

const turkishMonthNames = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', //
  'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// "14 Ekim"
String formatDayMonth(int day, int month) =>
    '$day ${turkishMonthNames[month - 1]}';
