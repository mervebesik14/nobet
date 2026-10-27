import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/manual_edits.dart';
import 'package:nobet_listesi/models/models.dart';

RosterEdit edit(String title, [List<String> lines = const []]) =>
    RosterEdit(at: DateTime(2026, 10, 1), title: title, lines: lines);

void main() {
  test('son oluşturmadan sonraki elle değişiklikler sayılır', () {
    final m = ManualEdits.since([
      edit('Elle değişiklik', ['eski']),
      edit('Liste yeniden oluşturuldu'),
      edit('Elle değişiklik', ['3 Ekim: Ayşe yerine Hale']),
      edit('Kurallara göre düzeltildi', ['otomatik']),
      edit('7A değişikliği', ['7A 5 Ekim: silindi', '7A 6 Ekim: Ali yazıldı']),
    ]);
    expect(m.count, 3);
    expect(m.samples, [
      '7A 6 Ekim: Ali yazıldı',
      '7A 5 Ekim: silindi',
      '3 Ekim: Ayşe yerine Hale',
    ]);
    expect(m.manualList, isFalse);
    expect(m.isEmpty, isFalse);
  });

  test('elle değişiklik yoksa boş', () {
    expect(ManualEdits.since([edit('Liste oluşturuldu')]).isEmpty, isTrue);
    expect(ManualEdits.since(const []).isEmpty, isTrue);
  });

  test("Excel'den alınan ya da elle girilen liste", () {
    final m = ManualEdits.since([
      edit('Liste oluşturuldu'),
      edit('Elle değişiklik', ['önceki listede']),
      edit("Liste Excel'den alındı"),
      edit('Elle değişiklik', ['4 Ekim: Banu çıkarıldı']),
    ]);
    expect(m.manualList, isTrue);
    expect(m.count, 1);
    expect(
      ManualEdits.since([edit('Elle giriş için boş liste açıldı')]).manualList,
      isTrue,
    );
    // Sıfırlanınca elle liste de kalmaz.
    expect(
      ManualEdits.since([
        edit("Liste Excel'den alındı"),
        edit('Liste sıfırlandı'),
      ]).isEmpty,
      isTrue,
    );
  });
}
