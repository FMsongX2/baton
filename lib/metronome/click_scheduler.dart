// 타임라인의 클릭을 오디오 엔진에 미리 예약함. 룩어헤드 창 안의 것만 넣어
// 정지·템포 변경에 빠르게 반응하고, 지연 보정만큼 소리를 앞당겨 냄.

import 'package:flutter_soloud/flutter_soloud.dart';

import '../score/timeline.dart';
import 'clock.dart';

class ClickScheduler {
  ClickScheduler(this._soloud, this._clock);

  final SoLoud _soloud;
  final PlaybackClock _clock;

  /// 이 창 안에 들어온 클릭만 예약함. 버퍼 지연보다 넉넉해야 소리가 빠지지 않음.
  Duration lookahead = const Duration(milliseconds: 300);

  /// 출력 지연 보정. 블루투스 이어폰은 소리가 늦으므로 그만큼 일찍 예약함.
  Duration latency = Duration.zero;

  AudioSource? accent;
  AudioSource? tick;
  double volume = 1.0;

  bool _muted = false;

  /// 소리를 낼지. 끄면 이미 예약된 것도 거둠. 그러지 않으면 룩어헤드만큼 더 울림.
  bool get muted => _muted;
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (value) cancelPending();
  }

  List<Click> _clicks = const [];
  int _next = 0;

  /// 아직 울리지 않은 예약. 일시정지할 때 거두지 않으면 룩어헤드만큼 소리가 더 남.
  final _pending = <({Duration at, SoundHandle handle})>[];

  /// 지금까지 예약한 클릭 수. 실측·디버깅용.
  int scheduled = 0;

  /// 새 타임라인을 걸고 예약 커서를 위치 from으로 맞춤. 이미 지난 클릭은 건너뜀.
  void load(List<Click> clicks, Duration from) {
    cancelPending();
    _clicks = clicks;
    final fromSec = from.inMicroseconds / 1e6;
    _next = 0;
    while (_next < _clicks.length && _clicks[_next].time < fromSec) {
      _next++;
    }
    scheduled = 0;
  }

  /// 룩어헤드 창 안의 클릭을 예약함. 주기 타이머에서 호출. 이번에 예약한 개수를 돌려줌.
  /// 소리를 낼 수 없는 상태에서도 커서는 밀어 둠. 나중에 켜도 밀린 클릭이 몰려 나오지 않음.
  int pump() {
    if (!_clock.isRunning) return 0;
    final now = _clock.position;
    final horizonSec = (now + lookahead).inMicroseconds / 1e6;

    // 소리를 낼 수 없으면 엔진에 묻지 않음. 예외 자체는 AudioService.createClock이 막음
    Duration? engineNow;
    if (!_muted && (accent != null || tick != null)) {
      try {
        engineNow = _soloud.getEngineTime();
      } catch (_) {
        engineNow = null;
      }
    }
    var count = 0;

    if (engineNow != null) _pending.removeWhere((p) => p.at <= engineNow!);

    while (_next < _clicks.length && _clicks[_next].time <= horizonSec) {
      final c = _clicks[_next];
      _next++;
      if (engineNow == null) continue;
      final src = c.accent ? accent : tick;
      if (src == null) continue;
      final at = _clock.engineTimeAt(secondsToDuration(c.time))! - latency;
      // 이미 지난 시각은 예약해도 늦게 나거나 몰려 나오므로 버림
      if (at <= engineNow) continue;
      // 분할음은 박을 덮지 않도록 낮춤
      final handle = _soloud.playScheduled(src, at, volume: c.subdivision ? volume * 0.45 : volume);
      _pending.add((at: at, handle: handle));
      count++;
      scheduled++;
    }
    return count;
  }

  /// 아직 울리지 않은 예약을 거둠. 일시정지·구간 점프처럼 시간축이 끊길 때 부름.
  /// 엔진이 살아 있지 않으면 예약 자체가 없으므로 목록만 비움.
  void cancelPending() {
    if (_pending.isEmpty) return;
    try {
      final now = _soloud.getEngineTime();
      for (final p in _pending) {
        if (p.at > now) _soloud.stopScheduled(p.handle, now);
      }
    } catch (_) {
      // 엔진이 내려간 상태. 예약도 함께 사라졌으므로 무시함
    }
    _pending.clear();
  }

  /// 커서를 위치 p로 다시 맞춤. 되감기·구간 점프에서 씀.
  void rewindTo(Duration p) => load(_clicks, p);
}
