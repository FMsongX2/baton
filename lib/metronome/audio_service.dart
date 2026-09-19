// 오디오 엔진 수명과 클릭 음원, 오디오 세션 사건을 소유함. 앱 시작 시 한 번 올려 끝까지 유지함.
// 엔진을 올리지 못한 기기에서도 앱이 죽지 않도록 Stopwatch 시간축으로 물러섬.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'clock.dart';

class AudioService {
  final SoLoud soloud = SoLoud.instance;

  AudioSource? accent;
  AudioSource? tick;

  /// 엔진을 올리지 못했을 때 쓰는 대체 시간축. 클릭은 못 내지만 페이지 넘김은 굴러감.
  final _fallback = Stopwatch();

  bool _ready = false;

  /// 네이티브(AppDelegate·MainActivity)가 보내는 세션 사건. 전화·Siri 인터럽트 시작, 이어폰·블루투스 빠짐.
  /// iOS 세션 카테고리(playback + mixWithOthers)도 네이티브가 앱 시작 때 정하고 지킴.
  static const _sessionEvents = EventChannel('baton/audio_session');

  /// 재생을 멈춰야 하는 사건. 끝났다고 자동으로 다시 틀지 않음. 연주자가 직접 누름.
  final _halts = StreamController<void>.broadcast();

  /// 클릭 소리를 낼 수 있는 상태인지. false면 자동 넘김만 동작함.
  bool get ready => _ready;

  /// 엔진과 음원을 준비하고 세션 사건을 듣기 시작함. 실패해도 던지지 않고 대체 시간축으로 넘어감.
  Future<void> init() async {
    _listenSession();
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

  /// 네이티브 세션 사건을 halts로 옮김. 엔진이 없어도 자동 넘김은 멈춰야 하므로 엔진과 무관하게 들음.
  void _listenSession() {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
    _sessionEvents.receiveBroadcastStream().listen((event) {
      debugPrint('오디오 세션 사건: $event');
      _halts.add(null);
    }, onError: (Object e) => debugPrint('오디오 세션 사건 수신 실패: $e'));
  }

  /// 멈춘 출력 장치를 다시 켬. 소리 없는 클릭을 한 번 내면 플러그인이 장치를 깨움.
  /// Android에서 재라우팅이 실패해 스트림이 사라졌으면 기본 장치로 새로 엶.
  /// 그래도 켤 수 없으면(통화 중처럼 세션을 못 얻는 경우) false.
  bool _wakeOutput() {
    final src = tick;
    if (src == null) return true;
    try {
      soloud.play(src, volume: 0);
      return true;
    } catch (e) {
      debugPrint('출력 장치를 다시 켜지 못함: $e');
    }
    if (!Platform.isAndroid) return false;
    try {
      soloud.changeDevice();
      soloud.play(src, volume: 0);
      return true;
    } catch (e) {
      debugPrint('출력 장치를 새로 열지 못함: $e');
      return false;
    }
  }

  /// 재생 위치 계산에 쓸 시계를 만듦. 엔진이 살아 있으면 엔진 시각을 따름.
  /// 엔진이 도중에 죽거나 출력 장치가 멈춰도 시간이 계속 흐르도록 감쌈. 여기가 유일한 시계 생성
  /// 지점이라 리더와 메트로놈이 같은 보호와 같은 세션 사건을 받음.
  PlaybackClock createClock() => _ready
      ? PlaybackClock.engine(
          FallbackTime(soloud.getEngineTime, wake: _wakeOutput),
          halts: _halts.stream,
        )
      : PlaybackClock(() => _fallback.elapsed, halts: _halts.stream);

  /// 앱 종료 시 엔진을 내림.
  void dispose() {
    if (_ready) soloud.deinit();
    _halts.close();
  }
}
