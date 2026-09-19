// 재생 위치 계산 검증. 일시정지·되감기 뒤 위치가 어긋나면 클릭과 페이지가 통째로 밀림.

import 'package:baton/metronome/clock.dart';
import 'package:baton/score/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration fake;
  late PlaybackClock clock;

  setUp(() {
    fake = Duration.zero;
    clock = PlaybackClock(() => fake);
  });

  test('정지 상태에서는 시간이 흐르지 않음', () {
    fake = const Duration(seconds: 5);
    expect(clock.position, Duration.zero);
    expect(clock.isRunning, isFalse);
  });

  test('시작한 시점부터 경과를 셈', () {
    fake = const Duration(seconds: 10);
    clock.start();
    fake = const Duration(seconds: 13);
    expect(clock.position, const Duration(seconds: 3));
  });

  test('일시정지하면 위치가 멈추고 재개하면 이어감', () {
    fake = const Duration(seconds: 10);
    clock.start();
    fake = const Duration(seconds: 14);
    clock.pause();
    fake = const Duration(seconds: 99);
    expect(clock.position, const Duration(seconds: 4), reason: '멈춘 동안은 안 흐름');

    clock.start();
    fake = const Duration(seconds: 100);
    expect(clock.position, const Duration(seconds: 5));
  });

  test('되감기 뒤에도 경과가 이어짐', () {
    fake = const Duration(seconds: 10);
    clock.start();
    fake = const Duration(seconds: 20);
    clock.seek(const Duration(seconds: 3));
    expect(clock.position, const Duration(seconds: 3));
    fake = const Duration(seconds: 22);
    expect(clock.position, const Duration(seconds: 5));
  });

  test('reset은 위치와 재생 상태를 모두 되돌림', () {
    fake = const Duration(seconds: 10);
    clock.start();
    fake = const Duration(seconds: 15);
    clock.reset();
    expect(clock.position, Duration.zero);
    expect(clock.isRunning, isFalse);
  });

  test('재생 위치를 절대 시각으로 되돌려 예약에 쓸 수 있음', () {
    expect(clock.engineTimeAt(Duration.zero), isNull, reason: '정지 중엔 기준점 없음');
    fake = const Duration(seconds: 10);
    clock.start();
    expect(clock.engineTimeAt(const Duration(seconds: 4)), const Duration(seconds: 14));

    // 일시정지 후 재개하면 기준점이 바뀌어도 같은 재생 위치는 같은 미래를 가리켜야 함
    fake = const Duration(seconds: 12);
    clock.pause();
    fake = const Duration(seconds: 50);
    clock.start();
    expect(clock.engineTimeAt(const Duration(seconds: 4)), const Duration(seconds: 52));
  });

  test('중복 start는 기준점을 흔들지 않음', () {
    fake = const Duration(seconds: 10);
    clock.start();
    fake = const Duration(seconds: 12);
    clock.start();
    expect(clock.position, const Duration(seconds: 2));
  });

  test('초를 Duration으로 반올림함', () {
    expect(secondsToDuration(1.5), const Duration(milliseconds: 1500));
    expect(secondsToDuration(0.0000004), Duration.zero);
    expect(secondsToDuration(2.0), const Duration(seconds: 2));
  });

  test('시작·건너뛰기 기준점을 lead만큼 미래로 둠. 그동안 위치는 목표 앞에 머묾', () {
    fake = const Duration(seconds: 10);
    clock.start(const Duration(milliseconds: 150));
    expect(clock.position, const Duration(milliseconds: -150));
    expect(clock.engineTimeAt(Duration.zero), const Duration(milliseconds: 10150));

    fake = const Duration(seconds: 12);
    clock.seek(const Duration(seconds: 30), const Duration(milliseconds: 150));
    expect(clock.position, const Duration(milliseconds: 29850));
    expect(clock.engineTimeAt(const Duration(seconds: 30)), const Duration(milliseconds: 12150));
  });

  group('엔진이 던질 때', () {
    /// 오디오 엔진이 도중에 죽으면 getEngineTime()이 던짐. 그대로 두면 매 프레임 예외가 나
    /// 소리뿐 아니라 페이지 자동 넘김까지 멈추므로, 시계가 스스로 물러서는지 고정함.
    test('예외를 밖으로 내보내지 않고 마지막 값을 유지함', () {
      var now = const Duration(seconds: 3);
      var alive = true;
      final clock = FallbackTime(() {
        if (!alive) throw StateError('엔진 내려감');
        return now;
      });

      expect(clock(), const Duration(seconds: 3));
      alive = false;
      expect(clock.call, returnsNormally);
      expect(clock(), greaterThanOrEqualTo(const Duration(seconds: 3)));
      expect(clock.fellBack, isTrue);
    });

    test('물러선 뒤에도 시간이 계속 흐름', () async {
      var alive = true;
      final clock = FallbackTime(() {
        if (!alive) throw StateError('엔진 내려감');
        return const Duration(seconds: 10);
      });
      clock();
      alive = false;
      final first = clock();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(clock(), greaterThan(first));
    });

    test('엔진이 살아나도 되돌아가지 않음. 두 시간축을 오가면 위치가 튐', () async {
      var alive = true;
      var engine = const Duration(seconds: 100);
      final clock = FallbackTime(() {
        if (!alive) throw StateError('엔진 내려감');
        return engine;
      });
      clock();
      alive = false;
      clock();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 엔진이 돌아오고 시각이 크게 앞서 있어도 무시함
      alive = true;
      engine = const Duration(seconds: 9999);
      expect(clock(), lessThan(const Duration(seconds: 200)));
    });
  });

  group('엔진 시각이 멈출 때', () {
    /// 출력 장치가 멈추면(iOS 인터럽트, Android 재라우팅 실패) getEngineTime()은 던지지 않고
    /// 같은 값만 돌려줌. 예외만 보면 자동 넘김이 그 자리에 얼어붙음.
    const limit = Duration(milliseconds: 30);

    test('멈춘 채로 한도를 넘기면 멈춘 자리부터 실제 시간으로 이어감', () async {
      final clock = FallbackTime(() => const Duration(seconds: 7), stallLimit: limit);
      expect(clock(), const Duration(seconds: 7));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final caughtUp = clock();
      expect(clock.fellBack, isTrue);
      expect(caughtUp, greaterThanOrEqualTo(const Duration(seconds: 7) + limit));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(clock(), greaterThan(caughtUp));
    });

    test('계단식으로 오르는 동안에는 물러서지 않음', () async {
      var engine = const Duration(seconds: 1);
      final clock = FallbackTime(() => engine, stallLimit: limit);
      for (var i = 0; i < 6; i++) {
        clock();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        engine += const Duration(milliseconds: 15);
      }
      expect(clock.fellBack, isFalse);
      expect(clock(), engine);
    });

    test('재생을 새로 시작하면 장치를 깨우고 엔진을 다시 따름', () async {
      var engine = const Duration(seconds: 5);
      var woke = 0;
      final clock = FallbackTime(
        () => engine,
        stallLimit: limit,
        wake: () {
          woke++;
          return true;
        },
      );
      clock();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      clock();
      expect(clock.fellBack, isTrue);

      engine = const Duration(seconds: 6);
      clock.rearm();
      expect(woke, 1);
      expect(clock.fellBack, isFalse);
      expect(clock(), const Duration(seconds: 6));
    });

    test('장치를 못 깨우면 한도를 기다리지 않고 바로 물러섬', () {
      final clock = FallbackTime(() => const Duration(seconds: 5), wake: () => false);
      clock();
      clock.rearm();
      expect(clock.fellBack, isTrue);
    });

    test('물러선 시계도 재생을 다시 시작하면 장치를 깨워 엔진을 따름', () async {
      var woke = 0;
      final clock = PlaybackClock.engine(
        FallbackTime(
          () => const Duration(seconds: 5),
          stallLimit: limit,
          wake: () {
            woke++;
            return true;
          },
        ),
      );
      clock.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      clock.position;
      expect(clock.followsEngine, isFalse);

      clock.pause();
      clock.start();
      expect(woke, 2, reason: '시작할 때마다 장치를 깨움');
      expect(clock.followsEngine, isTrue);
    });

    test('물러선 시계는 엔진 예약에 쓸 수 없다고 알림', () async {
      final clock = PlaybackClock.engine(
        FallbackTime(() => const Duration(seconds: 5), stallLimit: limit),
      );
      clock.start();
      expect(clock.followsEngine, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      clock.position;
      expect(clock.followsEngine, isFalse);
    });
  });
}
