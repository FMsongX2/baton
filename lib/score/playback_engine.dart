// 클럭·클릭 예약·페이지 전환을 한 덩어리로 굴림. 시간 판단은 전부 타임라인과 클럭에 맡기고
// 여기서는 상태 전이와 알림만 다룸. tick은 화면의 Ticker가 매 프레임 부름.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../metronome/click_scheduler.dart';
import '../metronome/clock.dart';
import 'timeline.dart';

class PlaybackEngine {
  /// 전화·이어폰 빠짐 같은 오디오 사건이 오면 스스로 멈춤. 화면이 따로 챙기지 않아도 됨.
  PlaybackEngine(this.clock, this.scheduler) {
    _halts = clock.halts.listen((_) => pause());
  }

  final PlaybackClock clock;
  final ClickScheduler scheduler;
  late final StreamSubscription<void> _halts;

  Timeline? _timeline;

  /// 재생 순서상 현재 위치. 페이지 인덱스가 아니라 스팬 인덱스라 반복 구간을 구분함.
  final spanIndex = ValueNotifier<int>(0);
  final isPlaying = ValueNotifier<bool>(false);

  /// 매 프레임 바뀌는 값. 화면 전체를 다시 빌드하지 않도록 알림 대상을 좁혀 둠.
  final progressValue = ValueNotifier<double>(0);
  final countIn = ValueNotifier<int?>(null);

  /// 보여줄 페이지가 바뀌면 물리 페이지 인덱스로 부름.
  void Function(int pageIndex)? onPageChanged;

  /// 마지막 페이지까지 끝나면 부름.
  void Function()? onFinished;

  Timeline? get timeline => _timeline;

  /// 현재 재생 위치. 시작·건너뛰기 직후 잠깐은 음수이거나 목표 지점 앞에 있음.
  Duration get position => clock.position;

  /// 시각 판정용 재생 위치(초). µs 반올림으로 경계 바로 앞에 떨어진 값을 경계로 붙임.
  double get _now => position.inMicroseconds / 1e6 + kTimeEpsilon;

  /// 0~1 진행률. 타임라인이 없으면 0.
  double get progress {
    final t = _timeline;
    if (t == null || t.totalSeconds <= 0) return 0;
    return (position.inMicroseconds / 1e6 / t.totalSeconds).clamp(0.0, 1.0);
  }

  /// 카운트인 중이면 남은 클릭 수, 아니면 null. 큰 숫자 카운트다운에 씀.
  /// 지금 울리고 있는 박도 아직 남은 것으로 세야 4,3,2,1로 끝남.
  /// 멈춰 있을 때는 셀 것이 없음. 그냥 두면 악보를 열자마자 큰 숫자가 화면을 덮음.
  int? get countInRemaining {
    final t = _timeline;
    if (t == null || !isPlaying.value) return null;
    final now = _now;
    if (now < _countInFrom || now >= _countInUntil) return null;
    var n = 0;
    for (var i = _countInFirst; i < t.clicks.length; i++) {
      if (t.clicks[i].time >= _countInUntil) break;
      if (t.clicks[i].time > now - _countInGrace) n++;
    }
    return n;
  }

  /// 카운트인 숫자를 보여 줄 구간의 끝. 처음 시작이면 타임라인의 카운트인 끝,
  /// 재개라면 되돌아온 지점이 됨.
  double _countInUntil = 0;

  /// 카운트인 숫자를 보여 주기 시작할 시각. 재개 때 되감은 지점.
  double _countInFrom = 0;

  /// 그 구간의 첫 클릭 인덱스. 매 프레임 전체 클릭을 훑지 않도록 구간을 정할 때 한 번만 찾음.
  /// 곡 뒤쪽에서 재개하면 앞의 수천 개를 매번 지나치게 됨.
  int _countInFirst = 0;

