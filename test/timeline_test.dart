// 타임라인 계산 검증. 페이지 체류 시간과 클릭 시각이 어긋나면 앱의 존재 이유가 무너지므로
// 겹박자·템포 오버라이드·반복·선행 넘김 경계를 전부 고정해 둠.

import 'package:baton/score/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

ScoreTiming score({
  double bpm = 120,
  int clicksPerBar = 4,
  int countInBars = 0,
  double leadBeats = 0,
  required List<PageTiming> pages,
  List<int>? playOrder,
}) => ScoreTiming(
  bpm: bpm,
  clicksPerBar: clicksPerBar,
  countInBars: countInBars,
  leadBeats: leadBeats,
  pages: pages,
  playOrder: playOrder,
);

void main() {
  test('4/4 120bpm 4마디 페이지는 8초', () {
    final t = buildTimeline(score(pages: const [PageTiming(barCount: 4)]));
    expect(t.spans.single.start, 0);
    expect(t.spans.single.end, closeTo(8.0, 1e-9));
    expect(t.totalSeconds, closeTo(8.0, 1e-9));
    expect(t.clicks.length, 16);
    expect(t.clicks[0].accent, isTrue);
    expect(t.clicks[1].accent, isFalse);
    expect(t.clicks[4].accent, isTrue);
    expect(t.clicks[4].time, closeTo(2.0, 1e-9));
  });

  test('카운트인 1마디는 첫 페이지를 뒤로 밀고 클릭도 넣음', () {
    final t = buildTimeline(score(countInBars: 1, pages: const [PageTiming(barCount: 4)]));
    expect(t.countInEnd, closeTo(2.0, 1e-9));
    expect(t.spans.single.start, closeTo(2.0, 1e-9));
    expect(t.spans.single.end, closeTo(10.0, 1e-9));
    expect(t.clicks.length, 20);
    expect(t.clicks.first.time, 0);
  });

  test('겹박자 기본 클릭 수', () {
    expect(defaultClicksPerBar(4, 4), 4);
    expect(defaultClicksPerBar(3, 4), 3);
    expect(defaultClicksPerBar(6, 8), 2);
    expect(defaultClicksPerBar(9, 8), 3);
    expect(defaultClicksPerBar(12, 8), 4);
    expect(defaultClicksPerBar(3, 8), 3, reason: '3/8은 묶지 않고 그대로 셈');
    expect(defaultClicksPerBar(7, 8), 7);
  });

  test('6/8 점4분 100bpm 2마디는 2.4초', () {
    final t = buildTimeline(
      score(
        bpm: 100,
        clicksPerBar: defaultClicksPerBar(6, 8),
        pages: const [PageTiming(barCount: 2)],
      ),
    );
    expect(t.spans.single.end, closeTo(2.4, 1e-9));
    expect(t.clicks.length, 4);
  });

  test('페이지별 bpm·박자 오버라이드가 상위를 덮음', () {
    final t = buildTimeline(
      score(
        pages: const [
          PageTiming(barCount: 2), // 120bpm 4/4 -> 4초
          PageTiming(barCount: 2, bpm: 60), // 60bpm 4/4  -> 8초
          PageTiming(barCount: 2, bpm: 60, clicksPerBar: 3), // 60bpm 3박 -> 6초
        ],
      ),
    );
    expect(t.spans[0].duration, closeTo(4.0, 1e-9));
    expect(t.spans[1].duration, closeTo(8.0, 1e-9));
    expect(t.spans[2].duration, closeTo(6.0, 1e-9));
    expect(t.totalSeconds, closeTo(18.0, 1e-9));
    expect(t.spans[1].bpm, 60);
  });

  test('playOrder는 페이지를 재생 순서대로 펼치고 인덱스를 반복 허용', () {
    final t = buildTimeline(
      score(
        pages: const [PageTiming(barCount: 1), PageTiming(barCount: 2)],
        playOrder: const [0, 1, 1, 0],
      ),
    );
    expect(t.spans.map((s) => s.pageIndex).toList(), [0, 1, 1, 0]);
    expect(t.spans[1].duration, closeTo(4.0, 1e-9));
    expect(t.totalSeconds, closeTo(2 + 4 + 4 + 2, 1e-9));
  });

  test('선행 넘김은 페이지 끝에서 leadBeats만큼 당김', () {
    final t = buildTimeline(score(leadBeats: 2, pages: const [PageTiming(barCount: 4)]));
    expect(t.spans.single.turnAt, closeTo(8.0 - 1.0, 1e-9));
  });

  test('선행 넘김이 페이지보다 길면 start로 막아 페이지를 건너뛰지 않음', () {
    final t = buildTimeline(score(leadBeats: 99, pages: const [PageTiming(barCount: 1)]));
    expect(t.spans.single.turnAt, t.spans.single.start);
  });

  test('spanIndexAt은 카운트인 구간과 끝을 -1로 구분', () {
    final t = buildTimeline(
      score(countInBars: 1, pages: const [PageTiming(barCount: 1), PageTiming(barCount: 1)]),
    );
    expect(t.spanIndexAt(1.0), -1, reason: '카운트인 중');
    expect(t.spanIndexAt(2.0), 0);
    expect(t.spanIndexAt(3.9), 0);
    expect(t.spanIndexAt(4.0), 1);
    expect(t.spanIndexAt(99.0), -1);
  });

  test('페이지가 없으면 카운트인만 남고 스팬은 비어 있음', () {
    final t = buildTimeline(score(countInBars: 2, pages: const []));
    expect(t.spans, isEmpty);
    expect(t.clicks.length, 8);
    expect(t.totalSeconds, closeTo(4.0, 1e-9));
  });

  _advanceTests();
  _metronomeTests();
}

