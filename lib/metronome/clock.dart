// 재생 위치의 단일 출처. 오디오 엔진 시각을 기준으로 삼아 클릭과 페이지 넘김이 같은 시간축을 공유함.
// Dart Timer로 박을 세지 않음. 긴 곡에서 수백 ms 어긋나 이 앱의 존재 이유가 무너짐.

/// 엔진 시각이 이만큼 실제 시간 동안 그대로면 출력 장치가 멈춘 것으로 봄.
/// 엔진 시각은 출력 버퍼마다 계단식으로 오르므로 버퍼 몇 칸보다 넉넉해야 함.
/// 재라우팅처럼 잠깐 멈췄다 도는 경우를 고장으로 잘못 보면 그 재생 동안 클릭이 끊김.
const kEngineStallLimit = Duration(milliseconds: 500);

/// 엔진 시각을 따르다가 던지거나 멈추면 마지막으로 흐르던 지점에서 Stopwatch로 이어 가는 시간원.
/// 엔진이 죽으면 getEngineTime()이 던지고, 출력 장치가 멈추면(iOS 인터럽트, Android 재라우팅 실패)
/// 던지지 않고 같은 값만 돌려줌. 어느 쪽이든 그대로 두면 소리뿐 아니라 페이지 자동 넘김까지 멈춤.
/// 재생 중에 한 번 물러서면 엔진으로 돌아가지 않음. 두 시간축을 오가면 재생 위치가 튐.
/// 재생을 새로 시작할 때(rearm)만 엔진을 다시 믿어 봄.
class FallbackTime {
  /// primary는 엔진 시각을 읽는 함수. stallLimit 넘게 값이 그대로면 멈춘 것으로 봄.
  FallbackTime(this._primary, {this.stallLimit = kEngineStallLimit, this.wake});

  final Duration Function() _primary;
  final Duration stallLimit;

  /// 멈춘 출력 장치를 다시 켜 보고 성공 여부를 돌려줌. rearm에서만 부름.
  final bool Function()? wake;

  /// 엔진 값이 마지막으로 바뀐 뒤 흐른 실제 시간. 멈춤 판정과 물러설 때 이어 붙일 길이에 씀.
  final _sinceAdvance = Stopwatch();

  /// 물러선 뒤의 시간축. 돌고 있으면 엔진을 더 읽지 않음.
  final _fallback = Stopwatch();

  Duration _last = Duration.zero;
  Duration _base = Duration.zero;

  /// 엔진 시각을 벗어나 Stopwatch로 흐르는 중인지. 이때 엔진에 소리를 예약하면 시각이 어긋남.
  bool get fellBack => _fallback.isRunning;

  /// 현재 시각. 엔진이 던지거나 stallLimit 넘게 멈추면 그 자리에서 Stopwatch로 물러섬.
  Duration call() {
    if (fellBack) return _base + _fallback.elapsed;
    try {
      final v = _primary();
      if (!_sinceAdvance.isRunning || v != _last) {
        _last = v;
        _sinceAdvance
          ..reset()
          ..start();
        return v;
      }
      if (_sinceAdvance.elapsed < stallLimit) return v;
    } catch (_) {
      // 엔진이 내려감. 아래에서 물러섬
    }
    return _fallBack();
  }

  /// 마지막으로 흐르던 시점부터 실제 시간으로 이어 가게 바꿈. 멈춘 동안 밀린 시간을 한 번에 따라잡음.
  Duration _fallBack() {
    _base = _last + _sinceAdvance.elapsed;
    _fallback
      ..reset()
      ..start();
    return _base;
  }

  /// 장치를 깨우고 엔진을 다시 믿어 봄. 재생 기준점을 새로 잡기 직전에만 불러야 위치가 튀지 않음.
  /// 장치를 못 깨우면 멈춤 판정을 기다리지 않고 바로 물러섬.
  void rearm() {
    final wake = this.wake;
    if (wake != null && !wake()) {
      if (!fellBack) _fallBack();
      return;
    }
    _fallback
      ..stop()
      ..reset();
    _sinceAdvance
      ..stop()
      ..reset();
  }
}