  /// 시각 t 이상인 첫 클릭 인덱스. 클릭 배열이 시간순이라 이분 탐색으로 찾음.
  int _clickIndexAt(double t) {
    final clicks = _timeline!.clicks;
    var lo = 0;
    var hi = clicks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (clicks[mid].time < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 기준점 대기가 향하는 위치. 시작·재개·건너뛰기가 기준점을 미래로 잡으면 그동안 위치가 이보다 앞에 있음.
  Duration _anchor = Duration.zero;

  /// 방금 지나간 박도 남은 것으로 세는 여유. 한 박보다 짧게 잡아 두 개가 겹치지 않게 함.
  static const _countInGrace = 0.08;

  /// 새 악보를 걸고 처음으로 되돌림. 재생 중이면 멈춤.
  /// 클릭 배열을 스케줄러에 넘기는 유일한 지점. 빠뜨리면 페이지만 넘어가고 소리가 나지 않음.
  void load(Timeline t) {
    _timeline = t;
    scheduler.load(t.clicks, Duration.zero);
    stop();
  }

  /// 현재 위치부터 재생함. 중간에서 다시 시작하면 카운트인 마디만큼 되감아
  /// 연주자가 다시 들어올 지점을 셀 수 있게 함. 멈춘 동안 화면이 딴 쪽에 가 있었어도
  /// 재생이 시작되는 위치의 페이지로 되돌림. 시작 위치를 기준점 대기가 향할 위치로 남김.
  void play() {
    final t = _timeline;
    if (t == null || isPlaying.value) return;
    if (_now >= t.totalSeconds) {
      // 끝까지 간 뒤 다시 누르면 처음부터. 그대로 두면 한 프레임 만에 다시 멈춤
      stop();
    } else if (position > Duration.zero) {
      _rewindForResume();
    }
    if (t.spans.isNotEmpty) {
      final now = _now;
      _showSpan(advanceSpan(t, math.max(0, t.spanIndexAt(now)), now));
    }
    _anchor = position;
    clock.start(scheduler.startLead);
    isPlaying.value = true;
  }

  /// 재개 지점 앞의 마디선까지 되감고 그 구간을 카운트인으로 표시함.
  /// 마디선은 타임라인의 강박 클릭으로 찾음. 템포·박자가 다른 앞 페이지나 카운트인까지 물러나도
  /// 그 구간 자신의 마디 길이로 셈. 되감은 구간의 클릭은 타임라인에 이미 있으므로 따로 만들지 않음.
  /// 이미 되감은 카운트인의 시작에 서 있으면 그 카운트인을 다시 쓰고 더 물러서지 않음.
  void _rewindForResume() {
    final t = _timeline!;
    if (t.countInBars <= 0) return;
    // 재개 기준점 대기 중에 멈추면 pause가 카운트인 시작으로 접어 둠. 여기서 또 세면 소리 한 번 없이
    // 재개할 때마다 한 마디씩 물러섬. 건너뛰기는 창을 비우므로 목표 마디선에서 새로 되감음
    if (_countInUntil > _countInFrom && position == secondsToDuration(_countInFrom)) return;
    final now = _now;
    // 카운트인 구간이거나 곡이 끝난 뒤면 되감을 기준 마디가 없음
    if (t.spanIndexAt(now) < 0) return;

    final clicks = t.clicks;
    // 멈춘 자리 이하의 마지막 강박이 다시 들어올 마디선. 첫 클릭은 항상 강박
    var i = _clickIndexAt(now) - 1;
    while (i > 0 && !clicks[i].accent) {
      i--;
    }
    final entry = i;
    for (var bars = 0; bars < t.countInBars && i > 0; bars++) {
      i--;
      while (i > 0 && !clicks[i].accent) {
        i--;
      }
    }

    _countInFrom = clicks[i].time;
    _countInUntil = clicks[entry].time;
    _countInFirst = i;
    _seekTo(secondsToDuration(_countInFrom));
  }

  /// 처음으로 되돌리고 멈춤.
  void stop() {
    scheduler.cancelPending();
    clock.reset();
    isPlaying.value = false;
    final t = _timeline;
    if (t == null) {
      _notifyPosition();
      return;
    }
    _countInFrom = 0;
    _countInUntil = t.countInEnd;
    _countInFirst = 0;
    spanIndex.value = 0;
    scheduler.rewindTo(Duration.zero);
    _notifyPosition();
    // 표지처럼 0마디인 쪽이 앞에 있으면 건너뛰어 카운트인 동안 첫 연주 페이지가 보이게 함
    if (t.spans.isNotEmpty) _showSpan(math.max(0, t.playedSpan(0)));
  }

  /// 위치를 남긴 채 멈춤. 이미 예약된 클릭은 거둬 멈춘 뒤에 소리가 남지 않게 함.
  /// 거둔 클릭을 재개가 다시 예약하도록 커서도 멈춘 자리로 되돌림. 카운트인 0마디 곡이나
  /// 카운트인·시작 대기 중에 멈춘 재개는 되감기(seek)를 타지 않아 여기서 맞추지 않으면 첫 클릭이 빠짐.
  /// 기준점 대기 중에 멈추면 대기가 향하던 위치에 멈춘 것으로 접음. 그 사이 울린 박이 없고, 목표 앞에 두면
  /// 재개 되감기가 앞 스팬의 마디선을 기준으로 삼아 한 마디 더 물러서고 앞 쪽을 보여 줌.
  void pause() {
    if (!isPlaying.value) return;
    clock.pause();
    if (clock.position < _anchor) clock.seek(_anchor);
    scheduler.cancelPending();
    scheduler.rewindTo(clock.position);
    isPlaying.value = false;
    _notifyPosition();
  }

  /// 특정 스팬의 시작으로 건너뜀. 카운트인은 다시 하지 않음.
  /// 0마디 쪽에는 서지 않음. 뒤로 건너뛰는 중이면 더 앞의 실제 쪽으로, 아니면 다음 실제 쪽으로 감.
  /// 끝의 빈 쪽처럼 갈 실제 쪽이 없으면 고른 쪽에 섬.
  void jumpToSpan(int index) {
    final t = _timeline;
    if (t == null || index < 0 || index >= t.spans.length) return;
    var target = index < spanIndex.value ? t.playedSpan(index, step: -1) : -1;
    if (target < 0) target = t.playedSpan(index);
    if (target < 0) target = index;
    // 되감은 구간이 남아 있으면 카운트인 숫자가 잘못 뜨므로 함께 지움.
    // 재생 중 건너뛰면 기준점이 미래로 잡혀 잠깐 목표 앞에 머무는데, 그때 숫자가 뜨지 않게 창을 비움
    _countInFrom = 0;
    _countInUntil = 0;
    _countInFirst = 0;
    _seekTo(secondsToDuration(t.spans[target].start));
    _showSpan(target);
  }

  /// 시간축을 옮기고 예약을 다시 맞춤. 되감기·건너뛰기가 공통으로 씀.
  /// 재생 중이면 기준점을 미래로 잡아 새 지점의 첫 강박이 버려지지 않게 하고, 대기가 향할 위치로 at을 남김.
  void _seekTo(Duration at) {
    _anchor = at;
    scheduler.cancelPending();
    clock.seek(at, scheduler.startLead);
    scheduler.rewindTo(at);
    _notifyPosition();
  }

  /// 스팬 i를 현재 스팬으로 두고 그 페이지를 무조건 알림. 같은 스팬이어도 화면이 딴 쪽에 가 있으면 되돌림.
  void _showSpan(int i) {
    spanIndex.value = i;
    onPageChanged?.call(_timeline!.spans[i].pageIndex);
  }

  /// 매 프레임 호출. 클릭을 예약하고 넘길 때가 되면 페이지를 넘김.
  void tick() {
    if (!isPlaying.value) return;
    final t = _timeline;
    if (t == null) return;

    scheduler.pump();
    _notifyPosition();

    final now = _now;
    if (t.spans.isNotEmpty) {
      // 되감기·건너뛰기는 play·jumpToSpan이 스팬을 맞춰 두므로 앞으로만 감.
      // 기준점을 미래로 잡은 직후엔 위치가 목표 앞에 있어 뒤로 되짚으면 앞 페이지로 깜빡임
      final next = advanceSpan(t, spanIndex.value, now);
      if (next != spanIndex.value) _showSpan(next);
    }
    if (now >= t.totalSeconds) {
      pause();
      onFinished?.call();
    }
  }

  /// 진행률과 카운트인 숫자를 지금 위치로 갱신함.
  /// 프레임 콜백은 재생 중에만 도므로 멈춘 뒤·건너뛴 뒤에도 화면이 맞도록 여기서 알림.
  void _notifyPosition() {
    progressValue.value = progress;
    countIn.value = countInRemaining;
  }

  /// 알림 대상과 세션 사건 구독을 정리하고 예약해 둔 클릭을 거둠. 화면이 사라질 때 부름.
  void dispose() {
    _halts.cancel();
    scheduler.cancelPending();
    spanIndex.dispose();
    isPlaying.dispose();
    progressValue.dispose();
    countIn.dispose();
  }
}
