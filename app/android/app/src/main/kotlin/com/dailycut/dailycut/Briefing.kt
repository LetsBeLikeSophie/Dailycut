package com.dailycut.dailycut

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/*
 * 아침 날씨 알림(2026-10-31, 안드로이드 네이티브). 서버 푸시(FCM)가 아니라 **기기 안에서 예약하는 로컬 알림**:
 * 정한 시각이 되면 WorkManager가 서버 `/widget`(위젯과 같은 요청)으로 지금 지역 날씨를 받아 알림을 띄움 → 서버에 기기 ID·토큰이 필요 없음.
 * 켜기·끄기·시각은 앱이 `flutter.brief_time`("07:30", 없으면 꺼짐)에 저장하고 [Briefing.apply]로 알려 줌.
 * 정확한 알람(SCHEDULE_EXACT_ALARM)은 일부러 안 씀(스토어 선언 부담) → 폰의 배터리 절약 상태에 따라 몇 분 늦을 수 있음.
 * 하루 한 번: 알림을 띄운 일꾼이 다음날 같은 시각 일꾼을 걸어 둠. 이름 두 개를 번갈아 써서(실행 중인 자기 자신을 REPLACE로 지우지 않게).
 */
object Briefing {
    private const val CHANNEL = "briefing"
    private const val NAME_A = "dailycut-brief-a"
    private const val NAME_B = "dailycut-brief-b"
    private const val NOTIF_ID = 4101
    const val KEY_NAME = "name"

    fun time(context: Context): String? =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.brief_time", null)
            ?.takeIf { it.matches(Regex("\\d{1,2}:\\d{2}")) }

    /** 저장된 시각대로 걸거나(있으면) 끔. 앱이 켜질 때·설정이 바뀔 때 부름. */
    fun apply(context: Context) {
        val wm = WorkManager.getInstance(context)
        val t = time(context)
        if (t == null) {
            wm.cancelUniqueWork(NAME_A)
            wm.cancelUniqueWork(NAME_B)
            return
        }
        wm.cancelUniqueWork(NAME_B)
        enqueue(context, t, NAME_A)
    }

    private fun enqueue(context: Context, hhmm: String, name: String) {
        val (h, m) = hhmm.split(":").map { it.toInt() }
        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (!after(now)) add(Calendar.DAY_OF_YEAR, 1)
        }
        val req = OneTimeWorkRequest.Builder(BriefingWorker::class.java)
            .setInitialDelay(next.timeInMillis - now.timeInMillis, TimeUnit.MILLISECONDS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(Data.Builder().putString(KEY_NAME, name).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(name, ExistingWorkPolicy.REPLACE, req)
    }

    fun permitted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** 다음날 같은 시각 일꾼을 건다(방금 돈 일꾼과 다른 이름으로). */
    fun reschedule(context: Context, current: String?) {
        val t = time(context) ?: return
        enqueue(context, t, if (current == NAME_A) NAME_B else NAME_A)
    }

    /** 알림을 띄움. 받아 둔 날씨가 없으면 false(다시 시도), 알림이 막혀 있으면 조용히 true. */
    fun show(context: Context): Boolean {
        if (!permitted(context)) return true
        val w = WidgetData.cached(context).json?.optJSONObject("weather") ?: return false
        if (w.isNull("temp")) return false
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && mgr.getNotificationChannel(CHANNEL) == null) {
            mgr.createNotificationChannel(
                NotificationChannel(CHANNEL, "아침 날씨 알림", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "정한 시각에 오늘 날씨와 옷차림을 알려 줘요"
                },
            )
        }
        val label = w.optString("label").ifEmpty { "서울" }
        val title = "$label ${w.optInt("temp")}° ${w.optString("condition")}"
        val range = if (w.isNull("high")) "" else "최고 ${w.optInt("high")}° / 최저 ${w.optInt("low")}°"
        val dust = listOfNotNull(
            w.optString("pm10").takeIf { it.isNotEmpty() && it != "null" }?.let { "미세먼지 $it" },
            w.optString("pm25").takeIf { it.isNotEmpty() && it != "null" }?.let { "초미세먼지 $it" },
        ).joinToString(" · ")
        val outfit = w.optString("outfit").takeIf { it != "null" }.orEmpty()
        val body = listOf(range, outfit, dust).filter { it.isNotEmpty() }.joinToString("\n")
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("tab", "today"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(title)
            .setContentText(body.lineSequence().firstOrNull().orEmpty())
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(NOTIF_ID, n)
        return true
    }
}

class BriefingWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val ctx = applicationContext
        if (Briefing.time(ctx) == null) return Result.success() // 그 사이에 껐음
        val ok = WidgetData.fetchAndStore(ctx) && Briefing.show(ctx)
        // 못 받았으면 몇 번만 다시 시도(오래된 날씨를 아침 알림으로 보내지는 않음). 끝내 안 되면 오늘은 건너뛰고 내일 걸어 둠.
        if (!ok && runAttemptCount < 3) return Result.retry()
        Briefing.reschedule(ctx, inputData.getString(Briefing.KEY_NAME))
        return Result.success()
    }
}
