package com.dailycut.dailycut

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import android.view.View
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/*
 * 홈 화면 위젯(2026-10-18, 안드로이드 네이티브). 위젯 4종이 같은 데이터(서버 `/widget` 한 번)를 나눠 씀:
 *  - WeatherWidget      "오늘 한눈에"(4x3): 날씨·미세먼지 + 장바구니·청약·이번 주 행사 줄
 *    (클래스 이름은 처음 만든 날씨 위젯 때 그대로 — 이미 홈 화면에 올려 둔 위젯이 안 사라지게 이름을 안 바꿈)
 *  - WeatherOnlyWidget  날씨(4x2) / BasketWidget 장바구니(2x2) / HousingWidget 청약(4x2)
 * 앱(플러터)이 저장해 둔 지역·내 장바구니를 `FlutterSharedPreferences`(키 앞에 `flutter.`)에서 읽음 — 위치(좌표)는 안 읽음.
 * 내 장바구니 품목은 URL이 아니라 POST 본문으로 보냄(접속 로그에 안 남게). 받기 실패하면 같은 지역으로 받아 둔 마지막 값을 "오래된 정보"로 보여 줌.
 * 줄·위젯을 누르면 앱이 해당 탭으로 열림(intent extra `tab` → MainActivity → 플러터).
 */
object WidgetData {
    private const val API = "https://itssophie.dev/dailycut-api"
    private const val OWN = "dailycut_widget"
    private const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!" // 플러터 setStringList가 앞에 붙이는 표시
    private const val STALE_AFTER_MS = 90 * 60 * 1000L // 새로 못 받은 지 90분이 넘으면 "오래된 정보"로 표시

    class Snapshot(val json: JSONObject?, val stale: Boolean, val at: Long)

    private fun flutterPrefs(context: Context) = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** 지금 앱에 저장된 지역·장바구니로 만든 키 — 받아 둔 값이 이 키와 같을 때만 보여 줌(지역을 바꾼 뒤 옛 지역 날씨가 나오지 않게). */
    private fun currentKey(context: Context): String {
        val f = flutterPrefs(context)
        return "${f.getString("flutter.region_code", null) ?: "11"}|${f.getString("flutter.region_sgg", null) ?: ""}|${basketItems(f).joinToString(",")}"
    }

    /** 네트워크 없이 받아 둔 값만. 지역이 다르면 비어 있음, 새로 받은 지 오래됐으면 stale. */
    fun cached(context: Context): Snapshot {
        val own = context.getSharedPreferences(OWN, Context.MODE_PRIVATE)
        if (own.getString("last_key", null) != currentKey(context)) return Snapshot(null, false, 0L)
        val j = parse(own.getString("last", null)) ?: return Snapshot(null, false, 0L)
        val at = own.getLong("last_at", 0L)
        return Snapshot(j, System.currentTimeMillis() - at > STALE_AFTER_MS, at)
    }

    /** 서버에서 새로 받아 저장. 성공하면 true(실패하면 받아 둔 값은 그대로 둠). 백그라운드(WidgetSyncWorker)에서만 부를 것. */
    fun fetchAndStore(context: Context): Boolean {
        val f = flutterPrefs(context)
        val sido = f.getString("flutter.region_code", null) ?: "11"
        val sgg = f.getString("flutter.region_sgg", null)
        val key = currentKey(context)
        val body = fetch(sido, sgg, basketItems(f)) ?: return false
        if (parse(body) == null) return false
        context.getSharedPreferences(OWN, Context.MODE_PRIVATE).edit()
            .putString("last", body).putString("last_key", key).putLong("last_at", System.currentTimeMillis()).apply()
        return true
    }

    private fun parse(s: String?): JSONObject? = if (s == null) null else runCatching { JSONObject(s) }.getOrNull()

