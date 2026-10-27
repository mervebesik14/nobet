import '../models/roster_edit.dart';

/// Son oluşturmadan bu yana elle yapılanlar.
class ManualEdits {
  const ManualEdits({
    required this.count,
    required this.samples,
    required this.manualList,
  });

  /// Elle yapılmış değişiklik sayısı (geçmişteki ayrıntı satırları).
  final int count;

  /// Örnek satırlar, en yenisi önce ("3 Ekim: Ayşe yerine Hale").
  final List<String> samples;

  /// Liste uygulamada oluşturulmadı: elle girildi ya da Excel'den alındı.
  /// Yeniden oluşturulursa tamamı silinir.
  final bool manualList;

  bool get isEmpty => count == 0 && !manualList;

  static const _generated = {'Liste oluşturuldu', 'Liste yeniden oluşturuldu'};
  static const _manualLists = {
    "Liste Excel'den alındı",
    'Elle giriş için boş liste açıldı',
  };
  static const _manualEdits = {'Elle değişiklik', '7A değişikliği'};

  /// Ayın değişiklik geçmişinden ([history], eskiden yeniye): son
  /// "oluşturuldu" kaydından sonraki elle değişiklikler. "Geri al" geçmişi
  /// kısalttığı için geri alınanlar sayılmaz.
  static ManualEdits since(List<RosterEdit> history, {int sampleCount = 3}) {
    var start = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (_generated.contains(history[i].title)) {
        start = i + 1;
        break;
      }
    }
    var manualList = false;
    final lines = <String>[];
    for (final edit in history.skip(start)) {
      if (_manualLists.contains(edit.title)) {
        manualList = true;
        lines.clear(); // öncesi bu listeyle değişti
      } else if (edit.title == 'Liste sıfırlandı') {
        manualList = false;
        lines.clear();
      } else if (_manualEdits.contains(edit.title)) {
        lines.addAll(edit.lines);
      }
    }
    return ManualEdits(
      count: lines.length,
      samples: lines.reversed.take(sampleCount).toList(),
      manualList: manualList,
    );
  }
}
