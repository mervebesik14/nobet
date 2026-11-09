import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../holidays/holidays_page.dart';
import '../month/month_page.dart';
import '../people/people_page.dart';
import '../settings/settings_page.dart';
import '../statistics/statistics_page.dart';

/// Alt navigasyonda seçili sekmenin indeksi.
class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

/// Beş sekmeli ana iskelet: Kişiler, Ay Planı, Tatiller, İstatistik,
/// Ayarlar.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  static const _pages = <Widget>[
    PeoplePage(),
    MonthPage(),
    HolidaysPage(),
    StatisticsPage(),
    SettingsPage(),
  ];

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  // Sekme değişince içerik hafifçe yukarı kayarak belirir.
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _curve.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    ref.listen(selectedTabProvider, (prev, next) {
      if (prev != next) _fade.forward(from: 0);
    });

    return Scaffold(
      // IndexedStack: sekme değişince sayfaların durumu korunur.
      body: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(_curve),
          child: IndexedStack(index: index, children: MainShell._pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(selectedTabProvider.notifier).select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Kişiler',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Ay Planı',
          ),
          NavigationDestination(
            icon: Icon(Icons.celebration_outlined),
            selectedIcon: Icon(Icons.celebration),
            label: 'Tatiller',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'İstatistik',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}