    private fun basketItems(flutter: android.content.SharedPreferences): List<String> = try {
        val raw = flutter.getString("flutter.my_basket_v2", null)
        if (raw == null) emptyList() else {
            val arr = JSONArray(raw.removePrefix(LIST_PREFIX))
            (0 until arr.length()).map { arr.getString(it) }
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun fetch(sido: String, sgg: String?, items: List<String>): String? = try {
        val c = URL("$API/widget").openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.doOutput = true
        c.connectTimeout = 8_000
        c.readTimeout = 45_000
        c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        val payload = JSONObject().put("sido", sido).put("sgg", sgg ?: JSONObject.NULL).put("items", JSONArray(items))
        c.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
        try {
            if (c.responseCode == 200) c.inputStream.bufferedReader().use { it.readText() } else null
        } finally {
            c.disconnect()
        }
    } catch (_: Exception) {
        null
    }
}

/**
 * 갱신 일정(WorkManager). 네트워크가 끊겨 있어도 위젯이 영영 멈추지 않게:
 *  - [now]: "인터넷이 연결되면 바로 한 번" 받는 작업. 오프라인이면 연결될 때까지 안드로이드가 기다렸다 실행하고, 서버 오류 등으로 실패하면 지수 백오프로 다시 시도(30초부터 늘어남).
 *  - [ensurePeriodic]: 30분마다(연결돼 있을 때만) 받는 반복 작업 — 제조사별로 `updatePeriodMillis`가 늦거나 건너뛰는 일이 있어서 겸함. 재부팅해도 유지됨.
 * 새로 받는 일은 전부 여기(백그라운드)서 함 — 위젯 `onUpdate`는 받아 둔 값을 바로 그리고 [now]만 걸어 둠(goAsync 시간 제한·메인 스레드에서 네트워크 금지).
 */
object WidgetSync {
    private const val NOW = "dailycut-widget-now"
    private const val PERIODIC = "dailycut-widget-periodic"
    private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    private fun request() = OneTimeWorkRequest.Builder(WidgetSyncWorker::class.java)
        .setConstraints(online)
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        .build()

    /** replace=true면 진행·대기 중인 것을 버리고 새로(앱에서 지역·장바구니를 바꿨을 때), false면 이미 있으면 그대로 둠. */
    fun now(context: Context, replace: Boolean = false) {
        WorkManager.getInstance(context).enqueueUniqueWork(NOW, if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request())
    }

    fun ensurePeriodic(context: Context) {
        val req = PeriodicWorkRequest.Builder(WidgetSyncWorker::class.java, 30, TimeUnit.MINUTES)
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, req)
    }

    /** 위젯이 하나도 안 남았으면 반복 작업을 끔(배터리·데이터 절약). */
    fun cancelIfNoWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val any = BaseWidget.all.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
        if (!any) {
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC)
            WorkManager.getInstance(context).cancelUniqueWork(NOW)
        }
    }
}

class WidgetSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val ok = WidgetData.fetchAndStore(applicationContext)
        // 성공이든 실패든 다시 그림(실패면 "오래된 정보" 표시가 갱신됨)
        BaseWidget.renderEverything(applicationContext, WidgetData.cached(applicationContext))
        return if (ok) Result.success() else Result.retry()
    }
}

abstract class BaseWidget : AppWidgetProvider() {
    abstract val layout: Int
    abstract fun fill(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, heightDp: Int)
    /** 누르면 열 탭(투데이 today·생활 life·문화 culture·나들이 place·혜택 money). */
    open val tab: String = "today"

    // 위젯을 처음 올렸을 때: 반복 작업을 걸고, 연결되는 대로 한 번 받음(받기 전엔 "불러오는 중"이 보임)
    override fun onEnabled(context: Context) {
        WidgetSync.ensurePeriodic(context)
        WidgetSync.now(context)
    }

