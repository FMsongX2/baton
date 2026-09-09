// 오디오 엔진 수명과 클릭 음원을 소유함. 앱 시작 시 한 번 올려 끝까지 유지함.
// 엔진을 올리지 못한 기기에서도 앱이 죽지 않도록 Stopwatch 시간축으로 물러섬.

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'clock.dart';

class AudioService {
  final SoLoud soloud = SoLoud.instance;

  AudioSource? accent;
  AudioSource? tick;

  /// 엔진을 올리지 못했을 때 쓰는 대체 시간축. 클릭은 못 내지만 페이지 넘김은 굴러감.
  final _fallback = Stopwatch();

  bool _ready = false;

  /// 클릭 소리를 낼 수 있는 상태인지. false면 자동 넘김만 동작함.
  bool get ready => _ready;

  /// 엔진과 음원을 준비함. 실패해도 던지지 않고 대체 시간축으로 넘어감.
  Future<void> init() async {
    try {
      await soloud.init();
      accent = await soloud.loadAsset('assets/sounds/click_hi.wav');
      tick = await soloud.loadAsset('assets/sounds/click_lo.wav');
      _ready = true;
    } catch (e) {
      debugPrint('오디오 엔진 초기화 실패, 무음으로 진행: $e');
      _fallback.start();
      _ready = false;
    }
  }

  /// 재생 위치 계산에 쓸 시계를 만듦. 엔진이 살아 있으면 엔진 시각을 따름.
  /// 엔진이 도중에 죽어도 시간이 계속 흐르도록 감쌈. 여기가 유일한 시계 생성 지점이라
  /// 리더와 메트로놈이 같은 보호를 받음.
  PlaybackClock createClock() =>
      PlaybackClock(withFallbackClock(_ready ? soloud.getEngineTime : () => _fallback.elapsed));

  /// 앱 종료 시 엔진을 내림.
  void dispose() {
    if (_ready) soloud.deinit();
  }
}