class PlaybackClock {
  /// now는 단조 증가하는 시각을 주는 함수. 엔진을 올리지 못한 기기에서는 Stopwatch를 넘겨
  /// 자동 넘김만이라도 살림. halts는 재생을 멈춰야 하는 오디오 사건(전화, 이어폰 빠짐).
  PlaybackClock(this._now, {this.halts = const Stream<void>.empty()}) : _guard = null;

  /// 오디오 엔진 시각을 따르는 시계. 엔진이 던지거나 멈추면 source가 이어 받음.
  PlaybackClock.engine(FallbackTime source, {this.halts = const Stream<void>.empty()})
    : _now = source.call,
      _guard = source;

  final Duration Function() _now;
  final FallbackTime? _guard;

  /// 시간원(오디오 출력)이 끊기거나 소리가 엉뚱한 곳으로 샐 사건. 재생하는 쪽이 듣고 멈춤.
  final Stream<void> halts;

  /// 재생을 시작한 시점의 기준 시각. null이면 정지 상태.
  Duration? _startedAt;

  /// 마지막 일시정지까지 누적된 재생 위치.
  Duration _offset = Duration.zero;

  /// 재생 중이면 true. 일시정지·정지 상태에서는 false.
  bool get isRunning => _startedAt != null;

  /// 기준 시각이 오디오 엔진 시각과 같은지. false면 engineTimeAt을 엔진 예약에 쓸 수 없음.
  bool get followsEngine => !(_guard?.fellBack ?? false);

  /// 현재 재생 위치. 일시정지 중이면 멈춘 지점을 그대로 돌려줌. 시작 직후 lead 동안은 음수.
  Duration get position => _startedAt == null ? _offset : _offset + (_now() - _startedAt!);

  /// 현재 위치부터 재생을 이어감. 이미 재생 중이면 아무것도 하지 않음.
  /// 기준점을 lead만큼 미래에 둠. 첫 클릭이 예약되기 전에 그 시각이 지나가 버리지 않게 하려는 것.
  /// 기준점을 새로 잡는 순간이라 멈췄던 엔진으로 돌아가도 위치가 튀지 않으므로 시간원을 다시 믿어 봄.
  void start([Duration lead = Duration.zero]) {
    if (_startedAt != null) return;
    _guard?.rearm();
    _startedAt = _now() + lead;
  }

  /// 위치를 보존한 채 멈춤. 이미 예약된 소리를 거두는 것은 호출자 책임.
  void pause() {
    if (_startedAt == null) return;
    _offset = position;
    _startedAt = null;
  }

  /// 위치를 0으로 되돌리고 멈춤.
  void reset() {
    _startedAt = null;
    _offset = Duration.zero;
  }

  /// 기준점을 옮겨 재생 위치를 by만큼 뒤로 물림. 위상이 정확히 유지되므로
  /// 메트로놈처럼 같은 구간을 끝없이 반복할 때 이어 붙이는 데 씀.
  void shift(Duration by) {
    if (_startedAt == null) {
      _offset -= by;
    } else {
      _startedAt = _startedAt! + by;
    }
  }

  /// 지정 위치로 건너뜀. 재생 중이면 기준점을 lead만큼 미래에 다시 잡고 그 지점부터 흐름.
  void seek(Duration p, [Duration lead = Duration.zero]) {
    _offset = p;
    if (_startedAt != null) _startedAt = _now() + lead;
  }

  /// 재생 위치를 기준 시간축의 절대 시각으로 변환함. playScheduled에 그대로 넘기는 값.
  /// 정지 상태에서는 기준점이 없어 null.
  Duration? engineTimeAt(Duration p) => _startedAt == null ? null : _startedAt! + (p - _offset);
}
