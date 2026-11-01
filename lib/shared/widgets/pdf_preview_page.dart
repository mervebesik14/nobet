import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform_services.dart';

/// PDF'i paylaşmadan önce sayfa sayfa gösterir; iki parmakla
/// yakınlaştırılır. "Paylaş" ile paylaşım menüsü açılır.
class PdfPreviewPage extends ConsumerStatefulWidget {
  const PdfPreviewPage({
    super.key,
    required this.title,
    required this.pdf,
    required this.fileName,
  });

  final String title;
  final Uint8List pdf;
  final String fileName;

  @override
  ConsumerState<PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends ConsumerState<PdfPreviewPage> {
  late final Future<List<({Uint8List png, int width, int height})>> _pages = ref
      .read(platformServicesProvider)
      .pdfPages(widget.pdf);

  Future<void> _share() async {
    try {
      await ref
          .read(platformServicesProvider)
          .sharePdf(widget.pdf, widget.fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Paylaş',
          icon: const Icon(Icons.share),
          onPressed: _share,
        ),
      ],
    ),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    body: FutureBuilder<List<({Uint8List png, int width, int height})>>(
      future: _pages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Önizleme açılamadı: ${snapshot.error}'));
        }
        final pages = snapshot.data;
        if (pages == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return InteractiveViewer(
          maxScale: 4,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              for (final (i, page) in pages.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                Material(
                  elevation: 2,
                  color: Colors.white,
                  // Görsel çözülene kadar da sayfa yer kaplasın.
                  child: AspectRatio(
                    aspectRatio: page.width / page.height,
                    child: Image.memory(
                      page.png,
                      key: ValueKey('pdf-page-$i'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: _share,
      icon: const Icon(Icons.send),
      label: const Text('Paylaş'),
    ),
  );
}
