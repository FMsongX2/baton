// 재생줄의 위치 조작 잠금과 넘김 예고. 재생 중이거나 터치 잠금 중이면 처음으로·진행바가 막히고,
// 맨 위 띠가 지금 쪽의 넘김까지 차오르며 한 마디 전부터 예고하는지를 고정함.

import 'package:baton/metronome/click_scheduler.dart';
import 'package:baton/metronome/clock.dart';
import 'package:baton/reader/playback_bar.dart';
import 'package:baton/score/playback_engine.dart';
import 'package:baton/score/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 소리를 내지 않는 스케줄러. 엔진이 부르는 것만 받아 넘김.
class _SilentScheduler implements ClickScheduler {
  /// 거둘 예약이 없음.
  @override
  void cancelPending() {}

  /// 클릭을 받지 않음.
  @override
  void load(List<Click> clicks, Duration from) {}

  /// 되감을 예약이 없음.
  @override
  void rewindTo(Duration p) {}

  /// 예약할 클릭이 없어 0개를 돌려줌.
  @override
  int pump() => 0;

  /// 이 테스트가 부르지 않는 나머지는 실수로 불리면 드러나게 던짐.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 4/4 120bpm(한 마디 2초), 쪽마다 4마디, 카운트인 1마디, 선행 2박(1초).
/// 스팬 0은 2~10초(넘김 9초), 스팬 1은 10~18초(넘김 17초), 스팬 2는 18~26초.
Timeline _timeline() => buildTimeline(
  const ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    leadBeats: 2,
    pages: [PageTiming(barCount: 4), PageTiming(barCount: 4), PageTiming(barCount: 4)],
  ),
);

/// 쪽마다 마디수를 따로 줌. 0이면 표지·빈 쪽처럼 연주가 없는 쪽. 나머지는 _timeline과 같음.
Timeline _bars(List<int> bars) => buildTimeline(
  ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    leadBeats: 2,
    pages: [for (final b in bars) PageTiming(barCount: b)],
  ),
);

void main() {
  group('넘김 예고', () {
    test('앞 쪽이 넘어온 순간 0에서 시작해 이 쪽 넘김에서 1', () {
      final t = _timeline();
      expect(pageTurnProgress(t, 1, 9.0).progress, closeTo(0, 1e-9));
      expect(pageTurnProgress(t, 1, 13.0).progress, closeTo(0.5, 1e-9));
      expect(pageTurnProgress(t, 1, 17.0).progress, closeTo(1, 1e-9));
    });

    test('넘김이 한 마디 안으로 오면 예고하고, 그 전에는 하지 않음', () {
      final t = _timeline();
      expect(pageTurnProgress(t, 1, 14.9).soon, isFalse);
      expect(pageTurnProgress(t, 1, 15.1).soon, isTrue);
    });

    test('마지막 쪽은 넘길 곳이 없어 예고하지 않음', () {
      final t = _timeline();
      expect(pageTurnProgress(t, 2, 25.5).soon, isFalse);
    });

    test('끝 쪽이 빈 쪽이면 앞의 연주 쪽이 마지막 쪽. 오지 않을 넘김을 예고하지 않음', () {
      // 스팬 0은 2~10초(넘김 9초). 엔진은 빈 쪽으로 넘기지 않음
      final r = pageTurnProgress(_bars([4, 0]), 0, 8.5);
      expect(r.soon, isFalse);
      expect(r.progress, closeTo(8.5 / 10, 1e-9));
    });

    test('가운데 빈 쪽 너머로 넘어온 쪽은 앞 쪽의 넘김부터 차오름', () {
      // 스팬 0은 넘김 9초, 빈 스팬 1은 10초, 스팬 2는 10~18초. 9초에 스팬 0에서 2로 넘어가고 곡 끝까지 참
      expect(pageTurnProgress(_bars([4, 0, 4]), 2, 9.5).progress, closeTo(0.5 / 9, 1e-9));
    });
  });

  group('위치 조작 잠금', () {
    late PlaybackEngine engine;

    setUp(() {
      engine = PlaybackEngine(PlaybackClock(() => Duration.zero), _SilentScheduler())
        ..load(_timeline());
    });

    Future<void> pumpBar(WidgetTester tester, {bool locked = false}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackBar(engine: engine, onJumpToSpan: engine.jumpToSpan, locked: locked),
        ),
      ),
    );

    VoidCallback? toStart(WidgetTester tester) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_previous)).onPressed;

    ValueChanged<double>? slider(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider)).onChanged;

    testWidgets('멈춰 있으면 처음으로와 진행바를 쓸 수 있음', (tester) async {
      await pumpBar(tester);
      expect(toStart(tester), isNotNull);
      expect(slider(tester), isNotNull);
    });

    testWidgets('재생 중에는 처음으로와 진행바를 막음', (tester) async {
      await pumpBar(tester);
      // 재생줄은 재생 여부 알림만 봄. play()를 부르면 엔진의 시계·예약 세부에 테스트가 묶임
      engine.isPlaying.value = true;
      await tester.pump();
      expect(toStart(tester), isNull);
      expect(slider(tester), isNull);
      engine.isPlaying.value = false;
      await tester.pump();
      expect(toStart(tester), isNotNull);
    });

    testWidgets('터치 잠금 중에는 멈춰 있어도 막음', (tester) async {
      await pumpBar(tester, locked: true);
      expect(toStart(tester), isNull);
      expect(slider(tester), isNull);
    });
  });
}
