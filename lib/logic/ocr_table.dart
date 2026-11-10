import '../models/models.dart';
import 'turkish_collation.dart';

/// Metin tanımanın bulduğu bir metin kutusu. Koordinatlar sayfaya göre
/// 0–1 arası; [y] üstten. Çok sayfalı PDF'te sonraki sayfalar [y]'ye
/// sayfa sırası eklenerek verilir.
typedef OcrBox = ({String text, double x, double y, double w, double h});

/// Bir fotoğraf ya da PDF'teki nöbet tablosunu, metin kutularından satır
/// ve sütunlara çevirir (saf Dart). Çıktı Excel okuyucusuyla aynı
/// biçimdedir: ilk satır gün başlığı (1, 2, …), sonrakiler "Ad, gün
/// hücreleri"; [RosterImport.fromRows] doğrudan okur. Adlar, kişi
/// listesindekilere Türkçe harf farkı ve küçük okuma hatalarıyla
/// eşleştirilir.
class OcrTable {
  const OcrTable._();

  static List<List<Object?>> toRows(
    List<OcrBox> boxes, {
    Iterable<Person> people = const [],
    int? daysInMonth,
  }) {
    // 1) Sözcükler: kutudaki metin boşluklarla bölünür, her sözcüğe
    // kutunun genişliği harf sayısına göre paylaştırılır.
    final tokens = <_Token>[];
    for (final b in boxes) {
      final text = b.text.trim();
      if (text.isEmpty) continue;
      final parts = text.split(RegExp(r'\s+'));
      final total = text.length;
      var pos = 0;
      for (final part in parts) {
        final start = text.indexOf(part, pos);
        pos = start + part.length;
        final mid = (start + part.length / 2) / total;
        tokens.add(_Token(part, b.x + b.w * mid, b.y + b.h / 2, b.h));
      }
    }
    if (tokens.isEmpty) return const [];

    // 2) Satırlar: dikey merkezlere göre kümelenir.
    tokens.sort((a, b) => a.cy.compareTo(b.cy));
    final heights = [for (final t in tokens) t.h]..sort();
    final medianH = heights[heights.length ~/ 2];
    final rows = <List<_Token>>[];
    for (final t in tokens) {
      if (rows.isNotEmpty) {
        final row = rows.last;
        final meanY = row.fold(0.0, (s, x) => s + x.cy) / row.length;
        if ((t.cy - meanY).abs() < medianH * 0.6) {
          row.add(t);
          continue;
        }
      }
      rows.add([t]);
    }
    for (final r in rows) {
      r.sort((a, b) => a.cx.compareTo(b.cx));
    }

    // 3) Gün başlığı: 1'den başlayıp artan sayıların en uzun olduğu satır.
    var headerIndex = -1;
    var best = <int, double>{};
    for (var i = 0; i < rows.length; i++) {
      final found = <int, double>{};
      var next = 1;
      for (final t in rows[i]) {
        final n = int.tryParse(t.text.replaceAll(RegExp(r'[^0-9]'), ''));
        if (n == null || n < 1 || n > 31) continue;
        // Birkaç gün okunmamış olabilir: ileriye atlamaya izin ver.
        if (n >= next && n <= next + 3) {
          found[n] = t.cx;
          next = n + 1;
        }
      }
      if (found.length > best.length) {
        best = found;
        headerIndex = i;
      }
    }
    if (best.length < 7) return const [];

    // Gün → x: bulunan başlıklara doğru uydurulur (eksik/kayık günler).
    final xs = best.keys.map((d) => d.toDouble()).toList();
    final ys = best.values.toList();
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    final slope = den == 0 ? 0.0 : num / den;
    if (slope <= 0) return const [];
    final intercept = my - slope * mx;
    final maxDay = daysInMonth ?? best.keys.reduce((a, b) => a > b ? a : b);
    double colX(int day) => intercept + slope * day;
    final nameLimit = colX(1) - slope * 0.6;

    // 4) Kişi satırları.
    final out = <List<Object?>>[
      ['', for (var d = 1; d <= maxDay; d++) d],
    ];
    for (var i = headerIndex + 1; i < rows.length; i++) {
      final nameParts = <String>[];
      final cells = <int, String>{};
      for (final t in rows[i]) {
        if (t.cx < nameLimit) {
          nameParts.add(t.text);
          continue;
        }
        final day = ((t.cx - intercept) / slope).round();
        if (day < 1 || day > maxDay) continue;
        cells[day] = (cells[day] ?? '') + t.text;
      }
      if (nameParts.isEmpty) continue;
      final raw = nameParts.join(' ');
      // Başlığın tekrarı (2. sayfa) ya da gün adları satırı atlanır.
      if (int.tryParse(raw) != null) continue;
      final name = matchName(raw, people) ?? raw;
      out.add([name, for (var d = 1; d <= maxDay; d++) cells[d] ?? '']);
    }
    return out;
  }

  /// Okunan adı kişi listesindeki ada eşler: Türkçe harfler sadeleştirilir,
  /// birebir, ön ek ya da en fazla birkaç harf farkıyla. Bulunamazsa null.
  static String? matchName(String raw, Iterable<Person> people) {
    final key = _plain(raw);
    if (key.isEmpty) return null;
    String? bestName;
    var bestScore = 1 << 30;
    for (final p in people) {
      final full = _plain(p.name);
      final score = full == key
          ? 0
          : full.startsWith(key) || key.startsWith(full)
          ? 1
          : _distance(full, key) + 1;
      if (score < bestScore) {
        bestScore = score;
        bestName = p.name;
      }
    }
    // Uzun adlarda biraz daha fazla hata kabul edilir.
    final allowed = 1 + (key.length / 4).floor();
    return bestScore <= allowed ? bestName : null;
  }

  static String _plain(String s) => turkishLowerCase(s)
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

class _Token {
  _Token(this.text, this.cx, this.cy, this.h);

  final String text;
  final double cx;
  final double cy;
  final double h;
}
