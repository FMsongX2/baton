// 재생 위치의 단일 출처. 오디오 엔진 시각을 기준으로 삼아 클릭과 페이지 넘김이 같은 시간축을 공유함.
// Dart Timer로 박을 세지 않음. 긴 곡에서 수백 ms 어긋나 이 앱의 존재 이유가 무너짐.

/// 시간 제공자가 던지면 마지막 값에서 이어지는 시계로 물러섬.
/// 오디오 엔진이 도중에 죽으면 getEngineTime()이 던지는데, 그대로 두면 매 프레임 예외가 나
/// 소리뿐 아니라 페이지 자동 넘김까지 멈춤. 엔진 시각을 읽는 모든 경로가 여기로 모임.
/// 한 번 물러서면 엔진으로 돌아가지 않음. 두 시간축을 오가면 재생 위치가 튐.
Duration Function() withFallbackClock(Duration Function() primary) {
  final since = Stopwatch();
  var last = Duration.zero;
  return () {
    if (since.isRunning) return last + since.elapsed;
    try {
      last = primary();
      return last;
    } catch (_) {
      since.start();
      return last;
    }
  };
}

class PlaybackClock {
  /// now는 단조 증가하는 시각을 주는 함수. 평소에는 오디오 엔진 시각을 넘기고,
  /// 엔진을 올리지 못한 기기에서는 Stopwatch를 넘겨 자동 넘김만이라도 살림.
  PlaybackClock(this._now);

  final Duration Function() _now;

  /// 재생을 시작한 시점의 기준 시각. null이면 정지 상태.
  Duration? _startedAt;

  /// 마지막 일시정지까지 누적된 재생 위치.
  Duration _offset = Duration.zero;

  /// 재생 중이면 true. 일시정지·정지 상태에서는 false.
  bool get isRunning => _startedAt != null;

  /// 현재 재생 위치. 일시정지 중이면 멈춘 지점을 그대로 돌려줌.
  Duration get position => _startedAt == null ? _offset : _offset + (_now() - _startedAt!);

  /// 현재 위치부터 재생을 이어감. 이미 재생 중이면 아무것도 하지 않음.
  void start() => _startedAt ??= _now();

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

  /// 지정 위치로 건너뜀. 재생 중이면 그 지점부터 계속 흐름.
  void seek(Duration p) {
    _offset = p;
    if (_startedAt != null) _startedAt = _now();
  }

  /// 재생 위치를 기준 시간축의 절대 시각으로 변환함. playScheduled에 그대로 넘기는 값.
  /// 정지 상태에서는 기준점이 없어 null.
  Duration? engineTimeAt(Duration p) => _startedAt == null ? null : _startedAt! + (p - _offset);
}
