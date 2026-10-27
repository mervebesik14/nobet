import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/providers.dart';
import 'package:nobet_listesi/shared/notification_service.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:nobet_listesi/shared/providers.dart';
import 'package:pdf/widgets.dart' as pw;

/// Diske yazmayan Hive kutuları açar; her test temiz başlar.
Future<HiveBoxes> openTestBoxes() async {
  await Hive.close();
  return HiveBoxes.open(inMemory: true);
}

/// Test kutularını kullanan provider override'ları.
/// Liste tohumu da sabitlenir: arayüz testleri her çalıştırmada aynı listeyi
/// üretir.
List<Override> boxOverrides(HiveBoxes boxes) {
  final rng = Random(1);
  return [
    hiveBoxesProvider.overrideWithValue(boxes),
    rosterSeedProvider.overrideWithValue(() => rng.nextInt(1 << 31)),
  ];
}

/// Paylaş / yazdır / dosya seç çağrılarını kaydeden sahte servis.
class FakePlatformServices extends PlatformServices {
  FakePlatformServices({this.pickedFile});

  /// pickJsonFile'ın döndüreceği dosya (boşsa kullanıcı vazgeçmiş sayılır).
  Uint8List? pickedFile;

  /// pickExcelFile'ın döndüreceği dosya (boşsa kullanıcı vazgeçmiş sayılır).
  Uint8List? pickedExcel;

  final calls = <String>[];
  final sharedFiles = <({String name, String mime, Uint8List bytes})>[];
  Uint8List? lastPdf;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {
    calls.add('sharePdf:$filename');
    lastPdf = bytes;
  }

  @override
  Future<void> printPdf(Uint8List bytes, String name) async {
    calls.add('printPdf:$name');
    lastPdf = bytes;
  }

  @override
  Future<Uint8List> pdfToPng(Uint8List pdf, {double dpi = 200}) async {
    calls.add('pdfToPng');
    lastPdf = pdf;
    return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
  }

  @override
  Future<void> shareFile(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    calls.add('shareFile:$filename');
    sharedFiles.add((name: filename, mime: mimeType, bytes: bytes));
  }

  @override
  Future<void> shareFiles(
    List<({Uint8List bytes, String name, String mime})> files, {
    String? subject,
  }) async {
    calls.add('shareFiles:${files.length}');
    for (final f in files) {
      sharedFiles.add((name: f.name, mime: f.mime, bytes: f.bytes));
    }
  }

  /// Paylaşılan metinler.
  final sharedTexts = <String>[];

  @override
  Future<void> shareText(String text, {String? subject}) async {
    calls.add('shareText');
    sharedTexts.add(text);
  }

  @override
  Future<Uint8List?> pickJsonFile() async {
    calls.add('pickJsonFile');
    return pickedFile;
  }

  @override
  Future<Uint8List?> pickExcelFile() async {
    calls.add('pickExcelFile');
    return pickedExcel;
  }

  @override
  Future<({pw.Font regular, pw.Font bold})> loadPdfFonts() async {
    pw.Font load(String file) => pw.Font.ttf(
      File('assets/fonts/$file').readAsBytesSync().buffer.asByteData(),
    );
    return (regular: load('Roboto-Regular.ttf'), bold: load('Roboto-Bold.ttf'));
  }
}

/// Bildirimleri telefona göndermeyip kaydeden sahte servis.
class FakeNotificationService extends NotificationService {
  /// Son planlanan bildirimler.
  final scheduled = <ScheduledNotification>[];

  /// Hemen gösterilen bildirimlerin metinleri.
  final shown = <String>[];
  var permissionRequests = 0;
  var scheduleCalls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(
    List<ScheduledNotification> items, {
    required Iterable<int> ids,
  }) async {
    scheduleCalls++;
    scheduled
      ..clear()
      ..addAll(items);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(body);
  }
}
