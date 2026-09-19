// 넘김 입력과 재생 위치 사이의 계산. 탭·페달이 어느 쪽·어느 스팬으로 가는지와 보고 있는 쪽을 여기서만 정함.
// 화면·엔진·뷰어 없이 표시 순서·타임라인·쪽 번호만 받아 따로 검증함.

import '../score/timeline.dart';

/// 표시 인덱스가 속한 칸의 첫 인덱스. 두 장씩이면 펼침면의 왼쪽 장.
int slotOf(int displayIndex, bool twoUp) => twoUp ? displayIndex - displayIndex % 2 : displayIndex;

/// 멈춘 동안 한 번 넘겼을 때 갈 표시 인덱스. 물리 인덱스가 아니라 표시 순서를 따라가 숨긴 쪽으로 빠지지 않음.
/// 목록에 없는 쪽을 보고 있으면 방향에 맞는 끝에서 다시 시작함. 끝을 넘으면 null.
int? nextDisplayIndex(List<int> pageOrder, int currentPage, int delta, bool twoUp) {
  final step = delta * (twoUp ? 2 : 1);
  final found = pageOrder.indexOf(currentPage);
  var slot = found < 0 ? (step > 0 ? -1 : pageOrder.length) : found;
  if (twoUp && found >= 0) slot -= slot % 2;
  final next = slot + step;
  return next < 0 || next >= pageOrder.length ? null : next;
}

/// 재생 중 한 번 눌렀을 때 갈 스팬. 갈 곳이 없으면 -1.
/// 자동 넘김과 같은 이웃(playedNeighbor)을 따라 0마디 스팬을 건너뜀. 뒤에 끝의 빈 쪽만 남으면 -1.
/// 곡 끝의 빈 쪽으로 건너뛰지 않으므로 재생이 멈추지 않음. 두 장씩 볼 때는 지금과 다른 펼침면이 나올 때까지 건너뜀.
/// 반복이 있으면 스팬 인덱스와 표시 순서의 홀짝이 어긋나므로 표시 순서로 짝을 맞춤.
int nextSpan(Timeline tl, int current, int delta, bool twoUp) {
  final from = slotOf(tl.spans[current].pageIndex, twoUp);
  var i = current;
  do {
    i = tl.playedNeighbor(i, step: delta);
  } while (i >= 0 && twoUp && slotOf(tl.spans[i].pageIndex, true) == from);
  return i;
}

/// 표시 칸을 연주하는 스팬 가운데 넘긴 방향(delta)에서 지금 스팬에 가장 가까운 회차의 첫 스팬.
/// 연주하지 않는 칸이면 null. 멈춘 동안 넘긴 쪽을 재생 위치로 삼을 때 씀. 반복 중인 쪽이면 그 반복의
/// 처음으로 가고, 되돌아가기가 있어 같은 쪽을 여러 번 지나면 넘긴 방향의 회차로 감.
/// 방향을 보지 않으면 앞뒤 회차가 같은 거리일 때 앞 회차를 골라 '다음'이 재생 위치를 뒤로 옮김.
/// 그 방향에 회차가 없을 때만 반대쪽에서 가장 가까운 회차로 물러섬.
int? spanForSlot(Timeline tl, int slot, int current, int delta, bool twoUp) {
  int? best;
  var bestAhead = false;
  for (var i = 0; i < tl.spans.length; i++) {
    if (slotOf(tl.spans[i].pageIndex, twoUp) != slot) continue;
    final ahead = (i - current) * delta >= 0;
    if (best == null ||
        (ahead && !bestAhead) ||
        (ahead == bestAhead && (i - current).abs() < (best - current).abs())) {
      best = i;
      bestAhead = ahead;
    }
  }
  if (best == null) return null;
  var first = best;
  while (first > 0 && slotOf(tl.spans[first - 1].pageIndex, twoUp) == slot) {
    first--;
  }
  return first;
}

/// 멈춘 동안 넘김 입력의 결과. seek은 재생 위치로 삼을 스팬이고 null이면 위치를 둠.
/// restart면 seek 대신 곡의 처음(카운트인부터)으로 되돌림. show는 엔진이 알려 올 쪽과 달라 따로 보여 줄 표시 인덱스.
typedef PausedStep = ({int? seek, bool restart, int? show});

