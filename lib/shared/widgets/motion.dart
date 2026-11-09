import 'package:flutter/material.dart';

/// Dokununca hafifçe küçülen, bırakınca yaylanarak eski boyuna dönen
/// dokunulabilir alan (hücreler, kartlar).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.9,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Basılıyken boyut oranı.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    onTapDown: (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Duration(milliseconds: _down ? 80 : 220),
      curve: _down ? Curves.easeOut : Curves.elasticOut,
      child: widget.child,
    ),
  );
}

/// Kaydetme bildirimlerindeki yeşil tik: küçükten yaylanarak büyür.
class SuccessTick extends StatelessWidget {
  const SuccessTick({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 450),
    curve: Curves.elasticOut,
    builder: (context, v, child) => Transform.scale(scale: v, child: child),
    child: Icon(
      Icons.check_circle_rounded,
      size: size,
      color: const Color(0xFF4CD9A0),
    ),
  );
}

/// Yeşil tikli bildirim içeriği.
class SuccessMessage extends StatelessWidget {
  const SuccessMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SuccessTick(),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ],
  );
}

/// Liste oluşturulurken: nabız gibi atan simge ve sırayla değişen
/// "neler yapılıyor" yazıları.
class GeneratingDialog extends StatefulWidget {
  const GeneratingDialog({super.key});

  static const steps = [
    'Liste oluşturuluyor…',
    'İstekler ve izinler okunuyor…',
    'Hafta sonları dengeleniyor…',
    'Gün aşırılar azaltılıyor…',
    'Tatiller adil dağıtılıyor…',
    'Son dokunuşlar…',
  ];

  @override
  State<GeneratingDialog> createState() => _GeneratingDialogState();
}

class _GeneratingDialogState extends State<GeneratingDialog>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      content: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final steps = GeneratingDialog.steps;
          final i = (_c.value * steps.length).floor() % steps.length;
          // Her adımda iki kez "nabız".
          final beat = (_c.value * steps.length * 2) % 1;
          final pulse = 1 + 0.12 * (1 - (beat * 2 - 1).abs());
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: scheme.primary,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    Transform.scale(
                      scale: pulse,
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        size: 38,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  steps[i],
                  key: ValueKey(i),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
