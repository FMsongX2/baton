// 앱 진입 액티비티. 재생을 멈춰야 할 오디오 사건(이어폰 빠짐, 통화)을 Dart로 보냄.
// 오디오 포커스는 잡지 않음. 잡으면 함께 틀어 둔 반주 앱 재생이 멈춤.

package com.hajung.baton

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    /** Dart의 AudioService가 듣는 통로. 듣기 전에는 null이라 사건을 버림. */
    private var sink: EventChannel.EventSink? = null
    private var listening = false

    /** 유선·블루투스 출력이 빠져 스피커로 넘어가기 직전에 오는 방송. 그대로 두면 클릭이 객석으로 샘. */
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) sink?.success("outputLost")
        }
    }

    /** 벨·통화가 시작되면 바뀌는 오디오 모드를 봄. 포커스 없이 통화를 알 수 있는 길(API 31+). */
    private var modeListener: AudioManager.OnModeChangedListener? = null

    /** 세션 사건 통로를 엶. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "baton/audio_session")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    listen()
                }

                override fun onCancel(arguments: Any?) {
                    unlisten()
                    sink = null
                }
            })
    }

    /** 액티비티가 엔진을 놓을 때 방송·모드 구독을 풂. 남기면 수신기가 새어 나감. */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unlisten()
        sink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** 이어폰 빠짐 방송과 통화 모드 변화를 구독함. 두 번 불려도 한 번만 등록함. */
    private fun listen() {
        if (listening) return
        listening = true
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext.registerReceiver(noisy, filter)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val listener = AudioManager.OnModeChangedListener { mode ->
                if (mode == AudioManager.MODE_RINGTONE ||
                    mode == AudioManager.MODE_IN_CALL ||
                    mode == AudioManager.MODE_IN_COMMUNICATION
                ) {
                    sink?.success("interrupted")
                }
            }
            getSystemService(AudioManager::class.java).addOnModeChangedListener(mainExecutor, listener)
            modeListener = listener
        }
    }

    /** 구독을 풂. 등록하지 않았으면 아무것도 하지 않음. */
    private fun unlisten() {
        if (!listening) return
        listening = false
        applicationContext.unregisterReceiver(noisy)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modeListener?.let { getSystemService(AudioManager::class.java).removeOnModeChangedListener(it) }
        }
        modeListener = null
    }
}
