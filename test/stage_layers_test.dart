// 악보 위 입력·표시 층. 넘김 탭이 뷰어의 더블탭 판정을 기다리지 않는지, 스타일러스 전용일 때 손가락이
// 뷰어까지 가는지, 반전을 꺼 두면 합성 레이어가 없는지, 필압이 기기와 무관하게 0~1인지를 고정함.

import 'package:baton/reader/stage_layers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면 전체를 덮는 획 오버레이 흉내. hitTest를 두지 않아 CustomPaint가 어디서나 히트됨.
class _FullPainter extends CustomPainter {
  /// 아무것도 그리지 않음. 히트 판정만 확인함.
  @override
  void paint(Canvas canvas, Size size) {}

  /// 그릴 것이 없어 다시 그리지 않음.
  @override
  bool shouldRepaint(_FullPainter old) => false;
}

/// 몇 번 만들어졌는지 세는 자식. 상태가 유지되는지 확인함.
class _Probe extends StatefulWidget {
  /// 상태를 새로 만들 때마다 created를 올리는 자식을 만듦.
  const _Probe();

  static int created = 0;

  /// 셈을 올리는 상태를 만듦.
  @override
  State<_Probe> createState() => _ProbeState();
}

/// 만들어질 때마다 _Probe.created를 올리는 상태.
class _ProbeState extends State<_Probe> {
  /// 만들어진 횟수를 하나 올림.
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  /// 부모 크기를 채우는 빈 상자.
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  /// 400×800 화면에 뷰어 흉내(탭·더블탭·드래그를 받는 층)와 넘김 칸을 겹쳐 둠.
  Future<void> pumpZones(
    WidgetTester tester, {
    required List<int> steps,
    required List<String> events,
    bool turns = true,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => events.add('viewer-tap'),
              onDoubleTap: () => events.add('viewer-double'),
              onPanStart: (_) => events.add('viewer-pan'),
            ),
            TapZones(onCenter: () => events.add('center'), onStep: steps.add, turns: turns),
          ],
        ),
      ),
    );
  }

  testWidgets('다음 칸을 빠르게 두 번 치면 기다리지 않고 두 번 넘김', (tester) async {
    final steps = <int>[];
    await pumpZones(tester, steps: steps, events: []);
    await tester.tapAt(const Offset(380, 400));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(380, 400));
    await tester.pump(const Duration(milliseconds: 10));
    expect(steps, [1, 1]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('끌면 넘기지 않고 드래그는 뷰어가 받음', (tester) async {
    final steps = <int>[];
    final events = <String>[];
    await pumpZones(tester, steps: steps, events: events);
    final g = await tester.startGesture(const Offset(380, 400));
    await g.moveBy(const Offset(0, -120));
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    expect(steps, isEmpty);
    expect(events, contains('viewer-pan'));
  });

  testWidgets('두 손가락이 닿으면 넘기지 않음', (tester) async {
    final steps = <int>[];
    await pumpZones(tester, steps: steps, events: []);
    final a = await tester.startGesture(const Offset(20, 400), pointer: 1);
    final b = await tester.startGesture(const Offset(380, 400), pointer: 2);
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1));
    expect(steps, isEmpty);
  });

  testWidgets('손을 댄 채 넘김 층이 빠지면 뗄 때 아무것도 하지 않음', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final steps = <int>[];
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, on, _) =>
              on ? TapZones(onCenter: () {}, onStep: steps.add) : const SizedBox.expand(),
        ),
      ),
    );
    final g = await tester.startGesture(const Offset(380, 400));
    // 다른 손가락으로 그리기를 켜거나 화면을 닫은 경우. 떼는 이벤트는 이미 잡힌 경로로 옛 층에 옴
    shown.value = false;
    await tester.pump();
    await g.up();
    expect(tester.takeException(), isNull);
    expect(steps, isEmpty);
  });

  testWidgets('넘김 칸을 끄면 가장자리도 가운데 칸으로 동작함', (tester) async {
    final steps = <int>[];
    final events = <String>[];
    await pumpZones(tester, steps: steps, events: events, turns: false);
    await tester.tapAt(const Offset(10, 400));
    await tester.pump(const Duration(seconds: 1));
    expect(steps, isEmpty);
    expect(events, contains('center'));
  });

  testWidgets('스타일러스 전용이면 손가락은 뷰어를 끌고 펜은 뷰어를 끌지 않음', (tester) async {
    final events = <String>[];
    final drawn = <PointerDeviceKind>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => events.add('viewer-pan'),
            ),
            DrawInputLayer(
              stylusOnly: true,
              onDown: (e) => drawn.add(e.kind),
              onMove: (_) {},
              onUp: (_) {},
              onCancel: (_) {},
              child: CustomPaint(size: Size.infinite, painter: _FullPainter()),
            ),
          ],
        ),
      ),
    );
    final finger = await tester.startGesture(const Offset(200, 300));
    await finger.moveBy(const Offset(0, 120));
    await finger.up();
    expect(events, contains('viewer-pan'));

    events.clear();
    final pen = await tester.startGesture(
      const Offset(200, 300),
      kind: PointerDeviceKind.stylus,
      pointer: 7,
    );
    await pen.moveBy(const Offset(0, 120));
    await pen.up();
    expect(events, isEmpty);
    expect(drawn, contains(PointerDeviceKind.stylus));
  });

  testWidgets('반전을 켜고 꺼도 자식 상태가 유지되고, 꺼져 있으면 필터 레이어가 없음', (tester) async {
    _Probe.created = 0;
    Future<void> pumpInvert(bool enabled) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: InvertColors(enabled: enabled, child: const _Probe()),
      ),
    );

    await pumpInvert(false);
    expect(tester.layers.whereType<ColorFilterLayer>(), isEmpty);
    await pumpInvert(true);
    expect(tester.layers.whereType<ColorFilterLayer>(), hasLength(1));
    await pumpInvert(false);
    expect(tester.layers.whereType<ColorFilterLayer>(), isEmpty);
    expect(_Probe.created, 1);
  });

  group('필압', () {
    test('펜 필압은 기기 범위로 나눠 0~1로 맞춤', () {
      const pencil = PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 4.17,
        pressureMin: 0,
        pressureMax: 4.17,
      );
      expect(strokePressure(pencil), closeTo(1.0, 1e-9));

      const light = PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 1.0,
        pressureMin: 0,
        pressureMax: 4.0,
      );
      expect(strokePressure(light), closeTo(0.25, 1e-9));
    });

    test('손가락이거나 범위를 모르면 null이라 렌더러가 흉내 냄', () {
      const finger = PointerDownEvent(pressure: 1.0, pressureMin: 0, pressureMax: 1);
      expect(strokePressure(finger), isNull);

      const flat = PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 1.0,
        pressureMin: 1.0,
        pressureMax: 1.0,
      );
      expect(strokePressure(flat), isNull);
    });
  });
}
