import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/file_names.dart';

void main() {
  test('Türkçe harfler ASCII, boşluk ve işaretler tire', () {
    expect(fileSlug('Merve Beşik'), 'merve-besik');
    expect(fileSlug('IŞIL Çağlar-Öztürk'), 'isil-caglar-ozturk');
    expect(fileSlug('  Ali  (Yedek) '), 'ali-yedek');
    expect(fileSlug('***'), 'kisi');
  });
}
