import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/providers.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Diske yazmayan Hive kutuları açar; her test temiz başlar.
Future<HiveBoxes> openTestBoxes() async {
  await Hive.close();
  return HiveBoxes.open(inMemory: true);
}

/// Test kutularını kullanan provider override'ları.
List<Override> boxOverrides(HiveBoxes boxes) => [
  hiveBoxesProvider.overrideWithValue(boxes),
];

/// Paylaş / yazdır / dosya seç çağrılarını kaydeden sahte servis.
class FakePlatformServices extends PlatformServices {
  FakePlatformServices({this.pickedFile});

  /// pickJsonFile'ın döndüreceği dosya (boşsa kullanıcı vazgeçmiş sayılır).
  Uint8List? pickedFile;

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
  Future<({pw.Font regular, pw.Font bold})> loadPdfFonts() async {
    pw.Font load(String file) => pw.Font.ttf(
      File('assets/fonts/$file').readAsBytesSync().buffer.asByteData(),
    );
    return (regular: load('Roboto-Regular.ttf'), bold: load('Roboto-Bold.ttf'));
  }
}
