import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/roster/roster_page.dart';
import 'package:nobet_listesi/logic/xlsx_writer.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/calendar_service.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

void main() {
  late HiveBoxes boxes;
  late FakePlatformServices services;
  late FakeCalendarService calendar;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    services = FakePlatformServices();
    calendar = FakeCalendarService();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    await boxes.people.putAll({
      'a': const Person(id: 'a', name: 'Ayşe', role: Role.nurse),
      'b': const Person(id: 'b', name: 'Banu', role: Role.nurse),
      't': const Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    });
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        assignments: {
          1: DayAssignment(day: 1, nurseIds: ['a', 'b'], techId: 't'),
        },
      ),
    );
  });

  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
          calendarServiceProvider.overrideWithValue(calendar),
        ],
        child: const MaterialApp(home: RosterPage()),
      ),
    );
  }

  /// Paylaş menüsünden [item]; tüm liste için açılan pencerede [details]
  /// true → "Liste ve ayrıntılar", false → "Yalnız liste".
  Future<void> choose(WidgetTester tester, String item, {bool? details}) async {
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
    if (details != null) {
      await tester.tap(
        find.byKey(
          ValueKey(details ? 'share-with-details' : 'share-list-only'),
        ),
      );
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Excel dosyasındaki sayfa adları.
  List<String> sheetNames(List<int> xlsx) {
    final workbook = ZipDecoder()
        .decodeBytes(xlsx)
        .firstWhere((f) => f.name == 'xl/workbook.xml');
    return RegExp(
      r'<sheet name="([^"]+)"',
    ).allMatches(utf8.decode(workbook.content)).map((m) => m[1]!).toList();
  }

  bool isPdf(List<int>? bytes) =>
      bytes != null && String.fromCharCodes(bytes.take(5)) == '%PDF-';

  testWidgets('PDF olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş', details: true);
    expect(services.calls, ['sharePdf:nobet-listesi-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('değişiklik bildirimi: paylaşılandan sonra değişen kişiler', (
    tester,
  ) async {
    await pump(tester);
    // Henüz paylaşılmadı.
    await choose(tester, 'Değişiklikleri bildir');
    expect(find.byKey(const ValueKey('mark-published')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await choose(tester, 'PDF olarak paylaş', details: false);
    expect(boxes.meta.get('publishedRoster/2026-10'), isNotNull);

    // 1 Ekim'de Banu çıkar.
    await tester.longPress(find.byKey(const ValueKey('cell-b-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.assignments[1]!.nurseIds, ['a']);
    services.calls.clear();
    await choose(tester, 'Değişiklikleri bildir');
    expect(find.byKey(const ValueKey('notice-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('notice-a')), findsNothing);
    expect(find.text('1 Ekim Perşembe: 24 kaldırıldı'), findsOneWidget);
    await tester.tap(find.text('Gönder'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['shareText']);
    await tester.tap(find.byKey(const ValueKey('notice-done')));
    await tester.pumpAndSettle();
    await choose(tester, 'Değişiklikleri bildir');
    expect(
      find.text('Paylaşılan listeden bu yana değişiklik yok.'),
      findsOneWidget,
    );
  });

  testWidgets('tüm liste: önce ne paylaşılacağı sorulur', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş');
    expect(find.text('Ne paylaşılsın?'), findsOneWidget);
    expect(find.text('Yalnız liste'), findsOneWidget);
    expect(find.text('Liste ve seçilenler'), findsOneWidget);
    // Vazgeçilirse hiçbir şey paylaşılmaz.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Ne paylaşılsın?'), findsNothing);
    expect(services.calls, isEmpty);
  });

  testWidgets('yalnız liste PDF\'i ayrıntılısından küçüktür', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş', details: false);
    final listOnly = services.lastPdf!;
    await choose(tester, 'PDF olarak paylaş', details: true);
    final withDetails = services.lastPdf!;
    expect(services.calls, [
      'sharePdf:nobet-listesi-2026-10.pdf',
      'sharePdf:nobet-listesi-2026-10.pdf',
    ]);
    expect(isPdf(listOnly), isTrue);
    expect(listOnly.length, lessThan(withDetails.length));
  });

  testWidgets('Görsel (PNG) olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'Görsel (PNG) olarak paylaş', details: false);
    expect(services.calls, ['pdfToPng', 'shareFile:nobet-listesi-2026-10.png']);
    expect(services.sharedFiles.single.mime, 'image/png');
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('Excel olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'Excel olarak paylaş', details: true);
    expect(services.calls, ['shareFile:nobet-listesi-2026-10.xlsx']);
    final file = services.sharedFiles.single;
    expect(file.mime, XlsxWriter.mimeType);
    // xlsx bir zip dosyasıdır: "PK" ile başlar.
    expect(String.fromCharCodes(file.bytes.take(2)), 'PK');
    expect(sheetNames(file.bytes), ['Nöbet Listesi', 'Mesai Özeti']);
  });

  testWidgets('özet sütunları seçilir ve hatırlanır', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excel olarak paylaş'));
    await tester.pumpAndSettle();
    // Yalnız toplam nöbet ve fazla mesai kalsın.
    for (final c in [
      'weekend',
      'preWeekend',
      'nationalHoliday',
      'religiousHoliday',
      'everyOtherDay',
      'longGaps',
      'dayShifts',
      'worked',
      'required',
    ]) {
      await tester.tap(find.byKey(ValueKey('col-$c')));
    }
    await tester.tap(find.byKey(const ValueKey('share-with-details')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final sheet = ZipDecoder()
        .decodeBytes(services.sharedFiles.single.bytes)
        .firstWhere((f) => f.name == 'xl/worksheets/sheet2.xml');
    final xml = utf8.decode(sheet.content);
    expect(xml, contains('Toplam nöbet'));
    expect(xml, contains('Fazla mesai'));
    expect(xml, isNot(contains('Hafta sonu nöbet')));
    expect(xml, isNot(contains('Çalışılan saat')));
    expect(boxes.meta.get('shareSummaryColumns'), ['shifts', 'overtime']);

    // Bir dahakinde aynı seçimle açılır.
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF olarak paylaş'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('col-weekend')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('col-shifts')))
          .value,
      isTrue,
    );
  });

  testWidgets('Excel yalnız liste: tek sayfa', (tester) async {
    await pump(tester);
    await choose(tester, 'Excel olarak paylaş', details: false);
    expect(sheetNames(services.sharedFiles.single.bytes), ['Nöbet Listesi']);
  });

  testWidgets('Yazdır', (tester) async {
    await pump(tester);
    await choose(tester, 'Yazdır');
    expect(find.text('Ne yazdırılsın?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-with-details')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['printPdf:Ekim 2026 Nöbet Listesi']);
  });

  testWidgets('kişiye özel liste mesaj olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişiye özel liste (mesaj)');
    expect(find.text('Kimin listesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Banu'),
      ),
    );
    await tester.pumpAndSettle();

    expect(services.calls, ['shareText']);
    final text = services.sharedTexts.single;
    expect(text, startsWith('Banu · Ekim 2026 nöbetleri'));
    expect(text, contains('• 1 Ekim Perşembe — 24'));
    expect(text, contains('Hemşire: Ayşe, Banu'));
    expect(text, contains('Radyoloji: Ali'));
    expect(text, endsWith('Toplam: 1 nöbet'));
  });

  testWidgets('herkesin takvim dosyası tek seferde paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Herkesin takvim dosyası');
    expect(services.calls, ['shareFiles:3']);
    expect(services.sharedFiles.map((f) => f.name), {
      'nobet-ayse-2026-10.ics',
      'nobet-banu-2026-10.ics',
      'nobet-ali-2026-10.ics',
    });
    for (final f in services.sharedFiles) {
      expect(f.mime, 'text/calendar');
      expect(utf8.decode(f.bytes), contains('DTSTART:20261001T080000'));
    }
  });

  testWidgets('nöbeti olmayanın takvim dosyası atlanır', (tester) async {
    await boxes.people.put(
      'x',
      const Person(id: 'x', name: 'Boş', role: Role.nurse),
    );
    await pump(tester);
    await choose(tester, 'Herkesin takvim dosyası');
    expect(services.calls, ['shareFiles:3']);
    expect(
      services.sharedFiles.map((f) => f.name),
      isNot(contains('nobet-bos-2026-10.ics')),
    );
  });

  group('bu telefonun takvimine ekle', () {
    Future<void> addFor(WidgetTester tester, String name) async {
      await choose(tester, 'Bu telefonun takvimine ekle');
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(name),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('nöbetler doğrudan takvime yazılır', (tester) async {
      await pump(tester);
      await addFor(tester, 'Banu');
      expect(services.calls, isEmpty);
      final e = calendar.events.values.single;
      expect(e.title, 'Nöbet (24)');
      expect(e.start, DateTime(2026, 10, 1, 8));
      expect(e.end, DateTime(2026, 10, 2, 8));
      expect(e.description, contains('Ayşe, Banu'));
      expect(find.text('Banu: 1 etkinlik takvime eklendi.'), findsOneWidget);
    });

    testWidgets('yeniden eklenince eskiler silinir, çift olmaz', (
      tester,
    ) async {
      await pump(tester);
      await addFor(tester, 'Banu');
      await addFor(tester, 'Banu');
      expect(calendar.events, hasLength(1));
      expect(
        find.text('Banu: 1 etkinlik takvime eklendi (eskiler güncellendi).'),
        findsOneWidget,
      );
      // Başka kişinin etkinlikleri ayrı tutulur.
      await addFor(tester, 'Ali');
      expect(calendar.events, hasLength(2));
    });

    testWidgets('izin yoksa yazılmaz, uyarı çıkar', (tester) async {
      calendar.access = CalendarAccess.none;
      await pump(tester);
      await addFor(tester, 'Banu');
      expect(calendar.events, isEmpty);
      expect(find.textContaining('Takvim izni yok'), findsOneWidget);
    });
  });

  testWidgets('kişiye özel takvim dosyası (.ics) paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Takvim dosyası (kişiye özel)');
    expect(find.text('Kimin listesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Banu'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(services.calls, ['shareFile:nobet-banu-2026-10.ics']);
    final file = services.sharedFiles.single;
    expect(file.mime, 'text/calendar');
    final ics = utf8.decode(file.bytes);
    expect(ics, startsWith('BEGIN:VCALENDAR'));
    // Banu 1 Ekim'de 24 nöbette: 08:00 → 2 Ekim 08:00.
    expect(ics, contains('DTSTART:20261001T080000'));
    expect(ics, contains('DTEND:20261002T080000'));
    expect(ics, contains('X-WR-CALNAME:Banu nöbetleri'));
  });

  testWidgets('herkese WhatsApp: numara rehberden eklenir, kişiye özel mesaj', (
    tester,
  ) async {
    await boxes.people.put(
      'a',
      const Person(
        id: 'a',
        name: 'Ayşe',
        role: Role.nurse,
        phone: '0532 111 22 33',
      ),
    );
    await pump(tester);
    await choose(tester, 'Herkese WhatsApp\'tan gönder');
    // Varsayılan PDF: numarası olmayana da gönderilebilir.
    expect(find.text('0 / 3 gönderildi'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('wa-b')),
        matching: find.text('Gönder'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['sharePdf:nobet-banu-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
    expect(find.text('1 / 3 gönderildi'), findsOneWidget);

    // Mesaj: WhatsApp kişinin sohbetinde açılır.
    await tester.tap(find.text('Mesaj'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 1 gönderildi'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('wa-a')),
        matching: find.text('Gönder'),
      ),
    );
    await tester.pumpAndSettle();
    final uri = services.openedUrls.single;
    expect(uri.scheme, 'whatsapp');
    expect(uri.queryParameters['phone'], '905321112233');
    expect(uri.queryParameters['text'], contains('Ayşe'));
    expect(find.text('1 / 1 gönderildi'), findsOneWidget);

    // Banu'nun numarası yok: rehberden eklenir.
    services.pickedContact = (name: 'Banu K.', phone: '+90 533 444 55 66');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('wa-b')),
        matching: find.text('Rehberden'),
      ),
    );
    await tester.pumpAndSettle();
    expect(boxes.people.get('b')!.phone, '0533 444 55 66');

    // WhatsApp yüklü değilse wa.me açılır.
    services.whatsAppInstalled = false;
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('wa-b')),
        matching: find.text('Gönder'),
      ),
    );
    await tester.pumpAndSettle();
    expect(services.openedUrls.last.host, 'wa.me');
    expect(services.openedUrls.last.path, '/905334445566');
  });

  testWidgets('fazla mesai raporu PDF olarak paylaşılır', (tester) async {
    await boxes.meta.put('reportInfo', {
      'institution': 'Örnek Devlet Hastanesi',
      'unit': 'Radyoloji',
    });
    await pump(tester);
    await choose(tester, 'Fazla mesai raporu (PDF)');
    expect(services.calls, ['sharePdf:fazla-mesai-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('kişiye özel liste PDF olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişiye özel liste (PDF)');
    expect(find.text('Kimin listesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Banu'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(services.calls, ['sharePdf:nobet-banu-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('herkesin kişiye özel PDF\'i tek seferde paylaşılır', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, 'Herkesin listesi (PDF)');
    expect(services.calls, ['shareFiles:3']);
    expect(services.sharedFiles.map((f) => f.name), {
      'nobet-ayse-2026-10.pdf',
      'nobet-banu-2026-10.pdf',
      'nobet-ali-2026-10.pdf',
    });
    for (final f in services.sharedFiles) {
      expect(f.mime, 'application/pdf');
      expect(isPdf(f.bytes), isTrue);
    }
  });

  testWidgets('ay kapanışı: adımlar sırayla yapılır ve hatırlanır', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayı kapat'));
    await tester.pumpAndSettle();

    // Kontrol: boş koltuklar var, sorulur.
    expect(find.textContaining('koltuk boş'), findsWidgets);
    expect(find.text('0 / 6 adım tamam'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-next')));
    await tester.pumpAndSettle();
    expect(find.text('Listede bakılacak şeyler var'), findsOneWidget);
    await tester.tap(find.text('Yine de devam'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 6 adım tamam'), findsOneWidget);

    // Kilit.
    await tester.tap(find.byKey(const ValueKey('close-next')));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.isLocked, isTrue);
    expect(find.text('Liste kilitli.'), findsOneWidget);

    // Fazla mesai raporu (sıra dışı, satırdan).
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('close-overtime')),
        matching: find.text('Yap'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['sharePdf:fazla-mesai-2026-10.pdf']);

    // Yedek.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('close-backup')),
        matching: find.text('Yap'),
      ),
    );
    await tester.pumpAndSettle();
    expect(services.calls.last, startsWith('shareFile:nobet-yedek-'));
    expect(find.text('4 / 6 adım tamam'), findsOneWidget);
    expect(find.text('Sıradaki: Herkese gönder'), findsOneWidget);
    expect(
      boxes.meta.get('monthClose/2026-10'),
      unorderedEquals(['check', 'lock', 'overtime', 'backup']),
    );
  });

  testWidgets('isme dokununca kişi vurgulanır ve özeti çıkar', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('highlight-summary')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('name-b')));
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('highlight-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(
        of: summary,
        matching: find.textContaining('1 nöbet · 0 hafta sonu · 0 gün aşırı'),
      ),
      findsOneWidget,
    );

    // Aynı isme yeniden dokununca vurgu kalkar.
    await tester.tap(find.byKey(const ValueKey('name-b')));
    await tester.pumpAndSettle();
    expect(summary, findsNothing);

    // Kapat düğmesiyle de kaldırılır.
    await tester.tap(find.byKey(const ValueKey('name-a')));
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);
    await tester.tap(find.byTooltip('Vurguyu kaldır'));
    await tester.pumpAndSettle();
    expect(summary, findsNothing);
  });
}
