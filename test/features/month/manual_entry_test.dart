import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/data/roster_history_repository.dart';
import 'package:nobet_listesi/features/month/month_page.dart';
import 'package:nobet_listesi/logic/roster_excel.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

const _team = [
  Person(id: 'n1', name: 'Ayşe', role: Role.nurse),
  Person(id: 'n2', name: 'Banu', role: Role.nurse),
  Person(id: 'n3', name: 'Cemile', role: Role.nurse),
  Person(id: 't1', name: 'Ali', role: Role.radiologyTech),
  Person(id: 't2', name: 'Burak', role: Role.radiologyTech),
];

/// Dışarıda hazırlanmış Ekim listesi: her gün iki hemşire + bir tekniker.
Map<int, DayAssignment> _outside() => {
  for (var d = 1; d <= 31; d++)
    d: DayAssignment(
      day: d,
      nurseIds: [
        ['n1', 'n2'],
        ['n2', 'n3'],
        ['n3', 'n1'],
      ][d % 3],
      techId: d.isOdd ? 't1' : 't2',
    ),
};

/// Uygulamanın "Excel olarak paylaş" ile verdiği biçimde dosya.
List<int> _excel(Map<int, DayAssignment> assignments, {List<Person>? people}) {
  final plan = MonthPlan(
    year: 2026,
    month: 10,
    assignments: assignments,
    annualLeave: const {
      'n3': [21],
    },
  );
  final team = people ?? _team;
  return RosterExcel.build(
    plan: plan,
    rows: [for (final p in team) (id: p.id, name: p.name, role: p.role)],
    summary: RosterSummary.build(
      year: 2026,
      month: 10,
      assignments: assignments,
      people: team,
      holidays: const [],
      settings: const RosterSettings(),
    ),
    weekendDays: const {},
    holidayDays: const {},
    shiftHours: 24,
  );
}

void main() {
  late HiveBoxes boxes;
  late FakePlatformServices services;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    services = FakePlatformServices();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    for (final p in _team) {
      await boxes.people.put(p.id, p);
    }
    // Yedek kartı karışmasın.
    await boxes.meta.put(
      'lastBackupAt',
      DateTime(2026, 10, 10).toIso8601String(),
    );
  });

  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
        ],
        child: const MaterialApp(home: MonthPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String option) async {
    await tester.tap(find.text('Listeyi elle gir'));
    await tester.pumpAndSettle();
    expect(find.text('Ekim listesini elle gir'), findsOneWidget);
    await tester.tap(find.text(option));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  MonthPlan saved() => boxes.monthPlans.get('2026-10')!;

  testWidgets('boş listeyle başla: tabloya dokunarak nöbet yazılır', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 'Boş listeyle başla');
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    expect(saved().assignments, hasLength(31));
    expect(
      saved().assignments.values.every((a) => a.personIds.isEmpty),
      isTrue,
    );
    expect(saved().nurseOnly, isFalse);
    // Liste ekranı açıldı; boş hücreye dokununca nöbet yazılır.
    expect(find.text('Ekim 2026 Nöbet Listesi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cell-n1-1')));
    await tester.pumpAndSettle();
    expect(saved().assignments[1]!.nurseIds, ['n1']);
  });

  testWidgets("Excel'den al: önizleme, onay ve kayıt", (tester) async {
    services.pickedExcel = Uint8List.fromList(_excel(_outside()));
    await pump(tester);
    await open(tester, "Excel'den al");

    expect(find.text("Ekim listesi Excel'den alınsın mı?"), findsOneWidget);
    expect(find.textContaining('93 nöbet, 5 kişi okundu.'), findsOneWidget);
    expect(
      find.textContaining('1 izin günü mevcut izinlere eklenecek.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    final plan = saved();
    for (final e in _outside().entries) {
      expect(
        plan.assignments[e.key]!.nurseIds.toSet(),
        e.value.nurseIds.toSet(),
      );
      expect(plan.assignments[e.key]!.techId, e.value.techId);
    }
    expect(plan.annualLeave, {
      'n3': [21],
    });
    expect(plan.nurseOnly, isFalse);
    expect(
      RosterHistoryRepository(boxes.history).load(2026, 10).last.title,
      "Liste Excel'den alındı",
    );
    // Liste ekranı açıldı.
    expect(find.text('Ekim 2026 Nöbet Listesi'), findsOneWidget);
  });

  testWidgets('mevcut listenin üstüne yazmadan önce sorar; uyarılar görünür', (
    tester,
  ) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(year: 2026, month: 10, assignments: _outside()),
    );
    // Dosyada tanınmayan bir kişi var.
    services.pickedExcel = Uint8List.fromList(
      _excel(
        {
          1: const DayAssignment(day: 1, nurseIds: ['n1', 'x']),
        },
        people: [
          ..._team,
          const Person(id: 'x', name: 'Zehra', role: Role.nurse),
        ],
      ),
    );
    await pump(tester);
    await open(tester, "Excel'den al");
    expect(find.textContaining('"Zehra" kişiler arasında yok'), findsOneWidget);
    expect(find.textContaining('yalnız hemşire listesi'), findsOneWidget);
    expect(
      find.textContaining('mevcut listesi değiştirilecek'),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().assignments[1]!.nurseIds, _outside()[1]!.nurseIds);
  });

  testWidgets('Excel olmayan dosya: açıklama, liste değişmez', (tester) async {
    services.pickedExcel = Uint8List.fromList(utf8.encode('merhaba'));
    await pump(tester);
    await open(tester, "Excel'den al");
    expect(find.text('Dosya bir Excel (.xlsx) dosyası değil.'), findsOneWidget);
    expect(saved().hasRoster, isFalse);
  });

  testWidgets('Excel şablonu: kişiler ve günler, tek sayfa', (tester) async {
    await pump(tester);
    await open(tester, 'Excel şablonunu paylaş');
    expect(services.calls, ['shareFile:nobet-sablon-2026-10.xlsx']);
    final files = {
      for (final f in ZipDecoder().decodeBytes(
        services.sharedFiles.single.bytes,
      ))
        f.name: utf8.decode(f.content),
    };
    expect(files['xl/workbook.xml'], contains('name="Nöbet Listesi"'));
    expect(files['xl/workbook.xml'], isNot(contains('Mesai Özeti')));
    final sheet = files['xl/worksheets/sheet1.xml']!;
    for (final p in _team) {
      expect(sheet, contains('>${p.name}<'));
    }
    expect(sheet, isNot(contains('<v>24</v>')));
    expect(saved().hasRoster, isFalse);
  });

  testWidgets('boş liste: mevcut liste varsa onay ister', (tester) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(year: 2026, month: 10, assignments: _outside()),
    );
    await pump(tester);
    await open(tester, 'Boş listeyle başla');
    expect(find.text('Mevcut liste değiştirilsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().assignments[1]!.nurseIds, isNotEmpty);
  });

  testWidgets('kilitli ayda elle girilmez', (tester) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(year: 2026, month: 10, assignments: _outside(), isLocked: true),
    );
    await pump(tester);
    await tester.tap(find.text('Listeyi elle gir'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bu ay kilitli. Elle girmek için önce kilidi açın.'),
      findsOneWidget,
    );
    expect(find.text('Ekim listesini elle gir'), findsNothing);
  });
}
