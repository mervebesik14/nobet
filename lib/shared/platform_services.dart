import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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
