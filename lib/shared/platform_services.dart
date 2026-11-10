import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/ocr_table.dart';

/// Telefonun paylaş / yazdır / dosya seç işlemleri. Ekranlar bunları bu
/// servis üzerinden çağırır; testlerde sahte bir sürümle değiştirilir.
class PlatformServices {
  const PlatformServices();

  /// PDF'i paylaşım menüsüyle gönderir (WhatsApp, e-posta, Drive...).
  Future<void> sharePdf(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  /// PDF'i yazdırma ekranında açar.
  Future<void> printPdf(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  /// PDF'in ilk sayfasını PNG görsele çevirir.
  Future<Uint8List> pdfToPng(Uint8List pdf, {double dpi = 200}) async {
    final page = await Printing.raster(pdf, pages: const [0], dpi: dpi).first;
    return page.toPng();
  }

  /// PDF'in bütün sayfalarını önizleme için PNG görsellere çevirir
  /// (piksel boyutlarıyla: görsel çözülmeden yer ayrılsın).
  Future<List<({Uint8List png, int width, int height})>> pdfPages(
    Uint8List pdf, {
    double dpi = 110,
  }) async => [
    await for (final page in Printing.raster(pdf, dpi: dpi))
      (png: await page.toPng(), width: page.width, height: page.height),
  ];

  /// Herhangi bir dosyayı paylaşım menüsüyle gönderir.
  Future<void> shareFile(Uint8List bytes, String filename, String mimeType) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
          fileNameOverrides: [filename],
        ),
      );

  /// Birden çok dosyayı tek paylaşım menüsüyle gönderir (ör. herkesin
  /// kişiye özel PDF'i).
  Future<void> shareFiles(
    List<({Uint8List bytes, String name, String mime})> files, {
    String? subject,
  }) => SharePlus.instance.share(
    ShareParams(
      files: [
        for (final f in files)
          XFile.fromData(f.bytes, mimeType: f.mime, name: f.name),
      ],
      fileNameOverrides: [for (final f in files) f.name],
      subject: subject,
    ),
  );

  /// Metni paylaşım menüsüyle gönderir (WhatsApp, mesaj vb.).
  Future<void> shareText(String text, {String? subject}) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  /// Kullanıcıya bir JSON dosyası seçtirir; vazgeçerse boş döner.
  Future<Uint8List?> pickJsonFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return file?.xFile.readAsBytes();
  }

  /// Kullanıcıya bir Excel (.xlsx) dosyası seçtirir; vazgeçerse boş döner.
  Future<Uint8List?> pickExcelFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    return file?.xFile.readAsBytes();
  }

  /// Liste fotoğrafı ya da PDF'i seçtirir: [photos] true ise Fotoğraflar,
  /// değilse Dosyalar. Vazgeçerse boş döner.
  Future<({Uint8List bytes, bool isPdf})?> pickScanFile({
    required bool photos,
  }) async {
    final file = await FilePicker.pickFile(
      type: photos ? FileType.image : FileType.custom,
      allowedExtensions: photos
          ? null
          : const ['pdf', 'jpg', 'jpeg', 'png', 'heic'],
    );
    if (file == null) return null;
    return (
      bytes: await file.xFile.readAsBytes(),
      isPdf: file.name.toLowerCase().endsWith('.pdf'),
    );
  }

  static const _ocr = MethodChannel('nobetci/ocr');

  /// Görseldeki metni cihaz üstünde okur (iPhone: Apple Vision,
  /// internetsiz). Kutular sayfaya göre 0–1 arası, y üstten.
  Future<List<OcrBox>> recognizeText(Uint8List image) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Fotoğraftan okuma şimdilik yalnız iPhone\'da.');
    }
    final list =
        await _ocr.invokeListMethod<Map<Object?, Object?>>('recognize', {
          'image': image,
        }) ??
        const [];
    return [
      for (final m in list)
        (
          text: m['text'] as String? ?? '',
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          w: (m['w'] as num).toDouble(),
          h: (m['h'] as num).toDouble(),
        ),
    ];
  }

  /// Telefon rehberinden bir numara seçtirir (izin istemez); vazgeçerse
  /// boş döner.
  Future<({String? name, String phone})?> pickContactPhone() async {
    final contact = await FlutterNativeContactPicker().selectPhoneNumber();
    final phone =
        contact?.selectedPhoneNumber ?? contact?.phoneNumbers?.firstOrNull;
    if (phone == null || phone.trim().isEmpty) return null;
    return (name: contact?.fullName, phone: phone);
  }

  /// Bağlantıyı başka uygulamada açar (WhatsApp); açılamadıysa false.
  Future<bool> openUrl(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  /// PDF'e gömülen Türkçe destekli fontlar.
  Future<({pw.Font regular, pw.Font bold})> loadPdfFonts() async => (
    regular: pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    ),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
  );
}

final platformServicesProvider = Provider<PlatformServices>(
  (ref) => const PlatformServices(),
);