    override fun onDisabled(context: Context) = WidgetSync.cancelIfNoWidgets(context)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) = WidgetSync.cancelIfNoWidgets(context)

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        renderAll(context, javaClass, WidgetData.cached(context)) // 지금 가진 값으로 즉시
        WidgetSync.ensurePeriodic(context)
        WidgetSync.now(context) // 새 값은 백그라운드에서(오프라인이면 연결될 때)
    }

    // 위젯 크기를 바꾸면(낮으면 줄을 줄임) 받아 둔 값으로 바로 다시 그림
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle) {
        render(context, manager, id, javaClass, WidgetData.cached(context))
    }

    companion object {
        val all: List<Class<out BaseWidget>> = listOf(
            WeatherWidget::class.java, WeatherOnlyWidget::class.java, BasketWidget::class.java, HousingWidget::class.java,
        )

        fun renderEverything(context: Context, snap: WidgetData.Snapshot) {
            for (cls in all) renderAll(context, cls, snap)
        }

        fun renderAll(context: Context, cls: Class<out BaseWidget>, snap: WidgetData.Snapshot) {
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, cls))) render(context, manager, id, cls, snap)
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int, cls: Class<out BaseWidget>, snap: WidgetData.Snapshot) {
            val w = cls.getDeclaredConstructor().newInstance()
            val h = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 200)
            val v = RemoteViews(context.packageName, w.layout)
            w.fill(context, v, snap.json, snap.stale, snap.at, h)
            v.setOnClickPendingIntent(R.id.widget_root, tabIntent(context, w.tab))
            // "오늘 한눈에"는 줄마다 해당 탭으로
            if (cls == WeatherWidget::class.java) {
                v.setOnClickPendingIntent(R.id.basket_row, tabIntent(context, "life"))
                v.setOnClickPendingIntent(R.id.housing_row, tabIntent(context, "money"))
                v.setOnClickPendingIntent(R.id.culture_row, tabIntent(context, "culture"))
            }
            manager.updateAppWidget(id, v)
        }

        private fun tabIntent(context: Context, tab: String): PendingIntent {
            val i = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("tab", tab)
            // 탭마다 다른 요청 번호(같으면 extra가 덮어써짐)
            return PendingIntent.getActivity(context, tab.hashCode(), i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

// ---- 공용 그리기 도구 ----
private fun Context.night(): Boolean = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

private fun gradeColor(grade: String?): Int = when (grade) {
    "좋음" -> Color.parseColor("#2F6FDB")
    "보통" -> Color.parseColor("#2E8B57")
    "나쁨" -> Color.parseColor("#E07B00")
    "매우나쁨" -> Color.parseColor("#D32F2F")
    else -> Color.GRAY
}

/** 앱의 형광펜(HighlightText)처럼 일부 글자 뒤에 섹션 색 띠를 깔아 굵게. */
private fun highlighted(prefix: String, phrase: String, color: Int, suffix: String = ""): CharSequence {
    val sb = SpannableStringBuilder(prefix)
    val start = sb.length
    sb.append(phrase)
    sb.setSpan(BackgroundColorSpan(color), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    // 형광펜 띠는 라이트·다크 모두 밝은 색, 그 위 글자는 늘 진한 색 — 글 색(@color/widget_ink)은 테마가 바뀌면 호스트가 바꾸지만
    // 이 띠 색은 그릴 때 한 번 정해져서, 다크로 바뀐 뒤에도 "밝은 글자 + 밝은 띠"로 안 읽히는 일이 없게
    sb.setSpan(ForegroundColorSpan(Color.parseColor("#191919")), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    sb.append(suffix)
    return sb
}

private fun dust(label: String, grade: String?, value: Int?): CharSequence {
    val sb = SpannableStringBuilder("$label ")
    val text = if (grade == null) "-" else if (value != null) "$grade $value" else grade
    val start = sb.length
    sb.append(text)
    sb.setSpan(ForegroundColorSpan(gradeColor(grade)), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return sb
}

private fun dateLabel(): String =
    SimpleDateFormat("M월 d일 EEEE", Locale.KOREA).apply { timeZone = TimeZone.getTimeZone("Asia/Seoul") }.format(Date())

private fun hhmm(at: Long): String =
    SimpleDateFormat("HH:mm", Locale.KOREA).apply { timeZone = TimeZone.getTimeZone("Asia/Seoul") }.format(Date(at))

/** 장바구니 변동 문장: "지난주보다 5.4% 내렸어요" / "지난주와 비슷해요" */
private fun basketDelta(context: Context, pct: Double?): CharSequence {
    if (pct == null) return "지난주 가격과 비교 중이에요"
    if (kotlin.math.abs(pct) < 0.5) return highlighted("지난주와 ", "비슷해요", context.getColor(R.color.hl_market))
    val phrase = "${String.format(Locale.KOREA, "%.1f", kotlin.math.abs(pct))}% ${if (pct < 0) "내렸어요" else "올랐어요"}"
    return highlighted("지난주보다 ", phrase, context.getColor(R.color.hl_market))
}

private fun fillWeather(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, withDate: Boolean) {
    val w = j?.optJSONObject("weather")
    if (w == null) {
        v.setTextViewText(R.id.w_region, "데일리컷")
        v.setTextViewText(R.id.w_temp, "--°")
        v.setTextViewText(R.id.w_cond, "날씨를 불러오는 중이에요")
        v.setTextViewText(R.id.w_range, "인터넷이 연결되면 새로 받아요")
        v.setTextViewText(R.id.w_pm10, "")
        v.setTextViewText(R.id.w_pm25, "")
        return
    }
    val label = w.optString("label").ifEmpty { "서울" }
    val head = if (withDate) "$label · ${dateLabel()}" else label
    v.setTextViewText(R.id.w_region, if (stale) "$head · 오래된 정보" else head)
    v.setTextViewText(R.id.w_temp, if (w.isNull("temp")) "--°" else "${w.optInt("temp")}°")
    v.setTextViewText(R.id.w_cond, w.optString("condition"))
    v.setTextViewText(R.id.w_range, if (w.isNull("high")) "" else "${w.optInt("low")}° / ${w.optInt("high")}°")
    v.setTextViewText(R.id.w_pm10, dust("미세먼지", w.optString("pm10").ifEmpty { null }, w.optInt("pm10_value", -1).takeIf { it >= 0 }))
    v.setTextViewText(R.id.w_pm25, dust("초미세먼지", w.optString("pm25").ifEmpty { null }, w.optInt("pm25_value", -1).takeIf { it >= 0 }))
}

// ---- 위젯 4종 ----
/** "오늘 한눈에"(4x3). 낮게 줄이면(150dp 미만) 날씨 + 장바구니만 남김. */
class WeatherWidget : BaseWidget() {
    override val layout = R.layout.widget_weather

    override fun fill(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, heightDp: Int) {
        fillWeather(context, v, j, stale, at, withDate = true)
        val showMore = heightDp >= 150
        val basket = j?.optJSONObject("basket")
        v.setTextViewText(R.id.basket_text, if (basket == null) "가격을 불러오는 중" else basketDelta(context, if (basket.isNull("pct")) null else basket.optDouble("pct")))

        val housing = j?.optJSONObject("housing")
        v.setTextViewText(R.id.housing_text, housingLine(context, housing))
        val culture = j?.optJSONObject("culture")
        v.setTextViewText(
            R.id.culture_text,
            if (culture == null) "이번 주 행사를 불러오는 중" else highlighted("이번 주 ", "${culture.optInt("week")}개", context.getColor(R.color.hl_culture), " 열려요"),
        )
        val vis = if (showMore) View.VISIBLE else View.GONE
        for (id in intArrayOf(R.id.housing_line, R.id.housing_row, R.id.culture_line, R.id.culture_row)) v.setViewVisibility(id, vis)
    }

    private fun housingLine(context: Context, h: JSONObject?): CharSequence {
        if (h == null) return "청약 소식을 불러오는 중"
        val first = h.optJSONObject("first")
        val open = h.optInt("open")
        return when {
            open > 0 -> highlighted("접수 중 ", "${open}건", context.getColor(R.color.hl_money), first?.let { " · ${it.optString("name")}" } ?: "")
            first != null -> "곧 접수 · ${first.optString("name")}"
            else -> "지금 접수 중인 청약이 없어요"
        }
    }
}

/** 날씨 단독(4x2): 큰 기온 + 옷차림 한 줄. */
class WeatherOnlyWidget : BaseWidget() {
    override val layout = R.layout.widget_single_weather

    override fun fill(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, heightDp: Int) {
        fillWeather(context, v, j, stale, at, withDate = true)
        val outfit = j?.optJSONObject("weather")?.optString("outfit").orEmpty()
        v.setTextViewText(R.id.w_outfit, if (stale && at > 0) "${hhmm(at)} 기준 · 인터넷이 연결되면 새로 받아요" else outfit)
    }
}

/** 장바구니 단독(2x2): 담은 품목 합계 + 지난주 대비. 담은 게 없으면 대표 8품목. */
class BasketWidget : BaseWidget() {
    override val layout = R.layout.widget_single_basket
    override val tab = "life"

    override fun fill(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, heightDp: Int) {
        val b = j?.optJSONObject("basket")
        if (b == null) {
            v.setTextViewText(R.id.b_label, "장바구니")
            v.setTextViewText(R.id.b_total, "--")
            v.setTextViewText(R.id.b_delta, "가격을 불러오는 중이에요")
            v.setTextViewText(R.id.b_note, "인터넷이 연결되면 새로 받아요")
            return
        }
        v.setTextViewText(R.id.b_label, b.optString("label"))
        v.setTextViewText(R.id.b_total, NumberFormat.getNumberInstance(Locale.KOREA).format(b.optLong("total")) + "원")
        v.setTextViewText(R.id.b_delta, basketDelta(context, if (b.isNull("pct")) null else b.optDouble("pct")))
        v.setTextViewText(R.id.b_note, if (stale && at > 0) "${hhmm(at)} 기준" else "${b.optInt("count")}품목 합계")
    }
}

/** 청약 단독(4x2): 접수 중 건수 + 마감이 가장 가까운 공고. */
class HousingWidget : BaseWidget() {
    override val layout = R.layout.widget_single_housing
    override val tab = "money"

    override fun fill(context: Context, v: RemoteViews, j: JSONObject?, stale: Boolean, at: Long, heightDp: Int) {
        val h = j?.optJSONObject("housing")
        if (h == null) {
            v.setTextViewText(R.id.h_label, "청약")
            v.setTextViewText(R.id.h_count, "--")
            v.setTextViewText(R.id.h_name, "청약 소식을 불러오는 중이에요")
            v.setTextViewText(R.id.h_sub, "인터넷이 연결되면 새로 받아요")
            return
        }
        val label = j.optJSONObject("weather")?.optString("label").orEmpty().ifEmpty { "서울" }
        v.setTextViewText(R.id.h_label, "청약 · $label")
        val open = h.optInt("open")
        val first = h.optJSONObject("first")
        v.setTextViewText(
            R.id.h_count,
            if (open > 0) highlighted("접수 중 ", "${open}건", context.getColor(R.color.hl_money)) else if (first != null) "곧 접수" else "접수 없음",
        )
        v.setTextViewText(R.id.h_name, first?.optString("name") ?: "지금 접수 중인 청약이 없어요")
        v.setTextViewText(R.id.h_sub, first?.let { "${it.optString("tag")} · ${it.optString("sub")}" } ?: "")
    }
}
