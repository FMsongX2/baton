// 재생 엔진의 상태 전이. 카운트인 셈, 일시정지 후 재개 되감기, 멈춘 뒤 진행률 갱신을 고정함.
// 오디오 엔진 없이 돌려야 하므로 클럭에는 직접 움직이는 가짜 시계를 물림.

import 'dart:async';

import 'package:baton/metronome/click_scheduler.dart';
import 'package:baton/metronome/clock.dart';
import 'package:baton/score/playback_engine.dart';
import 'package:baton/score/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// 손으로 밀어 주는 시계. 실제 시간과 무관하게 재생 위치를 원하는 지점에 둘 수 있음.
class _FakeNow {
  Duration value = Duration.zero;
  Duration call() => value;
}

/// 소리를 내지 않는 스케줄러. 예약 호출만 세어 클럭 조작이 반영됐는지 확인함.
class _FakeScheduler implements ClickScheduler {
  int cancels = 0;
  int pumps = 0;
  Duration? lastRewind;

  /// 스케줄러가 실제로 받은 클릭. 비어 있으면 소리가 날 수 없음.
  List<Click> clicks = const [];

  @override
  void cancelPending() => cancels++;

  @override
  void load(List<Click> clicks, Duration from) {
    this.clicks = clicks;
    lastRewind = from;
  }

  @override
  void rewindTo(Duration p) => load(clicks, p);

  /// 기준점을 미래로 미는 길이. 0이면 위치가 시각과 그대로 맞아 기대값을 적기 쉬움.
  @override
  Duration startLead = Duration.zero;

