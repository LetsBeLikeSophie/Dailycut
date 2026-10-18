package com.dailycut.dailycut

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 앱에서 지역을 바꾸면 홈 화면 위젯도 바로 새 지역으로 다시 그리게(widget_bridge.dart가 부름)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dailycut/widget").setMethodCallHandler { call, result ->
            if (call.method == "refresh") {
                WeatherWidget.requestUpdate(applicationContext)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
