// 넘김 입력이 가는 쪽·스팬 계산. 멈춘 동안의 넘김이 넘긴 방향의 재생 위치가 되고 0마디 쪽도 화면에 보이는지,
// 재생 중 선행 넘김 뒤의 이전이 시계를 두고 앞 쪽만 보여 주는지, 지나가는 쪽이 넘김 기준을 흔들지 않는지를 고정함.

import 'package:baton/metronome/click_scheduler.dart';
import 'package:baton/metronome/clock.dart';
import 'package:baton/reader/page_nav.dart';
import 'package:baton/score/playback_engine.dart';
import 'package:baton/score/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// 4/4 120bpm(한 마디 2초), 쪽마다 4마디, 카운트인 1마디, 선행 2박(1초).
/// playOrder가 없으면 스팬 0은 2~10초(넘김 9초), 스팬 1은 10~18초(넘김 17초), 스팬 2는 18~26초.
Timeline _timeline({int pages = 3, List<int>? playOrder}) => buildTimeline(
  ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    leadBeats: 2,
    pages: [for (var i = 0; i < pages; i++) const PageTiming(barCount: 4)],
    playOrder: playOrder,
  ),
);

/// 쪽마다 마디수를 따로 줌. 0이면 표지·빈 쪽처럼 연주가 없는 쪽.
Timeline _bars(List<int> bars) => buildTimeline(
  ScoreTiming(
    bpm: 120,
    clicksPerBar: 4,
    leadBeats: 2,
    pages: [for (final b in bars) PageTiming(barCount: b)],
  ),
);

/// 소리를 내지 않는 스케줄러. 엔진이 위치를 옮길 때 부르는 것만 받아 넘김.
class _SilentScheduler implements ClickScheduler {
  /// 기준점을 미루지 않아 위치가 옮긴 스팬 시작과 그대로 맞음.
  @override
  Duration get startLead => Duration.zero;

  /// 거둘 예약이 없음.
  @override
  void cancelPending() {}

  /// 클릭을 받지 않음.
  @override
  void load(List<Click> clicks, Duration from) {}

  /// 되감을 예약이 없음.
  @override
  void rewindTo(Duration p) {}

  /// 이 테스트가 부르지 않는 나머지는 실수로 불리면 드러나게 던짐.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('멈춘 동안 0마디 쪽으로 넘김', () {
    test('표지로 돌아가면 화면은 표지, 위치는 곡의 처음', () {
      final r = pausedStep(
        _bars([0, 4, 4]),
        [0, 1, 2],
        viewedPage: 1,
        spanIndex: 1,
        delta: -1,
        twoUp: false,
      );
      expect(r, (seek: 1, restart: true, show: 0));
    });

    test('가운데 빈 쪽은 어느 방향에서 와도 보이고 위치는 다음 실제 쪽의 처음', () {
      final tl = _bars([4, 0, 4]);
      expect(pausedStep(tl, [0, 1, 2], viewedPage: 0, spanIndex: 0, delta: 1, twoUp: false), (
        seek: 2,
        restart: false,
        show: 1,
      ));
      expect(pausedStep(tl, [0, 1, 2], viewedPage: 2, spanIndex: 2, delta: -1, twoUp: false), (
        seek: 2,
        restart: false,
        show: 1,
      ));
    });

    test('끝의 빈 쪽은 곡 끝에 두고, 앞의 빈 쪽으로 돌아가도 실제 쪽으로 되짚지 않음', () {
      final tl = _bars([4, 0, 0]);
      expect(pausedStep(tl, [0, 1, 2], viewedPage: 0, spanIndex: 0, delta: 1, twoUp: false), (
        seek: 2,
        restart: false,
        show: 1,
      ));
      expect(pausedStep(tl, [0, 1, 2], viewedPage: 2, spanIndex: 2, delta: -1, twoUp: false), (
        seek: 2,
        restart: false,
        show: 1,
      ));
    });

    test('표지 뒤 첫 실제 쪽도 곡의 처음이고, 엔진이 알릴 쪽이면 따로 보여 주지 않음', () {
      final tl = _bars([0, 4, 4]);
      expect(pausedStep(tl, [0, 1, 2], viewedPage: 2, spanIndex: 2, delta: -1, twoUp: false), (
        seek: 1,
        restart: true,
        show: null,
      ));
      // 두 장씩이면 표지와 첫 실제 쪽이 한 펼침면이라 엔진이 알리는 쪽이 곧 넘긴 칸
      expect(
        pausedStep(
          _bars([0, 4, 4, 4]),
          [0, 1, 2, 3],
          viewedPage: 2,
          spanIndex: 2,
          delta: -1,
          twoUp: true,
        ),
        (seek: 1, restart: true, show: null),
      );
    });

    test('두 장씩 왼쪽 장이 빈 펼침면으로 돌아가면 그 펼침면의 연주 쪽에 섬', () {
      // 펼침면 {4,5}(스팬 4)에서 이전. 빈 스팬 2를 재생 위치로 주면 엔진이 뒤로 찾아 {0,1}로 건너뜀
      expect(
        pausedStep(
          _bars([4, 4, 0, 4, 4, 4]),
          [0, 1, 2, 3, 4, 5],
          viewedPage: 4,
          spanIndex: 4,
          delta: -1,
          twoUp: true,
        ),
        (seek: 3, restart: false, show: null),
      );
    });