  @override
  int pump() {
    pumps++;
    return 0;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 4/4 120bpm(한 마디 2초) 페이지 두 장, 각 4마디. 카운트인 1마디.
Timeline _timeline({int countInBars = 1}) => buildTimeline(
  ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    countInBars: countInBars,
    leadBeats: 0,
    pages: const [PageTiming(barCount: 4), PageTiming(barCount: 4)],
  ),
);

void main() {
  late _FakeNow now;
  late PlaybackClock clock;
  late _FakeScheduler scheduler;
  late PlaybackEngine engine;

  setUp(() {
    now = _FakeNow();
    clock = PlaybackClock(now.call);
    scheduler = _FakeScheduler();
    engine = PlaybackEngine(clock, scheduler);
    engine.load(_timeline());
  });

  /// 재생을 시작하고 시계를 지정 위치까지 밀어 tick을 한 번 돌림.
  void advanceTo(double seconds) {
    now.value = Duration(microseconds: (seconds * 1e6).round());
    engine.tick();
  }

  test('카운트인은 마디 클릭 수부터 1까지 셈', () {
    engine.play();
    advanceTo(0);
    expect(engine.countInRemaining, 4);
    advanceTo(0.5);
    expect(engine.countInRemaining, 3);
    advanceTo(1.5);
    expect(engine.countInRemaining, 1);
    // 카운트인이 끝나면 숫자가 사라짐
    advanceTo(2.0);
    expect(engine.countInRemaining, isNull);
  });

  test('멈춘 뒤에도 진행률과 카운트인이 지금 위치를 가리킴', () {
    engine.play();
    advanceTo(4.0);
    engine.pause();
    expect(engine.progressValue.value, closeTo(4.0 / 18.0, 1e-9));
    expect(engine.countIn.value, isNull);
  });

  test('중간에서 재개하면 마디선까지 되감고 그 구간을 카운트인으로 셈', () {
    engine.play();
    // 첫 페이지 두 번째 마디 도중(카운트인 2초 + 2.6초)
    advanceTo(4.6);
    engine.pause();

    engine.play();
    // 2초(카운트인) + 1마디 지난 4초 지점에서 한 마디를 되감아 2초로 감
    expect(engine.position.inMilliseconds, 2000);
    expect(engine.countInRemaining, 4);
  });

  test('카운트인 0마디면 되감지 않고 그 자리에서 이어감', () {
    engine.load(_timeline(countInBars: 0));
    engine.play();
    advanceTo(3.3);
    engine.pause();
    engine.play();
    expect(engine.position.inMilliseconds, 3300);
  });

  test('처음 시작은 되감지 않고 카운트인부터 감', () {
    engine.play();
    expect(engine.position, Duration.zero);
    expect(engine.countInRemaining, 4);
  });

  test('되감아 앞 페이지로 넘어가면 페이지 표시도 함께 돌아감', () {
    final pages = <int>[];
    engine.onPageChanged = pages.add;
    engine.play();
    // 둘째 페이지 첫 마디 도중
    advanceTo(10.5);
    expect(engine.spanIndex.value, 1);
    engine.pause();

    engine.play();
    // 둘째 페이지 시작(10초)에서 한 마디 되감으면 첫 페이지 끝(8초)
    expect(engine.position.inMilliseconds, 8000);
    advanceTo(8.1);
    expect(engine.spanIndex.value, 0);
    expect(pages.last, 0);
  });

  test('일시정지와 구간 점프는 예약된 클릭을 거둠', () {
    engine.play();
    advanceTo(4.0);
    final before = scheduler.cancels;
    engine.pause();
    expect(scheduler.cancels, greaterThan(before));

    engine.jumpToSpan(1);
    expect(scheduler.lastRewind!.inMilliseconds, 10000);
  });

  test('멈춰 있는 동안에는 카운트인 숫자가 뜨지 않음', () {
    // 악보를 열면 load가 처음으로 되돌리는데, 이때 숫자가 뜨면 악보를 덮어 버림
    expect(engine.countIn.value, isNull);
    expect(engine.countInRemaining, isNull);

    engine.play();
    expect(engine.countInRemaining, 4);
    engine.pause();
    expect(engine.countInRemaining, isNull);
  });

  test('곡 뒤쪽에서 재개해도 카운트인은 그 구간만 셈', () {
    engine.play();
    // 둘째 페이지 셋째 마디 도중
    advanceTo(15.0);
    engine.pause();
    engine.play();
    expect(engine.position.inMilliseconds, 12000);
    expect(engine.countInRemaining, 4);
  });

  test('악보를 걸면 클릭 배열이 스케줄러까지 감', () {
    // 이 호출이 빠지면 페이지는 넘어가는데 소리만 나지 않아 원인 추적이 어려움
    expect(scheduler.clicks, isNotEmpty);
    expect(scheduler.clicks.length, greaterThan(4));
    expect(scheduler.clicks.first.accent, isTrue);
  });

  test('끝까지 재생한 뒤 다시 누르면 처음부터 감', () {
    engine.play();
    advanceTo(18.0);
    expect(engine.isPlaying.value, isFalse);

    engine.play();
    expect(engine.position, Duration.zero);
    expect(engine.isPlaying.value, isTrue);
    expect(engine.spanIndex.value, 0);
  });

  test('재생을 누르면 멈춘 사이 화면이 어디 있든 재생 위치의 페이지를 다시 알림', () {
    final pages = <int>[];
    engine.onPageChanged = pages.add;
    engine.play();
    advanceTo(4.6);
    engine.pause();
    // 멈춘 동안 페달로 다른 쪽을 봤어도 엔진은 모름. 같은 스팬 안에서 재개해도 알려야 화면이 돌아옴
    pages.clear();
    engine.play();
    expect(pages, [0]);
  });

  test('시작 기준점을 미래로 미는 동안에는 카운트인 숫자를 띄우지 않음', () {
    scheduler.startLead = const Duration(milliseconds: 150);
    engine.play();
    expect(engine.position, const Duration(milliseconds: -150));
    expect(engine.countInRemaining, isNull);
    advanceTo(0.15);
    expect(engine.position, Duration.zero);
    expect(engine.countInRemaining, 4);
  });

  test('건너뛴 직후 기준점 대기 중에 멈추면 건너뛴 지점에 멈춘 것으로 보고 그 마디선에서 되감음', () {
    // 대기 중 위치는 목표(10초) 앞. 그대로 멈추면 재개가 앞 쪽 마디선(8초)에서 한 마디 더 물러서 6초로 감
    scheduler.startLead = const Duration(milliseconds: 150);
    engine.play();
    advanceTo(5.0);
    engine.jumpToSpan(1);
    engine.pause();
    expect(engine.position, const Duration(seconds: 10));
    engine.play();
    advanceTo(5.15);
    expect(engine.position, const Duration(seconds: 8));
  });

  test('재개 기준점 대기 중에 멈췄다 다시 재개하면 같은 마디선에서 같은 카운트인을 셈', () {
    // 소리 한 번 없이 멈춘 재개가 되감기를 또 타면 8초에서 6초로 한 마디 더 물러서 앞 쪽을 보여 줌
    engine.play();
    advanceTo(10.5);
    engine.pause();
    scheduler.startLead = const Duration(milliseconds: 150);
    engine.play();
    engine.pause();
    expect(engine.position, const Duration(seconds: 8));
    engine.play();
    advanceTo(10.65);
    expect(engine.position, const Duration(seconds: 8));
    expect(engine.countInRemaining, 4);
  });

  test('오디오 세션 사건(전화·이어폰 빠짐)이 오면 스스로 멈추고 다시 틀지 않음', () async {
    final halts = StreamController<void>();
    final engine = PlaybackEngine(PlaybackClock(now.call, halts: halts.stream), scheduler)
      ..load(_timeline());
    engine.play();
    halts.add(null);
    await pumpEventQueue();
    expect(engine.isPlaying.value, isFalse);
    engine.dispose();
    await halts.close();
  });

  group('0마디 쪽', () {
    Timeline coverFirst() => buildTimeline(
      const ScoreTiming(
        bpm: 120,
        clicksPerBar: 4,
        leadBeats: 0,
        pages: [PageTiming(barCount: 0), PageTiming(barCount: 4), PageTiming(barCount: 4)],
      ),
    );

    test('악보를 열면 표지를 건너뛰어 카운트인 동안 첫 연주 페이지가 보임', () {
      final pages = <int>[];
      engine.onPageChanged = pages.add;
      engine.load(coverFirst());
      expect(pages.last, 1);
      engine.play();
      advanceTo(1.0);
      expect(engine.spanIndex.value, 1);
    });

    test('건너뛰기는 빈 쪽에 서지 않고 가는 방향의 실제 쪽으로 감', () {
      engine.load(
        buildTimeline(
          const ScoreTiming(
            bpm: 120,
            clicksPerBar: 4,
            leadBeats: 0,
            pages: [PageTiming(barCount: 4), PageTiming(barCount: 0), PageTiming(barCount: 4)],
          ),
        ),
      );
      engine.play();
      engine.jumpToSpan(1);
      expect(engine.spanIndex.value, 2);
      engine.jumpToSpan(1);
      expect(engine.spanIndex.value, 0, reason: '뒤로 가다 빈 쪽에 걸려 제자리로 돌아오면 안 됨');
    });
  });

  test('스팬 시작으로 건너뛴 뒤 재개해도 µs 반올림 때문에 앞 스팬으로 떨어지지 않음', () {
    // 100bpm 4/4에서 넷째 쪽 시작은 누적 오차로 31.20000000000003이고 Duration으로는 31.2가 됨
    final t = buildTimeline(
      ScoreTiming(
        bpm: 100,
        clicksPerBar: 4,
        leadBeats: 0,
        pages: List.filled(5, const PageTiming(barCount: 4)),
      ),
    );
    engine.load(t);
    engine.jumpToSpan(3);
    engine.play();
    final bar = barSeconds(4, 100);
    expect(engine.position.inMicroseconds / 1e6, closeTo(t.spans[3].start - bar, 1e-6));
    expect(engine.countInRemaining, 4);
  });

  test('첫 스팬으로 건너뛴 뒤 재개해도 카운트인을 다시 셈', () {
    // 72bpm은 카운트인 끝이 µs로 내림되어, 반올림을 덮지 않으면 카운트인 구간으로 판정됨
    engine.load(
      buildTimeline(
        const ScoreTiming(
          bpm: 72,
          clicksPerBar: 4,
          leadBeats: 0,
          pages: [PageTiming(barCount: 4), PageTiming(barCount: 4)],
        ),
      ),
    );
    engine.jumpToSpan(0);
    engine.play();
    expect(engine.position, Duration.zero);
    expect(engine.countInRemaining, 4);
  });

  test('재개 되감기가 앞 페이지로 넘어가면 그 페이지의 템포로 한 마디를 셈', () {
    // 앞쪽 60bpm(마디 4초), 뒤쪽 120bpm(마디 2초). 카운트인은 첫 쪽 템포라 4초
    engine.load(
      buildTimeline(
        const ScoreTiming(
          bpm: 60,
          clicksPerBar: 4,
          leadBeats: 0,
          pages: [PageTiming(barCount: 2), PageTiming(barCount: 2, bpm: 120)],
        ),
      ),
    );
    engine.play();
    // 뒤쪽 첫 마디 도중(12초 시작)
    advanceTo(12.5);
    engine.pause();
    engine.play();
    expect(engine.position.inMilliseconds, 8000, reason: '앞쪽 마지막 마디선');
    expect(engine.countInRemaining, 4);
  });

  test('재개 되감기가 박자가 다른 앞 페이지로 넘어가도 마디선에 섬', () {
    // 앞쪽 3/4(마디 1.5초), 뒤쪽 4/4(마디 2초), 같은 120bpm
    engine.load(
      buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 3,
          leadBeats: 0,
          pages: [PageTiming(barCount: 2), PageTiming(barCount: 2, clicksPerBar: 4)],
        ),
      ),
    );
    engine.play();
    advanceTo(5.0);
    engine.pause();
    engine.play();
    expect(engine.position.inMilliseconds, 3000);
    expect(engine.countInRemaining, 3);
  });
}
