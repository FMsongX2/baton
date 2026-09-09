// 클럭·클릭 예약·페이지 전환을 한 덩어리로 굴림. 시간 판단은 전부 타임라인과 클럭에 맡기고
// 여기서는 상태 전이와 알림만 다룸. tick은 화면의 Ticker가 매 프레임 부름.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../metronome/click_scheduler.dart';
import '../metronome/clock.dart';
import 'timeline.dart';

class PlaybackEngine {
  PlaybackEngine(this.clock, this.scheduler);

  final PlaybackClock clock;
  final ClickScheduler scheduler;

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

  /// 현재 재생 위치.
  Duration get position => clock.position;

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
    final now = position.inMicroseconds / 1e6;
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
  /// 연주자가 다시 들어올 지점을 셀 수 있게 함.
  void play() {
    final t = _timeline;
    if (t == null || isPlaying.value) return;
    if (position.inMicroseconds / 1e6 >= t.totalSeconds) {
      // 끝까지 간 뒤 다시 누르면 처음부터. 그대로 두면 한 프레임 만에 다시 멈춤
      stop();
    } else if (position > Duration.zero) {
      _rewindForResume();
    }
    clock.start();
    isPlaying.value = true;
  }

  /// 재개 지점 앞의 마디선까지 되감고 그 구간을 카운트인으로 표시함.
  /// 되감은 구간의 클릭은 타임라인에 이미 있으므로 따로 만들지 않음.
  void _rewindForResume() {
    final t = _timeline!;
    if (t.countInBars <= 0) return;
    final now = position.inMicroseconds / 1e6;
    final i = t.spanIndexAt(now);
    // 카운트인 구간이거나 곡이 끝난 뒤면 되감을 기준 마디가 없음
    if (i < 0) return;

    final span = t.spans[i];
    final bar = barSeconds(span.clicksPerBar, span.bpm);
    // 마디선에 맞춰 되감아야 다시 들어오는 지점이 강박이 됨
    final barsIn = ((now - span.start) / bar).floor();
    final target = math.max(0.0, span.start + (barsIn - t.countInBars) * bar);

    _countInFrom = target;
    _countInUntil = span.start + barsIn * bar;
    _countInFirst = _clickIndexAt(target);
    _seekTo(secondsToDuration(target));
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
    if (t.spans.isNotEmpty) onPageChanged?.call(t.spans.first.pageIndex);
  }

  /// 위치를 남긴 채 멈춤. 이미 예약된 클릭은 거둬 멈춘 뒤에 소리가 남지 않게 함.
  void pause() {
    if (!isPlaying.value) return;
    clock.pause();
    scheduler.cancelPending();
    isPlaying.value = false;
    _notifyPosition();
  }

  /// 특정 스팬의 시작으로 건너뜀. 카운트인은 다시 하지 않음.
  void jumpToSpan(int index) {
    final t = _timeline;
    if (t == null || index < 0 || index >= t.spans.length) return;
    // 되감은 구간이 남아 있으면 카운트인 숫자가 잘못 뜨므로 함께 지움
    _countInFrom = 0;
    _countInUntil = index == 0 ? t.countInEnd : 0;
    _countInFirst = 0;
    _seekTo(secondsToDuration(t.spans[index].start));
    spanIndex.value = index;
    onPageChanged?.call(t.spans[index].pageIndex);
  }

  /// 시간축을 옮기고 예약을 다시 맞춤. 되감기·건너뛰기가 공통으로 씀.
  void _seekTo(Duration at) {
    scheduler.cancelPending();
    clock.seek(at);
    scheduler.rewindTo(at);
    _notifyPosition();
  }

  /// 매 프레임 호출. 클릭을 예약하고 넘길 때가 되면 페이지를 넘김.
  void tick() {
    if (!isPlaying.value) return;
    final t = _timeline;
    if (t == null) return;

    scheduler.pump();
    _notifyPosition();

    final now = position.inMicroseconds / 1e6;
    if (t.spans.isNotEmpty) {
      // 재개하며 앞 페이지로 되감았을 수 있어 전진 전에 실제 위치로 맞춤
      final from = now < t.spans[spanIndex.value].start ? t.spanIndexAt(now) : spanIndex.value;
      final next = advanceSpan(t, from, now);
      if (next != spanIndex.value) {
        spanIndex.value = next;
        onPageChanged?.call(t.spans[next].pageIndex);
      }
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

  /// 알림 대상을 정리하고 예약해 둔 클릭을 거둠. 화면이 사라질 때 부름.
  void dispose() {
    scheduler.cancelPending();
    spanIndex.dispose();
    isPlaying.dispose();
    progressValue.dispose();
    countIn.dispose();
  }
}
