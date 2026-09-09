// 악보 재생 타임라인 계산. bpm·박자·페이지별 마디수로부터 페이지 구간과 클릭 시각을 펼침.
// 순수 함수만 둠. 오디오·UI·DB에 의존하지 않으며 이 앱 타이밍의 유일한 진실.

import 'dart:math' as math;

/// 클릭 하나. accent면 강박(마디 첫 박), subdivision이면 박 사이를 채우는 작은 소리.
class Click {
  final double time;
  final bool accent;
  final bool subdivision;

  const Click(this.time, this.accent, {this.subdivision = false});
}

/// 한 페이지가 화면에 떠 있는 구간. turnAt은 선행 넘김을 반영한 실제 전환 시각.
class PageSpan {
  final int pageIndex;
  final double start;
  final double end;
  final double turnAt;
  final double bpm;
  final int clicksPerBar;
  final int barCount;

  const PageSpan({
    required this.pageIndex,
    required this.start,
    required this.end,
    required this.turnAt,
    required this.bpm,
    required this.clicksPerBar,
    required this.barCount,
  });

  double get duration => end - start;
}

/// 페이지 하나의 타이밍 입력. bpm·clicksPerBar가 null이면 악보 기본값을 상속함.
class PageTiming {
  final int barCount;
  final double? bpm;
  final int? clicksPerBar;

  const PageTiming({required this.barCount, this.bpm, this.clicksPerBar});
}

/// 악보 전체의 타이밍 입력. playOrder가 null이면 0..pages.length-1 선형 재생.
class ScoreTiming {
  final double bpm;
  final int clicksPerBar;
  final int countInBars;
  final double leadBeats;
  final List<PageTiming> pages;
  final List<int>? playOrder;

  const ScoreTiming({
    required this.bpm,
    required this.clicksPerBar,
    required this.pages,
    this.countInBars = 1,
    this.leadBeats = 2,
    this.playOrder,
  });
}

/// 계산 결과. spans는 재생 순서대로이며 pageIndex는 반복 시 중복될 수 있음.
class Timeline {
  final List<PageSpan> spans;
  final List<Click> clicks;
  final double countInEnd;
  final double totalSeconds;

  /// 시작 전에 세는 마디 수. 일시정지 후 재개할 때 되감을 길이로도 씀.
  final int countInBars;

  const Timeline({
    required this.spans,
    required this.clicks,
    required this.countInEnd,
    required this.totalSeconds,
    required this.countInBars,
  });

  /// 주어진 시각이 속한 스팬 인덱스. 카운트인 구간이나 끝을 넘으면 -1.
  int spanIndexAt(double t) {
    for (var i = 0; i < spans.length; i++) {
      if (t >= spans[i].start && t < spans[i].end) return i;
    }
    return -1;
  }
}

/// 다룰 수 있는 템포 범위. 0이나 음수, NaN이 들어오면 한 박이 무한대가 되어
/// 타임라인 전체가 NaN이 되고 secondsToDuration에서 앱이 죽음.
/// DB 값과 AI가 읽은 값이 여기로 들어오므로 계산 전에 접어 둠.
const kMinBpm = 20.0;
const kMaxBpm = 400.0;

/// 한 페이지가 가질 수 있는 최대 마디 수. AI나 손상된 DB가 큰 값을 넣어도
/// 재생이 몇 시간짜리가 되지 않게 접음.
const kMaxBarsPerPage = 999;

/// 한 마디 길이(초). clicksPerBar는 겹박자를 포함한 실제 클릭 수.
double barSeconds(int clicksPerBar, double bpm) => clicksPerBar * 60.0 / safeBpm(bpm);

/// 쓸 수 있는 템포로 접음. 값이 이상하면 기본값 120.
double safeBpm(double bpm) => bpm.isFinite && bpm > 0 ? bpm.clamp(kMinBpm, kMaxBpm) : 120.0;

/// 쓸 수 있는 마디당 클릭 수로 접음. 0이면 마디가 길이 0이 되어 진행이 멈춤.
int safeClicksPerBar(int cpb) => cpb < 1 ? 1 : (cpb > 32 ? 32 : cpb);

/// 선행 넘김 박수를 접음. NaN이면 turnAt이 NaN이 되고 비교가 항상 거짓이라
/// 페이지가 아예 넘어가지 않음. bpm·마디수는 접으면서 이것만 빠져 있었음.
double safeLeadBeats(double beats) => beats.isFinite && beats > 0 ? math.min(beats, 64) : 0;

