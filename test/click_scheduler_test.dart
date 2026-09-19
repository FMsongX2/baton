// 클릭 예약 검증. 첫 강박이 버려지거나 지연 보정이 예약 창을 잡아먹으면 소리가 빠지므로
// 가짜 오디오 엔진 시각 위에서 실제 ClickScheduler와 PlaybackEngine을 돌려 고정함.

import 'package:baton/metronome/click_scheduler.dart';
import 'package:baton/metronome/clock.dart';
import 'package:baton/metronome/metronome_page.dart';
import 'package:baton/score/playback_engine.dart';
import 'package:baton/score/timeline.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';

/// 손으로 미는 엔진 시각과 예약 기록. 실제 엔진처럼 지난 시각이 예약돼도 받아 줌.
class _FakeSoLoud implements SoLoud {
  Duration now = const Duration(seconds: 100);
  final played = <Duration>[];
  final stopped = <SoundHandle>[];

  /// true면 출력 장치를 켜지 못한 것처럼 예약마다 던짐.
  bool failPlay = false;
  var _handles = 0;

  /// 손으로 민 엔진 시각.
  @override
  Duration getEngineTime() => now;

  /// 예약 시각을 기록함. failPlay면 던짐.
  @override
  SoundHandle playScheduled(
    AudioSource sound,
    Duration atTime, {
    Duration? duration,
    int busId = 0,
    double volume = 1,
    double pan = 0,
  }) {
    if (failPlay) throw StateError('출력 장치 시작 실패');
    played.add(atTime);
    return SoundHandle(++_handles);
  }

  /// 거둔 예약을 기록함.
  @override
  void stopScheduled(SoundHandle handle, Duration atTime) => stopped.add(handle);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 소리 자리만 채우는 음원.
class _FakeSource implements AudioSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 4/4 120bpm(박 0.5초) 페이지 두 장, 각 4마디. 카운트인 1마디.
Timeline _timeline() => buildTimeline(
  const ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    leadBeats: 0,
    pages: [PageTiming(barCount: 4), PageTiming(barCount: 4)],
  ),
);

