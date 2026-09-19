// 앱 진입점. 파일 경로와 오디오 엔진을 올린 뒤 화면을 띄움.
// 두 초기화는 화면보다 먼저 끝나야 해서 runApp 전에 기다림.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'ads/ads.dart';
import 'core/db/database.dart';
import 'core/providers.dart';
import 'core/storage/backup.dart';
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
  // DB를 열기 전에 끝내야 함. 되살리기 교체 도중 죽었다면 원래 라이브러리로 돌려놓음
  await _recoverRestore();
  final audio = AudioService();
  await audio.init();

  final container = ProviderContainer(overrides: [audioProvider.overrideWithValue(audio)]);
  // 보관 기간이 지난 휴지통 항목을 지움. 첫 화면을 막지 않도록 기다리지 않음
  unawaited(_purgeExpiredTrash(container.read(dbProvider)));

  runApp(UncontrolledProviderScope(container: container, child: const BatonApp()));
  // 동의 폼은 첫 화면 위에 떠야 하므로 runApp 뒤에 시작함. 기다리지 않음
  Ads.start();
}

/// 끝나지 않은 백업 되살리기를 되돌림. 실패해도 앱 시작을 막지 않고 표시가 남아 다음 시작에서 다시 함.
Future<void> _recoverRestore() async {
  try {
    await recoverInterruptedRestore();
  } catch (e) {
    debugPrint('되살리기 복구 실패: $e');
  }
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
    restorationScopeId: 'baton',
    debugShowCheckedModeBanner: false,
    theme: batonTheme(Brightness.light),
    darkTheme: batonTheme(Brightness.dark),
    // 한국어 전용. 지원 언어가 하나라 기기 언어가 무엇이든 기본 문구가 한국어로 떨어짐
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('ko')],
    // 배너 칸을 Navigator 밖에 하나만 둠. 화면을 오가도 다시 요청하지 않고 전체 화면 push에서도 남음
    builder: (context, child) => AdFrame(child: child!),
    navigatorObservers: [Ads.modalObserver],
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
  /// 다른 탭에서 뒤로가기는 앱을 닫지 않고 악보 탭으로 돌아감.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: IndexedStack(
        index: _tab,
        children: [
          LibraryPage(active: _tab == 0),
          MetronomePage(active: _tab == 1),
          const SettingsPage(),
        ],
      ),
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
