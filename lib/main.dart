// 앱 진입점. 파일 경로와 오디오 엔진을 올린 뒤 화면을 띄움.
// 두 초기화는 화면보다 먼저 끝나야 해서 runApp 전에 기다림.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/db/database.dart';
import 'core/providers.dart';
import 'core/storage/paths.dart';
import 'library/library_page.dart';
import 'library/library_repo.dart';
import 'metronome/audio_service.dart';
import 'metronome/metronome_page.dart';
import 'settings/settings_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 임포트가 위젯보다 먼저 PdfDocument를 열기 때문에 엔진을 여기서 올려야 함.
  // 빠뜨리면 앱을 켜고 바로 악보를 열었을 때 뷰어가 빈 화면으로 남음
  pdfrxFlutterInitialize();
  await AppPaths.init();
  final audio = AudioService();
  await audio.init();

  final container = ProviderContainer(overrides: [audioProvider.overrideWithValue(audio)]);
  // 보관 기간이 지난 휴지통 항목을 지움. 첫 화면을 막지 않도록 기다리지 않음
  unawaited(_purgeExpiredTrash(container.read(dbProvider)));

  runApp(UncontrolledProviderScope(container: container, child: const BatonApp()));
}

/// 보관 기간이 지난 휴지통 항목과 그 파일을 지움. 실패해도 앱 시작을 막지 않음.
Future<void> _purgeExpiredTrash(BatonDatabase db) async {
  try {
    await LibraryRepo(db).purgeExpired();
  } catch (e) {
    debugPrint('휴지통 자동 정리 실패: $e');
  }
}

class BatonApp extends StatelessWidget {
  const BatonApp({super.key});

  /// 밝은 연습실과 어두운 무대를 모두 쓰므로 시스템 테마를 따라감.
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Baton',
    debugShowCheckedModeBanner: false,
    theme: batonTheme(Brightness.light),
    darkTheme: batonTheme(Brightness.dark),
    home: const HomeShell(),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// 탭을 바꿔도 각 화면 상태가 살아 있도록 IndexedStack으로 둠.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        const LibraryPage(),
        MetronomePage(active: _tab == 1),
        const SettingsPage(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music),
          label: '악보',
        ),
        NavigationDestination(
          icon: Icon(Icons.av_timer_outlined),
          selectedIcon: Icon(Icons.av_timer),
          label: '메트로놈',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '설정',
        ),
      ],
    ),
  );
}
