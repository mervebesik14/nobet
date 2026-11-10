import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/logic/ocr_table.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/providers.dart';
import 'package:nobet_listesi/data/weekly_file_backup.dart';
import 'package:nobet_listesi/logic/roster_calendar.dart';
import 'package:nobet_listesi/shared/calendar_service.dart';
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
    // Haftalık dosya yedeği gerçek Belgeler klasörü yerine geçici klasöre.
    backupFolderProvider.overrideWithValue(
      BackupFolder(Directory.systemTemp.createTempSync('nobet_yedek')),
    ),
  ];
}

/// Paylaş / yazdır / dosya seç çağrılarını kaydeden sahte servis.
class FakePlatformServices extends PlatformServices {
  FakePlatformServices({this.pickedFile});

  /// pickJsonFile'ın döndüreceği dosya (boşsa kullanıcı vazgeçmiş sayılır).
  Uint8List? pickedFile;

  /// pickExcelFile'ın döndüreceği dosya (boşsa kullanıcı vazgeçmiş sayılır).
  Uint8List? pickedExcel;

  /// pickScanFile'ın döndüreceği dosya ve recognizeText'in bulacağı kutular
  /// (sayfa başına).
  ({Uint8List bytes, bool isPdf})? pickedScan;
  List<List<OcrBox>> scanPages = const [];

  @override
  Future<({Uint8List bytes, bool isPdf})?> pickScanFile({
    required bool photos,
  }) async {
    calls.add('pickScanFile:${photos ? 'photos' : 'files'}');
    return pickedScan;
  }

  var _ocrPage = 0;

  @override
  Future<List<OcrBox>> recognizeText(Uint8List image) async {
    calls.add('recognizeText');
    return _ocrPage < scanPages.length ? scanPages[_ocrPage++] : const [];
  }

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
  Future<List<({Uint8List png, int width, int height})>> pdfPages(
    Uint8List pdf, {
    double dpi = 110,
  }) async {
    calls.add('pdfPages');
    lastPdf = pdf;
    return [(png: _onePixelPng, width: 1, height: 1)];
  }

  // Geçerli 1×1 PNG: önizleme testlerinde Image.memory çözebilsin.
  static final _onePixelPng = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0xF0,
    0x1F,
    0x00,
    0x05,
    0x00,
    0x01,
    0xFF,
    0x89,
    0x99,
    0x3D,
    0x1D,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

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

  /// pickContactPhone'un döndüreceği kişi (boşsa vazgeçilmiş sayılır).
  ({String? name, String phone})? pickedContact;

  /// openUrl ile açılan bağlantılar.
  final openedUrls = <Uri>[];

  /// openUrl sonucu: false ise WhatsApp yüklü değil gibi davranır (yalnız
  /// whatsapp:// bağlantıları için).
  bool whatsAppInstalled = true;

  @override
  Future<({String? name, String phone})?> pickContactPhone() async {
    calls.add('pickContactPhone');
    return pickedContact;
  }

  @override
  Future<bool> openUrl(Uri uri) async {
    openedUrls.add(uri);
    return uri.scheme != 'whatsapp' || whatsAppInstalled;
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
    bool startedButton = true,
  }) async {
    scheduleCalls++;
    // Ay başı ve kendi nöbet hatırlatmaları ayrı tutulur.
    (startedButton ? scheduled : shiftScheduled)
      ..clear()
      ..addAll(items);
  }

  /// Son planlanan kendi nöbet hatırlatmaları.
  final shiftScheduled = <ScheduledNotification>[];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(body);
  }
}

/// Telefon takvimi yerine bellekte tutar.
class FakeCalendarService extends CalendarService {
  FakeCalendarService({this.access = CalendarAccess.full});

  CalendarAccess access;

  /// Takvimdeki etkinlikler: kimlik → etkinlik.
  final events = <String, CalendarEntry>{};
  var _next = 0;

  @override
  Future<CalendarAccess> requestAccess() async => access;

  @override
  Future<String> add(CalendarEntry e) async {
    final id = 'e${_next++}';
    events[id] = e;
    return id;
  }

  @override
  Future<void> delete(String id) async => events.remove(id);
}