    test('엔진에 적용하면 넘긴 빈 쪽이 화면에 남고 엔진은 다음 실제 쪽에 섬', () {
      final engine = PlaybackEngine(PlaybackClock(() => Duration.zero), _SilentScheduler())
        ..load(_bars([0, 4, 0, 4]));
      int? shown;
      engine.onPageChanged = (p) => shown = p;
      var viewed = 1;
      engine.jumpToSpan(1);
      // 리더의 멈춤 넘김과 같은 순서로 적용함. 엔진이 알린 쪽 위에 show를 덮음
      void step(int delta) {
        final r = pausedStep(
          engine.timeline,
          [0, 1, 2, 3],
          viewedPage: viewed,
          spanIndex: engine.spanIndex.value,
          delta: delta,
          twoUp: false,
        )!;
        if (r.restart) {
          engine.stop();
        } else if (r.seek != null) {
          engine.jumpToSpan(r.seek!);
        }
        viewed = r.show ?? shown!;
      }

      step(-1);
      expect((viewed, engine.spanIndex.value, engine.position), (0, 1, Duration.zero));
      step(1);
      step(1);
      expect((viewed, engine.spanIndex.value), (2, 3));
      step(-1);
      expect((viewed, engine.spanIndex.value), (1, 1));
    });
  });

  group('멈춘 동안 넘긴 쪽의 재생 위치', () {
    test('선형 순서면 그 쪽의 스팬', () {
      expect(spanForSlot(_timeline(), 2, 0, 1, false), 2);
    });

    test('반복 중인 쪽으로 돌아가면 그 반복의 처음', () {
      final tl = _timeline(pages: 2, playOrder: [0, 0, 1, 1]);
      expect(spanForSlot(tl, 0, 3, -1, false), 0);
      expect(spanForSlot(tl, 1, 1, 1, false), 2);
    });

    test('되돌아가기로 같은 쪽을 두 번 지나면 지금 회차에 머묾', () {
      final tl = _timeline(pages: 4, playOrder: [0, 1, 2, 1, 2, 3]);
      expect(spanForSlot(tl, 1, 4, -1, false), 3);
      expect(spanForSlot(tl, 1, 0, 1, false), 1);
    });

    test('앞뒤 회차가 같은 거리면 넘긴 방향의 회차로 감', () {
      // 0쪽 2회차(스팬 2)에서 다음을 누르면 1쪽 1회차(스팬 1)가 아니라 2회차(스팬 3)
      final repeat = _timeline(pages: 2, playOrder: [0, 1, 0, 1]);
      expect(spanForSlot(repeat, 1, 2, 1, false), 3);
      expect(spanForSlot(repeat, 1, 2, -1, false), 1);
      // 1쪽 2회차(스팬 3)에서 다음을 누르면 2쪽 2회차(스팬 4)
      final ds = _timeline(pages: 4, playOrder: [0, 1, 2, 1, 2, 3]);
      expect(spanForSlot(ds, 2, 3, 1, false), 4);
      expect(spanForSlot(ds, 2, 3, -1, false), 2);
    });

    test('넘긴 방향에 회차가 없으면 반대쪽에서 가장 가까운 회차', () {
      final tl = _timeline(pages: 4, playOrder: [0, 1, 2, 1, 3]);
      expect(spanForSlot(tl, 2, 3, 1, false), 2);
    });

    test('지금 스팬이 그 쪽이면 방향과 무관하게 그 회차에 머묾', () {
      final tl = _timeline(pages: 3, playOrder: [0, 1, 2, 1]);
      expect(spanForSlot(tl, 1, 1, 1, false), 1);
    });

    test('연주하지 않는 쪽이면 null', () {
      final tl = _timeline(pages: 3, playOrder: [0, 2]);
      expect(spanForSlot(tl, 1, 0, 1, false), isNull);
    });

    test('두 장씩이면 펼침면 안의 어느 쪽이든 그 펼침면의 첫 스팬', () {
      final tl = _timeline(pages: 4);
      expect(spanForSlot(tl, 2, 0, 1, true), 2);
    });

    test('표시 순서를 따라 넘기고 끝을 넘으면 멈춤', () {
      expect(nextDisplayIndex([2, 0, 1], 0, 1, false), 2);
      expect(nextDisplayIndex([2, 0, 1], 1, 1, false), isNull);
      expect(nextDisplayIndex([0, 1, 2, 3], 1, 1, true), 2);
    });
  });

  group('재생 중 넘김', () {
    test('선행 넘김 뒤 이전을 누르면 시계를 두고 앞 쪽만 보여 줌', () {
      final r = playingStep(
        _timeline(),
        spanIndex: 1,
        now: 9.5,
        delta: -1,
        twoUp: false,
        peeking: false,
        turned: true,
      );
      expect(r.jump, isNull);
      expect(r.show, 0);
      expect(r.peeking, isTrue);
    });

    test('앞 쪽을 보던 중 다음을 누르면 넘어간 쪽으로 돌아오고 시계는 그대로', () {
      final r = playingStep(
        _timeline(),
        spanIndex: 1,
        now: 9.6,
        delta: 1,
        twoUp: false,
        peeking: true,
        turned: true,
      );
      expect(r.jump, isNull);
      expect(r.show, 1);
      expect(r.peeking, isFalse);
    });

    test('쪽 한가운데서 이전을 누르면 앞 스팬 처음으로 옮김', () {
      final r = playingStep(
        _timeline(),
        spanIndex: 1,
        now: 12.0,
        delta: -1,
        twoUp: false,
        peeking: false,
        turned: true,
      );
      expect(r.jump, 0);
      expect(r.peeking, isFalse);
    });

    test('건너뛰어 온 스팬이면 시계가 잠깐 시작 앞에 있어도 이전은 앞 스팬으로 옮김', () {
      // 재생 중 건너뛰기·재생 시작은 출력 지연 보정만큼 시계를 목표 앞에 둠. 선행 구간으로 치면 이전이 사라짐
      final r = playingStep(
        _timeline(),
        spanIndex: 1,
        now: 9.9,
        delta: -1,
        twoUp: false,
        peeking: false,
        turned: false,
      );
      expect(r.jump, 0);
      expect(r.show, isNull);
      expect(r.peeking, isFalse);
    });

    test('가운데 빈 쪽 너머로 선행 넘김한 뒤 이전은 빈 쪽이 아니라 연주 중인 앞 쪽을 보여 줌', () {
      // 스팬 0은 2~10초(넘김 9초), 빈 스팬 1은 10초, 스팬 2는 10~18초. 9초에 스팬 0에서 2로 넘어감
      final tl = _bars([4, 0, 4]);
      PlayingStep back({required bool peeking}) => playingStep(
        tl,
        spanIndex: 2,
        now: 9.5,
        delta: -1,
        twoUp: false,
        peeking: peeking,
        turned: true,
      );
      expect(back(peeking: false), (jump: null, show: 0, peeking: true));
      // 앞 쪽을 보는 중 한 번 더 이전. 빈 쪽을 앞 쪽의 이웃으로 세지 않아 첫 쪽 앞은 갈 곳이 없음
      expect(back(peeking: true), (jump: null, show: null, peeking: true));
      // 두 장씩이면 빈 쪽이 끼인 펼침면 {2,3}에서 앞 펼침면 {0,1}을 보여 줌. 시계를 되감지 않음
      expect(
        playingStep(
          _bars([4, 4, 0, 4, 4, 4]),
          spanIndex: 3,
          now: 17.5,
          delta: -1,
          twoUp: true,
          peeking: false,
          turned: true,
        ),
        (jump: null, show: 1, peeking: true),
      );
    });

    test('재생 중에는 앞뒤 끝의 빈 쪽으로 가지 않음', () {
      // 끝 빈 쪽으로 건너뛰면 곡 끝에 서서 재생이 멈추고 빈 쪽이 뜸
      expect(
        playingStep(
          _bars([4, 4, 0]),
          spanIndex: 1,
          now: 11,
          delta: 1,
          twoUp: false,
          peeking: false,
          turned: false,
        ),
        (jump: null, show: null, peeking: false),
      );
      // 맨 앞 표지도 재생 중에는 세우지 않음. 첫 연주 쪽에서 이전은 표지 없는 곡의 첫 쪽과 같음
      expect(
        playingStep(
          _bars([0, 4, 4]),
          spanIndex: 1,
          now: 5,
          delta: -1,
          twoUp: false,
          peeking: false,
          turned: false,
        ),
        (jump: null, show: null, peeking: false),
      );
    });

    test('갈 곳이 없으면 아무것도 바꾸지 않음', () {
      final r = playingStep(
        _timeline(),
        spanIndex: 1,
        now: 9.5,
        delta: -1,
        twoUp: false,
        peeking: true,
        turned: true,
      );
      expect(r.jump, isNull);
      expect(r.show, isNull);
      expect(r.peeking, isTrue);
    });

    test('두 장씩이면 다른 펼침면이 나올 때까지 건너뜀', () {
      final tl = _timeline(pages: 4);
      expect(nextSpan(tl, 0, 1, true), 2);
      expect(nextSpan(tl, 3, -1, true), 1);
    });
  });

  group('보고 있는 쪽', () {
    test('보낸 이동 중에 뷰어가 지나가며 알린 쪽은 넘김 기준을 바꾸지 않음', () {
      final v = ViewedPage()..go(1);
      v.go(2);
      expect(v.report(1), isFalse);
      expect(v.current, 2);
      expect(v.report(2), isTrue);
      expect(v.current, 2);
    });

    test('목표에 닿은 뒤나 손으로 끌기 시작한 뒤의 보고는 그대로 받음', () {
      final v = ViewedPage()..go(3);
      expect(v.report(3), isTrue);
      expect(v.report(5), isTrue);
      expect(v.current, 5);
      v.go(1);
      v.touched();
      expect(v.report(4), isTrue);
      expect(v.current, 4);
    });
  });
}
