import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/backup_picker.dart';
import 'package:nobet_listesi/logic/block_reason.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 'd', name: 'Derya', role: Role.nurse),
    Person(id: 'e', name: 'Elif', role: Role.nurse),
    Person(id: 'f', name: 'Fatma', role: Role.nurse),
    Person(id: 's', name: 'Sorumlu', role: Role.nurse, isChargeNurse: true),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
  ];
  // Kasım 2026, 10. gün: Ayşe ve Fatma nöbette. Banu 9'da (art arda),
  // Cemile 6 ve 8'de (10 ile zincir 3), Elif istemedi; Derya 2 nöbetli.
  final plan = MonthPlan(
    year: 2026,
    month: 11,
    assignments: {
      1: const DayAssignment(day: 1, nurseIds: ['d']),
      3: const DayAssignment(day: 3, nurseIds: ['d']),
      6: const DayAssignment(day: 6, nurseIds: ['c']),
      8: const DayAssignment(day: 8, nurseIds: ['c']),
      9: const DayAssignment(day: 9, nurseIds: ['b']),
      10: const DayAssignment(day: 10, nurseIds: ['a', 'f'], techId: 't'),
    },
  );

  test('kurala uyan, az nöbetli yedekler', () {
    final c = BackupPicker.candidates(
      plan: plan,
      people: people,
      day: 10,
      role: Role.nurse,
      settings: const RosterSettings(),
      blockReasons: const {
        'e': {10: BlockReason.unavailable},
      },
    );
    expect([for (final p in c) p.id], ['d']);

    // 20'si için: hepsi uygun; en az nöbetli önce (Elif 0, ...).
    final c20 = BackupPicker.candidates(
      plan: plan,
      people: people,
      day: 20,
      role: Role.nurse,
      settings: const RosterSettings(),
    );
    expect([for (final p in c20) p.id], ['e', 'a']);

    // Gelemeyene iyilik borcu olan önce.
    final owed = BackupPicker.candidates(
      plan: plan,
      people: people,
      day: 20,
      role: Role.nurse,
      settings: const RosterSettings(),
      debts: const {'b': 1},
    );
    expect([for (final p in owed) p.id], ['b', 'e']);
  });

  test('mesaj', () {
    expect(
      BackupPicker.message(
        plan: plan,
        day: 10,
        backupName: 'Derya',
        absentName: 'Ayşe',
      ),
      'Merhaba Derya, 10 Kasım Salı günü Ayşe gelemiyor; yerine 24 nöbeti '
      'senin. Uygun değilsen lütfen hemen haber ver.',
    );
  });
}
