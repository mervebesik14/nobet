import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Listeyi tam ekranda gösterir: telefon yatay çevrilir, durum çubuğu
/// gizlenir ve tablonun tamamı ekrana sığdırılır (kaydırmak gerekmez).
/// İki parmakla yakınlaştırılır, "Ekrana sığdır" ile ilk hâline döner.
/// İsme dokunmak kişiyi vurgular; düzenleme ana liste ekranında yapılır.
class RosterFullscreenPage extends StatefulWidget {
  const RosterFullscreenPage({
    super.key,
    required this.title,
    required this.contentSize,
    required this.tableBuilder,
    this.initialHighlightId,
    this.rotate = true,
  });

  final String title;

  /// Tablonun kaydırmasız tam boyu ([RosterTable.contentSize]).
  final Size contentSize;

  /// Tablo sliver'ını kurar; vurgulanan kişi ve isme dokunma verilir.
  final Widget Function(String? highlightId, ValueChanged<String> onNameTap)
  tableBuilder;

  final String? initialHighlightId;

  /// Açılınca yataya çevrilsin mi (testlerde kapatılır).
  final bool rotate;

  @override
  State<RosterFullscreenPage> createState() => _RosterFullscreenPageState();
}

class _RosterFullscreenPageState extends State<RosterFullscreenPage> {
  final _zoom = TransformationController();
  late String? _highlightId = widget.initialHighlightId;

  @override
  void initState() {
    super.initState();
    if (widget.rotate) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (widget.rotate) {
      // Boş liste: uygulamanın kendi ayarındaki yönlere döner.
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = widget.contentSize;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'İki parmakla yakınlaştır',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('fullscreen-fit'),
                    tooltip: 'Ekrana sığdır',
                    onPressed: () => _zoom.value = Matrix4.identity(),
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                  TextButton.icon(
                    key: const ValueKey('fullscreen-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.fullscreen_exit),
                    label: const Text('Kapat'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                key: const ValueKey('fullscreen-viewer'),
                transformationController: _zoom,
                maxScale: 5,
                child: Center(
                  child: FittedBox(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: CustomScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        slivers: [
                          widget.tableBuilder(
                            _highlightId,
                            (id) => setState(
                              () =>
                                  _highlightId = _highlightId == id ? null : id,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
