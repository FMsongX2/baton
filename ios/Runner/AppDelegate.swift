// 앱 진입점. 오디오 세션을 앱이 직접 정하고 지키며, 재생을 멈춰야 할 세션 사건을 Dart로 보냄.
// flutter_soloud는 iOS 세션 카테고리를 앱에 맡기므로 여기서 정하지 않으면 SoloAmbient로 돎.

import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  /// Dart의 AudioService가 듣는 통로. 듣기 전에는 nil이라 사건을 버림.
  private var sessionSink: FlutterEventSink?

  /// 엔진을 올리기 전에 세션을 정함. Dart가 오디오 엔진을 여는 시점보다 앞서야 함.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()
    center.addObserver(
      self, selector: #selector(onInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: session)
    center.addObserver(
      self, selector: #selector(onRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: session)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 플러그인을 등록하고 세션 사건 통로를 엶.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BatonAudioSession")
    else { return }
    FlutterEventChannel(name: "baton/audio_session", binaryMessenger: registrar.messenger())
      .setStreamHandler(self)
  }

  /// 무음 스위치와 무관하게 클릭이 들리고(playback), 반주 앱 소리와 함께 울림(mixWithOthers).
  /// 이미 그 상태면 건드리지 않음. 광고 SDK 등이 카테고리를 바꾸면 경로 변경 알림에서 다시 부름.
  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    if session.category == .playback && session.categoryOptions.contains(.mixWithOthers) { return }
    do {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      NSLog("오디오 세션 설정 실패: \(error)")
    }
  }

  /// 전화·Siri·알람이 시작되면 재생을 멈추게 알림. 끝나도 다시 틀지 않음. 연주자가 직접 누름.
  @objc private func onInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .began
    else { return }
    send("interrupted")
  }

  /// 이어폰·블루투스가 빠지면 멈추게 알림. 그대로 두면 클릭이 스피커로 새어 객석에 들림.
  /// 카테고리가 바뀌었으면 앱 설정으로 되돌림.
  @objc private func onRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
    else { return }
    switch reason {
    case .oldDeviceUnavailable:
      send("outputLost")
    case .categoryChange:
      configureAudioSession()
    default:
      break
    }
  }

  /// 세션 알림은 보조 스레드에서 오므로 메인 스레드로 옮겨 Dart에 보냄.
  private func send(_ event: String) {
    DispatchQueue.main.async { self.sessionSink?(event) }
  }

  /// Dart가 듣기 시작하면 통로를 잡아 둠.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sessionSink = events
    return nil
  }

  /// Dart가 듣기를 멈추면 통로를 놓음.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sessionSink = nil
    return nil
  }
}
