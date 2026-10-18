package com.dailycut.dailycut

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingTab: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingTab = intent?.getStringExtra("tab")
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dailycut/widget")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // 앱에서 지역·장바구니를 바꾸면 홈 화면 위젯도 바로 새로 그리게(widget_bridge.dart가 부름)
                "refresh" -> {
                    BaseWidget.renderEverything(applicationContext, WidgetData.cached(applicationContext)) // 옛 지역 값은 바로 비우고
                    WidgetSync.now(applicationContext, replace = true) // 새 값은 연결되는 대로
                    result.success(null)
                }
                // 위젯을 눌러 앱이 처음 켜졌을 때 열어야 할 탭(한 번 꺼내면 비움)
                "initialTab" -> {
                    result.success(pendingTab)
                    pendingTab = null
                }
                else -> result.notImplemented()
            }
        }
    }

    // 앱이 이미 떠 있는 상태에서 위젯을 누르면 새 인텐트로 들어옴 → 플러터에 탭을 바꾸라고 알림
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("tab")?.let { channel?.invokeMethod("openTab", it) }
    }
}