/// 멈춘 동안 넘김 입력을 해석함. 표시 순서로 다음 칸을 고르고 재생 위치를 spanForSlot의 회차로 옮김.
/// 0마디 쪽은 엔진이 서지 않으므로 위치를 연주 순서상 다음 실제 스팬의 처음(없으면 곡 끝)에 두고 화면만 그 쪽을 보여 줌.
/// 위치가 첫 실제 스팬이면 곡의 처음으로 되돌림. 끝을 넘으면 null.
PausedStep? pausedStep(
  Timeline? tl,
  List<int> pageOrder, {
  required int viewedPage,
  required int spanIndex,
  required int delta,
  required bool twoUp,
}) {
  final next = nextDisplayIndex(pageOrder, viewedPage, delta, twoUp);
  if (next == null) return null;
  final slot = slotOf(next, twoUp);
  final span = tl == null ? null : spanForSlot(tl, slot, spanIndex, delta, twoUp);
  if (span == null) return (seek: null, restart: false, show: next);
  final played = tl!.playedSpan(span);
  // 엔진은 실제 스팬이나 끝의 빈 스팬에만 섬. 끝의 빈 쪽이면 마지막 스팬(곡 끝)을 줌.
  // 마지막 스팬은 지금 위치보다 앞일 수 없어 엔진이 앞의 실제 쪽으로 되짚지 않음
  final seek = played >= 0 ? played : tl.spans.length - 1;
  final engineShows = slotOf(tl.spans[seek].pageIndex, twoUp) == slot;
  return (seek: seek, restart: seek == tl.playedSpan(0), show: engineShows ? null : next);
}

/// 재생 중 넘김 입력의 결과. jump는 시계를 옮길 스팬, show는 시계를 두고 쪽만 보여 줄 스팬.
/// peeking은 선행 넘김 뒤 앞 쪽을 다시 보는 중인지. 둘 다 null이면 아무것도 하지 않음.
typedef PlayingStep = ({int? jump, int? show, bool peeking});

/// 재생 중 넘김 입력을 해석함. 선행 넘김으로 이미 넘어간 뒤 이전을 누르면 시계는 두고 앞 쪽만 다시 보여 줌.
/// 연주는 아직 앞 쪽에 있으므로 시계를 그 쪽 처음으로 되감으면 연주보다 한 쪽이 늦어짐.
/// 그 상태에서 다음을 누르면 넘어간 쪽으로 돌아오고, 그 밖에는 스팬 단위로 시계를 옮김.
/// turned는 지금 스팬에 엔진의 넘김으로 들어왔는지. 건너뛰기·재생 시작 직후 시계가 잠깐 스팬 시작
/// 앞에 머물러도 선행 구간으로 치지 않아, 그때의 이전이 쪽만 보여 주고 사라지지 않게 함.
/// 아직 연주 중인 앞 쪽은 0마디 스팬을 건너뛴 앞 이웃. 가운데 빈 쪽은 선행 넘김이 건너뛰었으므로 보여 주지 않음.
PlayingStep playingStep(
  Timeline tl, {
  required int spanIndex,
  required double now,
  required int delta,
  required bool twoUp,
  required bool peeking,
  required bool turned,
}) {
  final prev = tl.playedNeighbor(spanIndex, step: -1);
  final inLead = turned && prev >= 0 && now < tl.spans[spanIndex].start;
  if (delta > 0 && peeking) return (jump: null, show: spanIndex, peeking: false);
  if (delta < 0 &&
      inLead &&
      !peeking &&
      slotOf(tl.spans[prev].pageIndex, twoUp) != slotOf(tl.spans[spanIndex].pageIndex, twoUp)) {
    return (jump: null, show: prev, peeking: true);
  }
  final target = nextSpan(tl, peeking && inLead ? prev : spanIndex, delta, twoUp);
  if (target < 0) return (jump: null, show: null, peeking: peeking);
  return (jump: target, show: null, peeking: false);
}

/// 보고 있는 물리 쪽. 넘김이 이 값에서 다음 쪽을 셈하므로 뷰어가 이동하며 지나가는 쪽에 흔들리면 안 됨.
/// 보낸 이동이 끝나기 전에 뷰어가 알려 오는 중간 쪽은 버림. 그대로 받으면 빠르게 연속으로 넘길 때
/// 목표가 지나가던 쪽으로 되돌아가 한 번이 빠짐. 손으로 끌기 시작하면 다시 뷰어의 보고를 따름.
class ViewedPage {
  /// 지금 보는(또는 가는 중인) 물리 쪽 인덱스.
  int current = 0;

  /// 보낸 이동의 목표. 뷰어가 여기 닿았다고 알리거나 손이 끼어들 때까지 다른 보고를 버림.
  int? _target;

  /// 이동을 보냄. 목표를 지금 쪽으로 삼고 도착 전까지 다른 보고를 무시함.
  void go(int page) {
    current = page;
    _target = page;
  }

  /// 뷰어가 알린 지금 쪽을 받음. 이동 중에 지나가는 쪽이면 버리고 false.
  bool report(int page) {
    if (_target != null && page != _target) return false;
    _target = null;
    current = page;
    return true;
  }

  /// 손으로 끌거나 확대하기 시작함. 이후 보고는 손이 옮긴 자리라 그대로 받음.
  void touched() => _target = null;
}