/// 박자표에서 마디당 클릭 수 기본값을 뽑음. 8분의 6/9/12박은 점4분 기준으로 묶음.
int defaultClicksPerBar(int num, int den) {
  if (den == 8 && num % 3 == 0 && num > 3) return num ~/ 3;
  return num;
}

/// 페이지 구간과 클릭 시각을 한 번에 펼침. 재생 중에는 이 결과만 읽고 재계산하지 않음.
Timeline buildTimeline(ScoreTiming s) {
  // 값이 이상하면 던지지 않고 접음. 여기 들어오는 값의 출처가 DB와 AI라
  // 디버그에서만 죽는 assert는 진단이 아니라 재현 어려운 크래시가 됨.
  final order = s.playOrder ?? List<int>.generate(s.pages.length, (i) => i);
  final clicks = <Click>[];
  final spans = <PageSpan>[];
  var t = 0.0;

  // 카운트인은 첫 재생 페이지의 템포를 따름. 페이지가 없으면 악보 기본값.
  final headBpm = safeBpm(order.isEmpty ? s.bpm : (s.pages[order.first].bpm ?? s.bpm));
  final headCpb = safeClicksPerBar(
    order.isEmpty ? s.clicksPerBar : (s.pages[order.first].clicksPerBar ?? s.clicksPerBar),
  );
  final headBeat = 60.0 / headBpm;
  final countInBars = s.countInBars < 0 ? 0 : s.countInBars;
  for (var i = 0; i < countInBars * headCpb; i++) {
    clicks.add(Click(t, i % headCpb == 0));
    t += headBeat;
  }
  final countInEnd = t;

  final leadBeats = safeLeadBeats(s.leadBeats);
  for (final idx in order) {
    final p = s.pages[idx];
    final bpm = safeBpm(p.bpm ?? s.bpm);
    final cpb = safeClicksPerBar(p.clicksPerBar ?? s.clicksPerBar);
    final beat = 60.0 / bpm;
    final start = t;
    // 손상된 값이 들어와도 재생이 몇 시간짜리가 되지 않게 접음
    final bars = p.barCount.clamp(0, kMaxBarsPerPage);
    for (var bar = 0; bar < bars; bar++) {
      for (var c = 0; c < cpb; c++) {
        clicks.add(Click(t, c == 0));
        t += beat;
      }
    }
    // 선행 넘김이 페이지 길이보다 길면 페이지가 아예 안 보이므로 start로 막음.
    final turnAt = math.max(start, t - leadBeats * beat);
    spans.add(
      PageSpan(
        pageIndex: idx,
        start: start,
        end: t,
        turnAt: turnAt,
        bpm: bpm,
        clicksPerBar: cpb,
        barCount: bars,
      ),
    );
  }

  return Timeline(
    spans: spans,
    clicks: clicks,
    countInEnd: countInEnd,
    totalSeconds: t,
    countInBars: countInBars,
  );
}

/// 재생 위치에 맞는 스팬 인덱스를 앞으로만 전진시켜 찾음.
/// 프레임이 밀려 여러 페이지를 한 번에 지나쳐도 따라잡음. 되감기는 spanIndexAt을 씀.
int advanceSpan(Timeline tl, int current, double nowSec) {
  var i = current < 0 ? 0 : current;
  while (i + 1 < tl.spans.length && nowSec >= tl.spans[i].turnAt) {
    i++;
  }
  return i;
}

/// 초 단위 실수를 Duration으로. 타임라인은 double, 오디오·UI는 Duration이라 경계에서만 씀.
Duration secondsToDuration(double s) => Duration(microseconds: (s * 1e6).round());

/// 메트로놈 화면용 클릭 배열. 악보가 아니라 고정 템포를 계속 치는 용도라 마디 수만큼 펼침.
/// subdivision은 한 박을 몇 등분할지. 1이면 분할음 없음, 2는 8분, 3은 셋잇단, 4는 16분.
List<Click> metronomeClicks({
  required double bpm,
  required int clicksPerBar,
  required int bars,
  int subdivision = 1,
}) {
  final beat = 60.0 / safeBpm(bpm);
  final step = beat / (subdivision < 1 ? 1 : subdivision);
  final out = <Click>[];
  var t = 0.0;
  final cpb = safeClicksPerBar(clicksPerBar);
  final div = subdivision < 1 ? 1 : subdivision;
  for (var bar = 0; bar < bars; bar++) {
    for (var c = 0; c < cpb; c++) {
      for (var d = 0; d < div; d++) {
        out.add(Click(t, d == 0 && c == 0, subdivision: d != 0));
        t += step;
      }
    }
  }
  return out;
}
