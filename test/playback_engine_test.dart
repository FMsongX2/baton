// 재생 엔진의 상태 전이. 카운트인 셈, 일시정지 후 재개 되감기, 멈춘 뒤 진행률 갱신을 고정함.
// 오디오 엔진 없이 돌려야 하므로 클럭에는 직접 움직이는 가짜 시계를 물림.

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
}
