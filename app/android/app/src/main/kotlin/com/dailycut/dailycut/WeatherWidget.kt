package com.dailycut.dailycut

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 홈 화면 "날씨·미세먼지" 위젯(2026-10-18). 앱(플러터)이 저장해 둔 지역(시도·시군구)을 읽어 서버 `/weather`를 직접 불러 그림 —
 * 앱을 켜지 않아도 30분마다(`weather_widget_info.xml`의 updatePeriodMillis) 갱신됨. 마지막으로 받은 응답은 따로 저장해 두었다가
 * 네트워크가 안 될 때 "오래된 정보"로 보여 줌. 위치(좌표)는 읽지 않고 저장된 지역 이름만 씀.
 * 플러터 `shared_preferences`는 `FlutterSharedPreferences` 파일에 키 앞에 `flutter.`를 붙여 저장함(region.dart의 region_code/region_sgg).
 */
class WeatherWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        Thread {
            try {
                refresh(context, manager, ids)
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val API = "https://itssophie.dev/dailycut-api"
        private const val OWN_PREFS = "dailycut_widget"

        /** 앱에서 지역을 바꿨을 때 등 바로 다시 그리고 싶을 때(MainActivity의 채널이 부름). */
        fun requestUpdate(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WeatherWidget::class.java))
            if (ids.isEmpty()) return
            Thread { refresh(context, manager, ids) }.start()
        }

        private fun refresh(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val own = context.getSharedPreferences(OWN_PREFS, Context.MODE_PRIVATE)
            val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val sido = flutter.getString("flutter.region_code", null) ?: "11"
            val sgg = flutter.getString("flutter.region_sgg", null)
            val key = "$sido|${sgg ?: ""}"
            var stale = false
            var body: String? = fetch(sido, sgg)
            if (body != null) {
                own.edit().putString("last", body).putString("last_key", key)
                    .putLong("last_at", System.currentTimeMillis()).apply()
            } else {
                // 같은 지역으로 받아 둔 값이 있을 때만 대신 보여 줌(지역이 바뀐 뒤 옛 지역 날씨가 나오지 않게)
                if (own.getString("last_key", null) == key) body = own.getString("last", null)
                stale = body != null
            }
            val views = build(context, body?.let { runCatching { JSONObject(it) }.getOrNull() }, stale, own.getLong("last_at", 0L))
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            manager.updateAppWidget(ids, views)
        }

        private fun fetch(sido: String, sgg: String?): String? = try {
            var url = "$API/weather?sido=${URLEncoder.encode(sido, "UTF-8")}"
            if (!sgg.isNullOrEmpty()) url += "&sgg=${URLEncoder.encode(sgg, "UTF-8")}"
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 10_000
            c.readTimeout = 20_000
            if (c.responseCode == 200) c.inputStream.bufferedReader().use { it.readText() } else null
        } catch (_: Exception) {
            null
        }

        private fun gradeColor(grade: String?): Int = when (grade) {
            "좋음" -> Color.parseColor("#2F6FDB")
            "보통" -> Color.parseColor("#2E8B57")
            "나쁨" -> Color.parseColor("#E07B00")
            "매우나쁨" -> Color.parseColor("#D32F2F")
            else -> Color.GRAY
        }

        private fun dust(label: String, grade: String?, value: Int?): CharSequence {
            val sb = SpannableStringBuilder("$label ")
            val text = if (grade == null) "-" else if (value != null) "$grade $value" else grade
            val start = sb.length
            sb.append(text)
            sb.setSpan(ForegroundColorSpan(gradeColor(grade)), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            return sb
        }

        private fun build(context: Context, j: JSONObject?, stale: Boolean, at: Long): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_weather)
            if (j == null) {
                v.setTextViewText(R.id.w_region, "데일리컷")
                v.setTextViewText(R.id.w_temp, "--°")
                v.setTextViewText(R.id.w_cond, "날씨를 불러오지 못했어요")
                v.setTextViewText(R.id.w_range, "")
                v.setTextViewText(R.id.w_pm10, "")
                v.setTextViewText(R.id.w_pm25, "")
                v.setTextViewText(R.id.w_outfit, "눌러서 앱 열기")
                return v
            }
            val today = j.optJSONObject("today")
            val air = j.optJSONObject("air_quality")
            val label = j.optJSONObject("location")?.optString("label").orEmpty().ifEmpty { "서울" }
            v.setTextViewText(R.id.w_region, if (stale) "$label · 오래된 정보" else label)
            v.setTextViewText(R.id.w_temp, today?.let { "${it.optInt("temp")}°" } ?: "--°")
            v.setTextViewText(R.id.w_cond, today?.optString("condition").orEmpty())
            v.setTextViewText(
                R.id.w_range,
                today?.let { "최고 ${it.optInt("high")}° · 최저 ${it.optInt("low")}°" } ?: "",
            )
            if (air != null) {
                v.setTextViewText(R.id.w_pm10, dust("미세먼지", air.optString("pm10").ifEmpty { null }, air.optInt("pm10_value", -1).takeIf { it >= 0 }))
                v.setTextViewText(R.id.w_pm25, dust("초미세먼지", air.optString("pm25").ifEmpty { null }, air.optInt("pm25_value", -1).takeIf { it >= 0 }))
            } else {
                v.setTextViewText(R.id.w_pm10, "")
                v.setTextViewText(R.id.w_pm25, "")
            }
            val updated = if (at > 0) SimpleDateFormat("HH:mm", Locale.KOREA).apply { timeZone = TimeZone.getTimeZone("Asia/Seoul") }.format(Date(at)) else null
            val outfit = j.optString("outfit")
            v.setTextViewText(R.id.w_outfit, if (stale && updated != null) "$updated 기준 · 인터넷이 연결되면 새로 받아요" else outfit)
            return v
        }
    }
}
