package com.dailycut.dailycut

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingTab: String? = null
    private var notifResult: MethodChannel.Result? = null

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
                // 아침 날씨 알림(Briefing.kt): 켜기·끄기·시각은 앱이 flutter.brief_time에 저장한 뒤 이걸 불러 일정을 다시 걺
                "briefApply" -> {
                    Briefing.apply(applicationContext)
                    result.success(null)
                }
                "notifGranted" -> result.success(Briefing.permitted(applicationContext))
                // 알림 허용 요청(안드로이드 13+에서만 창이 뜸). 이미 허용이거나 12 이하면 바로 결과
                "notifRequest" -> {
                    if (Briefing.permitted(applicationContext)) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= 33 && notifResult == null) {
                        notifResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7001) {
            notifResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            notifResult = null
        }
    }

    // 앱이 이미 떠 있는 상태에서 위젯을 누르면 새 인텐트로 들어옴 → 플러터에 탭을 바꾸라고 알림
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("tab")?.let { channel?.invokeMethod("openTab", it) }
    }
}
