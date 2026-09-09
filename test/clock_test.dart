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

  group('엔진이 던질 때', () {
    /// 오디오 엔진이 도중에 죽으면 getEngineTime()이 던짐. 그대로 두면 매 프레임 예외가 나
    /// 소리뿐 아니라 페이지 자동 넘김까지 멈추므로, 시계가 스스로 물러서는지 고정함.
    test('예외를 밖으로 내보내지 않고 마지막 값을 유지함', () {
      var now = const Duration(seconds: 3);
      var alive = true;
      final clock = withFallbackClock(() {
        if (!alive) throw StateError('엔진 내려감');
        return now;
      });

      expect(clock(), const Duration(seconds: 3));
      alive = false;
      expect(clock, returnsNormally);
      expect(clock(), greaterThanOrEqualTo(const Duration(seconds: 3)));
    });

    test('물러선 뒤에도 시간이 계속 흐름', () async {
      var alive = true;
      final clock = withFallbackClock(() {
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
      final clock = withFallbackClock(() {
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
}
