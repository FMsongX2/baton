// 타임라인의 클릭을 오디오 엔진에 미리 예약함. 룩어헤드 창 안의 것만 넣어
// 정지·템포 변경에 빠르게 반응하고, 지연 보정만큼 소리를 앞당겨 냄.

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../score/timeline.dart';
import 'clock.dart';

/// 지연 보정 상한. 설정 슬라이더의 최댓값과 같음. 깨진 DB 값이 들어와도 이 안으로 접음.
const kMaxLatency = Duration(milliseconds: 400);

class ClickScheduler {
  ClickScheduler(this._soloud, this._clock);

  final SoLoud _soloud;
  final PlaybackClock _clock;

  /// 클릭을 엔진 시각보다 이만큼 앞서 예약함. 프레임이 밀려도 예약이 늦지 않도록 버퍼 지연보다 넉넉히 둠.
  Duration lookahead = const Duration(milliseconds: 300);

  /// 시작·건너뛰기 기준점을 지연 보정에 더해 이만큼 더 미래로 둠.
  /// 첫 클릭이 다음 프레임의 pump에 닿기 전에 지나가 버리지 않도록 엔진 시각 계단(버퍼 한두 칸)과
  /// 첫 프레임 지연을 덮음.
  static const startMargin = Duration(milliseconds: 150);

  Duration _latency = Duration.zero;

  /// 출력 지연 보정. 블루투스 이어폰은 소리가 늦으므로 그만큼 일찍 예약함. 0~[kMaxLatency]로 접힘.
  Duration get latency => _latency;
  set latency(Duration value) => _latency = value < Duration.zero
      ? Duration.zero
      : (value > kMaxLatency ? kMaxLatency : value);

  /// 재생 위치 기준 예약 창. 지연 보정만큼 일찍 내야 하므로 그만큼 더 앞을 봄.
  /// 그러지 않으면 보정이 룩어헤드를 잡아먹어 300ms 이상에서 클릭이 전부 버려짐.
  Duration get horizon => lookahead + _latency;

  /// PlaybackClock.start·seek에 넘길 lead. 시작 지점의 첫 클릭(카운트인 강박)이 예약될 시간을 벎.
  Duration get startLead => _latency + startMargin;

  AudioSource? accent;
  AudioSource? tick;
  double volume = 1.0;

  bool _muted = false;

  /// 소리를 낼지. 끄면 이미 예약된 것도 거둠. 그러지 않으면 룩어헤드만큼 더 울림.
  /// 꺼진 동안 커서가 예약 창 끝까지 밀려 있으므로 다시 켜면 지금 위치로 되돌림.
  /// 그러지 않으면 켠 직후 창 하나만큼 클릭이 빠짐. 이미 늦은 클릭은 pump가 버림.
  bool get muted => _muted;
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (value) {
      cancelPending();
    } else {
      rewindTo(_clock.position);
    }
  }

  List<Click> _clicks = const [];
  int _next = 0;

  /// 아직 울리지 않은 예약. 일시정지할 때 거두지 않으면 룩어헤드만큼 소리가 더 남.
  final _pending = <({Duration at, SoundHandle handle})>[];

  /// 지금까지 예약한 클릭 수. 실측·디버깅용.
  int scheduled = 0;

  /// 새 타임라인을 걸고 예약 커서를 위치 from으로 맞춤. 이전 타임라인의 예약은 거둠.
  void load(List<Click> clicks, Duration from) {
    cancelPending();
    _clicks = clicks;
    scheduled = 0;
    rewindTo(from);
  }

  /// 룩어헤드 창 안의 클릭을 예약함. 주기 타이머에서 호출. 이번에 예약한 개수를 돌려줌.
  /// 소리를 낼 수 없는 상태에서도 커서는 밀어 둠. 나중에 켜도 밀린 클릭이 몰려 나오지 않음.
  int pump() {
    if (!_clock.isRunning) return 0;
    final now = _clock.position;
    final horizonSec = (now + horizon).inMicroseconds / 1e6;

    // 소리를 낼 수 없으면 엔진에 묻지 않음. 예외 자체는 AudioService.createClock이 막음
    Duration? engineNow;
    if (!_muted && (accent != null || tick != null)) {
      if (_clock.followsEngine) {
        try {
          engineNow = _soloud.getEngineTime();
        } catch (_) {
          engineNow = null;
        }
      } else {
        // 시계가 Stopwatch로 물러섬. 걸어 둔 클릭은 엔진이 다시 돌 때 멈춘 시간만큼 늦게 울림
        cancelPending();
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
      final at = _clock.engineTimeAt(secondsToDuration(c.time))! - _latency;
      // 이미 지난 시각은 예약해도 늦게 나거나 몰려 나오므로 버림
      if (at <= engineNow) continue;
      final SoundHandle handle;
      try {
        // 분할음은 박을 덮지 않도록 낮춤
        handle = _soloud.playScheduled(src, at, volume: c.subdivision ? volume * 0.45 : volume);
      } catch (e) {
        // 출력 장치를 켜지 못함. 던지면 Ticker가 끊겨 페이지 넘김까지 서므로 이 박만 버림
        debugPrint('클릭 예약 실패: $e');
        continue;
      }
      _pending.add((at: at, handle: handle));
      count++;
      scheduled++;
    }
    return count;
  }

  /// 아직 울리지 않은 예약을 거둠. 일시정지·구간 점프처럼 시간축이 끊길 때 부름.
  /// 커서는 옮기지 않음. 거둔 클릭을 다시 울리려면 부른 쪽이 rewindTo로 커서를 맞춤.
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

  /// 예약 커서만 위치 p로 옮김. 이미 예약한 소리는 그대로 둠.
  /// 시간축이 끊기는 되감기·구간 점프는 먼저 cancelPending을 부름. 메트로놈 이음매처럼 위상이 이어지면
  /// 부르지 않아야 끝 박이 살아남음. µs 반올림으로 p가 클릭 시각을 살짝 넘어도 그 클릭은 남김.
  void rewindTo(Duration p) {
    final fromSec = p.inMicroseconds / 1e6 - kTimeEpsilon;
    _next = 0;
    while (_next < _clicks.length && _clicks[_next].time < fromSec) {
      _next++;
    }
  }
}
