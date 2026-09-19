// 앱 루트 배너 칸의 배치 규칙. 동의 전에는 광고 요청이 없고, 칸이 생긴 만큼 본문이 줄며,
// 뷰어에서는 칸이 빠지고 대화상자 동안은 덮이되 화면 스택과 광고가 유지되는지를 고정함.

import 'dart:async';

import 'package:baton/ads/ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// 플러그인 채널을 가로챌 공개 API가 없음
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';

/// 배너를 내리는 화면 대역. ReaderPage와 같은 수명 지점에서 suppress·release를 부름.
class _Reader extends StatefulWidget {
  const _Reader();

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  /// 열리자마자 배너를 내림.
  @override
  void initState() {
    super.initState();
    Ads.suppress();
  }

  /// 닫히면 배너를 되돌림.
  @override
  void dispose() {
    Ads.release();
    super.dispose();
  }

  /// 내용은 검증에 쓰지 않음.
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('reader'));
}

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      instanceManager.channel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
  });

  testWidgets('동의 전 무요청, 칸 예약, 뷰어에서 칸 제거와 스택 유지, 키보드 인셋 보정', (tester) async {
    // 칸 높이: 구분 띠 8 + 고정 배너 50. 테스트 화면은 800x600
    const slot = 58.0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => AdFrame(child: child!),
        navigatorObservers: [Ads.modalObserver],
        home: const Scaffold(body: Text('home')),
      ),
    );
    expect(find.byType(BannerSlot), findsNothing);

    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('folder'))),
      ),
    );
    await tester.pumpAndSettle();

    Ads.ready.value = true;
    await tester.pump();
    // 첫 요청은 0초 타이머로 나감. 시간을 흘려야 발화함
    await tester.pump(Duration.zero);
    expect(tester.getSize(find.byType(BannerSlot)).height, slot);
    expect(tester.getSize(find.byType(Navigator)).height, 600 - slot);
    expect(calls, contains('loadBannerAd'));

    // 뷰어가 열리면 칸이 빠지고 화면 전체를 씀
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _Reader())));
    await tester.pumpAndSettle();
    expect(find.byType(BannerSlot), findsNothing);
    expect(tester.getSize(find.byType(Navigator)).height, 600);

    // 닫으면 칸이 돌아오고, 칸을 넣고 빼는 동안 Navigator가 새로 만들어지지 않아 폴더 화면이 남음
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BannerSlot), findsOneWidget);
    expect(find.text('folder'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();

    // 대화상자 동안 배너를 배경막으로 덮고, 닫으면 걷음. 칸은 그대로라 광고를 다시 받지 않음
    // 대화상자 자체의 배경막도 black54라 탭을 흡수하는 배너 덮개만 고름
    final cover = find.byWidgetPredicate(
      (w) =>
          w is AbsorbPointer &&
          w.child is ColoredBox &&
          (w.child! as ColoredBox).color == Colors.black54,
    );
    final slotState = tester.state(find.byType(BannerSlot));
    unawaited(showDialog<void>(context: nav.currentContext!, builder: (_) => const Text('dialog')));
    await tester.pumpAndSettle();
    expect(cover, findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
    expect(tester.state(find.byType(BannerSlot)), same(slotState));

    // 키보드 인셋에서 칸 높이를 덜어야 본문이 키보드 위에 정확히 붙음
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await tester.pump();
    // Scaffold는 본문에서 인셋을 지우므로 AdFrame이 넘긴 값은 Navigator에서 읽음
    final inner = MediaQuery.of(tester.element(find.byType(Navigator)));
    expect(inner.viewInsets.bottom, closeTo(300 - slot, 0.01));
    tester.view.resetViewInsets();

    // 칸을 없애 예약된 재요청 타이머를 끊음
    Ads.ready.value = false;
    await tester.pumpAndSettle();
  });
}