void _advanceTests() {
  test('선행 넘김 시각을 넘기면 다음 스팬으로 전진', () {
    final t = buildTimeline(
      score(leadBeats: 2, pages: const [PageTiming(barCount: 2), PageTiming(barCount: 2)]),
    );
    // 4/4 120bpm 2마디 = 4초, lead 2박 = 1초 -> turnAt 3.0
    expect(advanceSpan(t, 0, 2.9), 0);
    expect(advanceSpan(t, 0, 3.0), 1);
    expect(advanceSpan(t, 0, 3.5), 1);
  });

  test('프레임이 밀려 여러 페이지를 지나쳐도 따라잡음', () {
    final t = buildTimeline(
      score(
        pages: const [
          PageTiming(barCount: 1),
          PageTiming(barCount: 1),
          PageTiming(barCount: 1),
          PageTiming(barCount: 1),
        ],
      ),
    );
    expect(advanceSpan(t, 0, 6.5), 3, reason: '한 번에 3장 전진');
  });

  test('마지막 스팬에서는 더 전진하지 않음', () {
    final t = buildTimeline(score(pages: const [PageTiming(barCount: 1)]));
    expect(advanceSpan(t, 0, 999.0), 0);
  });

  test('카운트인 중에는 첫 스팬에 머무름', () {
    final t = buildTimeline(
      score(countInBars: 1, pages: const [PageTiming(barCount: 2), PageTiming(barCount: 2)]),
    );
    expect(advanceSpan(t, 0, 0.5), 0);
    expect(advanceSpan(t, 0, 1.9), 0);
  });
}

void _metronomeTests() {
  test('메트로놈 클릭은 마디 첫 박만 강박', () {
    final c = metronomeClicks(bpm: 120, clicksPerBar: 4, bars: 2);
    expect(c.length, 8);
    expect(c.map((x) => x.accent), [true, false, false, false, true, false, false, false]);
    expect(c[4].time, closeTo(2.0, 1e-9));
    expect(c.every((x) => !x.subdivision), isTrue);
  });

  test('분할음은 박 사이를 채우고 subdivision으로 표시됨', () {
    final c = metronomeClicks(bpm: 60, clicksPerBar: 2, bars: 1, subdivision: 2);
    expect(c.length, 4, reason: '2박 × 8분');
    expect(c.map((x) => x.time), [0.0, 0.5, 1.0, 1.5]);
    expect(c.map((x) => x.subdivision), [false, true, false, true]);
    expect(c.first.accent, isTrue);
  });

  test('셋잇단은 한 박을 셋으로 나눔', () {
    final c = metronomeClicks(bpm: 60, clicksPerBar: 1, bars: 1, subdivision: 3);
    expect(c.length, 3);
    expect(c[1].time, closeTo(1 / 3, 1e-9));
    expect(c[2].time, closeTo(2 / 3, 1e-9));
  });

  group('손상된 값 방어', () {
    /// DB나 AI가 넣은 값이 그대로 계산에 들어가면 앱이 죽으므로 접히는지 확인함.
    test('bpm이 0이면 기본값으로 접혀 타임라인이 유한함', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 0,
          clicksPerBar: 4,
          countInBars: 0,
          pages: [PageTiming(barCount: 2)],
        ),
      );
      expect(t.totalSeconds.isFinite, isTrue);
      expect(t.totalSeconds, closeTo(barSeconds(4, 120) * 2, 1e-9));
    });

    test('페이지 bpm이 음수여도 죽지 않음', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 4,
          countInBars: 0,
          pages: [PageTiming(barCount: 1, bpm: -60)],
        ),
      );
      expect(t.totalSeconds.isFinite, isTrue);
      expect(t.spans.single.bpm, 120);
    });

    test('마디당 클릭이 0이면 1로 접힘', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 0,
          countInBars: 0,
          pages: [PageTiming(barCount: 1)],
        ),
      );
      expect(t.spans.single.clicksPerBar, 1);
      expect(t.clicks.length, 1);
    });

    test('터무니없는 마디수는 상한으로 접힘', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 4,
          countInBars: 0,
          pages: [PageTiming(barCount: 100000)],
        ),
      );
      expect(t.spans.single.barCount, kMaxBarsPerPage);
    });

    test('마디수 0인 표지는 길이 0으로 지나감', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 4,
          countInBars: 0,
          pages: [PageTiming(barCount: 0), PageTiming(barCount: 2)],
        ),
      );
      expect(t.spans.first.duration, 0);
      expect(t.totalSeconds, closeTo(barSeconds(4, 120) * 2, 1e-9));
    });

    test('선행 넘김이 NaN이면 0으로 접혀 페이지가 넘어감', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 4,
          countInBars: 0,
          leadBeats: double.nan,
          pages: [PageTiming(barCount: 1), PageTiming(barCount: 1)],
        ),
      );
      expect(t.spans.first.turnAt.isFinite, isTrue);
      // turnAt이 NaN이면 비교가 항상 거짓이라 전진이 멈춤
      expect(advanceSpan(t, 0, t.spans.first.end), 1);
    });

    test('선행 넘김이 음수여도 페이지 끝을 넘지 않음', () {
      final t = buildTimeline(
        const ScoreTiming(
          bpm: 120,
          clicksPerBar: 4,
          countInBars: 0,
          leadBeats: -8,
          pages: [PageTiming(barCount: 2)],
        ),
      );
      expect(t.spans.single.turnAt, t.spans.single.end);
    });
  });
}