void main() {
  late _FakeSoLoud soloud;
  late PlaybackClock clock;
  late ClickScheduler scheduler;
  late PlaybackEngine engine;
  const start = Duration(seconds: 100);

  /// 엔진 시각과 스케줄러·재생 엔진을 새로 묶음. clock을 바꿔 끼울 때도 씀.
  void wire(PlaybackClock c, {Duration latency = Duration.zero}) {
    clock = c;
    scheduler = ClickScheduler(soloud, clock)
      ..accent = _FakeSource()
      ..tick = _FakeSource()
      ..latency = latency;
    engine = PlaybackEngine(clock, scheduler)..load(_timeline());
  }

  setUp(() {
    soloud = _FakeSoLoud();
    wire(PlaybackClock(soloud.getEngineTime));
  });

  /// 엔진 시각을 dt만큼 올리고 한 프레임을 돌림.
  void frame(Duration dt) {
    soloud.now += dt;
    engine.tick();
  }

  group('첫 클릭', () {
    /// 기준점을 '지금'으로 잡으면 시작 지점 클릭의 예약 시각이 다음 프레임에 이미 과거라
    /// 매번 버려짐. 카운트인 강박, 재개·건너뛰기 뒤의 첫 강박이 모두 여기에 걸림.
    for (final latencyMs in [0, 250]) {
      test('재생을 누른 순간의 강박이 예약됨(지연 보정 ${latencyMs}ms)', () {
        wire(PlaybackClock(soloud.getEngineTime), latency: Duration(milliseconds: latencyMs));
        engine.play();
        // 다음 프레임에 엔진 시각이 출력 버퍼 한 칸만큼 오름
        frame(const Duration(milliseconds: 46));
        expect(soloud.played.first, start + ClickScheduler.startMargin);
      });
    }

    test('재생 중 건너뛰면 새 페이지의 강박이 예약됨', () {
      engine.play();
      for (var i = 0; i < 60; i++) {
        frame(const Duration(milliseconds: 50));
      }
      final jumpedAt = soloud.now;
      // 점프 전 예약이 우연히 같은 시각에 걸릴 수 있으니 점프 뒤에 새로 예약한 것만 봄
      final before = soloud.played.length;
      engine.jumpToSpan(1);
      frame(const Duration(milliseconds: 46));
      expect(soloud.played.skip(before).first, jumpedAt + ClickScheduler.startMargin);
    });

    test('재개하면 되감은 카운트인 마디의 강박이 예약됨', () {
      engine.play();
      for (var i = 0; i < 95; i++) {
        frame(const Duration(milliseconds: 50));
      }
      engine.pause();
      soloud.now += const Duration(seconds: 5);
      final resumedAt = soloud.now;
      engine.play();
      frame(const Duration(milliseconds: 46));
      expect(
        soloud.played.where((at) => at >= resumedAt).first,
        resumedAt + ClickScheduler.startMargin,
      );
    });

    // 일시정지가 거둔 클릭은 커서가 다시 예약해야 함. 되감기(seek)를 타지 않는 재개가 여기에 걸림
    const resumeCases = [
      (name: '카운트인 0마디 곡', countInBars: 0, pauseAt: 1.25, first: 1.5),
      (name: '카운트인 도중', countInBars: 1, pauseAt: 1.25, first: 1.5),
      (name: '시작 대기(lead) 도중', countInBars: 1, pauseAt: -0.1, first: 0.0),
    ];
    for (final c in resumeCases) {
      for (final latencyMs in [0, 250]) {
        test('${c.name}에서 멈췄다 재개해도 멈춘 자리 뒤 첫 클릭이 예약됨(지연 보정 ${latencyMs}ms)', () {
          wire(PlaybackClock(soloud.getEngineTime), latency: Duration(milliseconds: latencyMs));
          engine.load(
            buildTimeline(
              ScoreTiming(
                bpm: 120,
                clicksPerBar: 4,
                countInBars: c.countInBars,
                leadBeats: 0,
                pages: const [PageTiming(barCount: 4), PageTiming(barCount: 4)],
              ),
            ),
          );
          engine.play();
          while (engine.position < secondsToDuration(c.pauseAt)) {
            frame(const Duration(milliseconds: 10));
          }
          engine.pause();
          soloud.now += const Duration(seconds: 5);
          final before = soloud.played.length;
          engine.play();
          for (var i = 0; i < 20; i++) {
            frame(const Duration(milliseconds: 50));
          }
          expect(
            soloud.played.skip(before).first,
            clock.engineTimeAt(secondsToDuration(c.first))! - scheduler.latency,
          );
        });
      }
    }

    test('µs 반올림이 올림되는 스팬 시작으로 재생 중 건너뛰어도 그 스팬의 첫 강박이 예약됨', () {
      // 100bpm 4/4에서 둘째 쪽 시작은 누적 오차로 11.999999999999996이고 Duration으로는 12.0으로 올림됨
      engine.load(
        buildTimeline(
          ScoreTiming(
            bpm: 100,
            clicksPerBar: 4,
            leadBeats: 0,
            pages: List.filled(3, const PageTiming(barCount: 4)),
          ),
        ),
      );
      expect(engine.timeline!.spans[1].start, lessThan(12.0), reason: '전제: 올림되는 경계');
      engine.play();
      for (var i = 0; i < 20; i++) {
        frame(const Duration(milliseconds: 50));
      }
      final jumpedAt = soloud.now;
      final before = soloud.played.length;
      engine.jumpToSpan(1);
      for (var i = 0; i < 20; i++) {
        frame(const Duration(milliseconds: 46));
      }
      expect(soloud.played.skip(before).first, jumpedAt + ClickScheduler.startMargin);
    });
  });

  test('재생 중 건너뛴 직후 기준점 대기 동안 앞 페이지로 깜빡이지 않음', () {
    // 선행 넘김 0이면 앞 페이지의 넘김 시각이 곧 새 페이지 시작이라, 대기 중 위치로 스팬을 되짚으면
    // 앞 페이지로 판정됨. 지연 보정을 두어 대기를 길게 잡음
    wire(PlaybackClock(soloud.getEngineTime), latency: const Duration(milliseconds: 250));
    final pages = <int>[];
    engine.onPageChanged = pages.add;
    engine.play();
    for (var i = 0; i < 60; i++) {
      frame(const Duration(milliseconds: 50));
    }
    pages.clear();
    engine.jumpToSpan(1);
    for (var i = 0; i < 20; i++) {
      frame(const Duration(milliseconds: 46));
    }
    expect(engine.position, greaterThan(const Duration(seconds: 10)), reason: '대기를 지남');
    expect(pages, [1]);
  });

  test('재생 중 클릭을 다시 켜면 꺼 둔 사이 지나친 예약 창의 박부터 다시 예약함', () {
    engine.play();
    while (engine.position < const Duration(milliseconds: 3100)) {
      frame(const Duration(milliseconds: 10));
    }
    scheduler.muted = true;
    // 꺼진 동안에도 커서는 예약 창 끝(3.55초 이후)까지 밀림
    while (engine.position < const Duration(milliseconds: 3250)) {
      frame(const Duration(milliseconds: 10));
    }
    scheduler.muted = false;
    final before = soloud.played.length;
    for (var i = 0; i < 60; i++) {
      frame(const Duration(milliseconds: 10));
    }
    expect(
      soloud.played.skip(before).first,
      clock.engineTimeAt(const Duration(milliseconds: 3500)),
    );
  });

  test('지연 보정이 룩어헤드보다 커도 클릭이 빠지지 않음', () {
    wire(PlaybackClock(soloud.getEngineTime), latency: const Duration(milliseconds: 400));
    engine.play();
    // 60Hz 프레임, 엔진 시각은 46ms 계단
    var real = Duration.zero;
    for (var i = 0; i < 200; i++) {
      real += const Duration(milliseconds: 16);
      soloud.now = start + const Duration(milliseconds: 46) * (real.inMilliseconds ~/ 46);
      engine.tick();
    }
    expect(soloud.played.length, greaterThanOrEqualTo(6));
    expect(soloud.played.first, start + ClickScheduler.startMargin);
    for (var i = 1; i < soloud.played.length; i++) {
      expect(soloud.played[i] - soloud.played[i - 1], const Duration(milliseconds: 500));
    }
  });

  test('지연 보정은 0~400ms로 접힘', () {
    scheduler.latency = const Duration(seconds: 3);
    expect(scheduler.latency, kMaxLatency);
    scheduler.latency = const Duration(milliseconds: -20);
    expect(scheduler.latency, Duration.zero);
  });

  test('예약이 실패해도 프레임이 끊기지 않고 페이지는 계속 넘어감', () {
    soloud.failPlay = true;
    final pages = <int>[];
    engine.onPageChanged = pages.add;
    engine.play();
    for (var i = 0; i < 250; i++) {
      frame(const Duration(milliseconds: 50));
    }
    expect(pages.last, 1, reason: '둘째 페이지(10초)까지 넘어감');
  });

  test('시계가 Stopwatch로 물러서면 걸어 둔 클릭을 거두고 더 예약하지 않음', () async {
    wire(
      PlaybackClock.engine(
        FallbackTime(soloud.getEngineTime, stallLimit: const Duration(milliseconds: 30)),
      ),
    );
    engine.play();
    engine.tick();
    expect(soloud.played, isNotEmpty);
    final before = soloud.played.length;

    // 출력 장치가 멈춰 엔진 시각이 그대로 멈춤
    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.tick();
    engine.tick();
    expect(clock.followsEngine, isFalse);
    expect(soloud.stopped, isNotEmpty);
    expect(soloud.played.length, before);
  });

  group('메트로놈 이음매', () {
    // 한 바퀴 1초, 8분 분할로 125ms마다 클릭
    final clicks = metronomeClicks(bpm: 240, clicksPerBar: 4, bars: 1, subdivision: 2);
    const loop = Duration(seconds: 1);

    test('앞 바퀴 끝 박이 남고 새 바퀴가 이음매에 맞음', () {
      scheduler.load(clicks, Duration.zero);
      clock.start(scheduler.startLead);
      final zeroAt = clock.engineTimeAt(Duration.zero)!;

      do {
        soloud.now += const Duration(milliseconds: 16);
        scheduler.pump();
      } while (!wrapLoop(clock, scheduler, loop));
      expect(soloud.played.last, zeroAt + loop - const Duration(milliseconds: 125));
      expect(soloud.stopped, isEmpty, reason: '이미 걸어 둔 끝 박을 거두면 이음매 직전이 빔');

      soloud.now += const Duration(milliseconds: 16);
      scheduler.pump();
      expect(soloud.played, contains(zeroAt + loop));
    });

    test('판정 전에 엔진 시각이 올라도 앞 바퀴 끝 박을 빠뜨리지 않음', () {
      scheduler.load(clicks, Duration.zero);
      clock.start(scheduler.startLead);
      final zeroAt = clock.engineTimeAt(Duration.zero)!;

      // 마지막 pump는 0.85초까지만 예약함
      soloud.now = zeroAt + const Duration(milliseconds: 550);
      scheduler.pump();
      expect(soloud.played, isNot(contains(zeroAt + const Duration(milliseconds: 875))));

      // pump와 이음매 판정 사이에 엔진 시각이 오름
      soloud.now = zeroAt + const Duration(milliseconds: 700);
      expect(wrapLoop(clock, scheduler, loop), isTrue);
      expect(soloud.played, contains(zeroAt + const Duration(milliseconds: 875)));
    });
  });
}
