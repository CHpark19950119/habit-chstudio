package com.cheonhong.cheonhong_studio

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 수면 자동 감지 — Static BroadcastReceiver
 *
 * 흐름:
 * 1) MainActivity의 SCREEN_OFF 리시버가 야간 화면 끔 감지 → 30분 알람 예약
 * 2) SLEEP_CHECK 알람 → 알림 표시 ("지금 주무시나요?")
 * 3) "취침" 탭 또는 10분 무응답(AUTO_CONFIRM) → SharedPreferences에 기록
 * 4) Flutter 앱 재개 시 SleepDetectService가 읽어서 NfcService FSM 전환
 */
class SleepAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SleepDetect"
        const val CHANNEL_ID = "sleep_detection"
        const val NOTIF_ID = 9001
        const val PREFS = "FlutterSharedPreferences"

        const val ACTION_SLEEP_CHECK = "com.cheonhong.SLEEP_CHECK"
        const val ACTION_AUTO_CONFIRM = "com.cheonhong.SLEEP_AUTO_CONFIRM"
        const val ACTION_CONFIRM = "com.cheonhong.SLEEP_CONFIRM"
        const val ACTION_DISMISS = "com.cheonhong.SLEEP_DISMISS"

        private const val AUTO_CONFIRM_DELAY = 10 * 60 * 1000L  // 10분
        private const val PI_FLAGS = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        /** 30분 후 수면 확인 알람 예약 */
        fun scheduleSleepCheck(context: Context, delayMs: Long) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = makePi(context, ACTION_SLEEP_CHECK, 1001)
            am.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delayMs,
                pi
            )
            Log.d(TAG, "Sleep check alarm scheduled (${delayMs / 60000}min)")
        }

        /** 수면 확인 알람 취소 */
        fun cancelSleepCheck(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(makePi(context, ACTION_SLEEP_CHECK, 1001))
            Log.d(TAG, "Sleep check alarm cancelled")
        }

        /** 알림 채널 생성 */
        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "수면 감지",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "자동 수면 감지 알림" }
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(ch)
            }
        }

        private fun makePi(context: Context, action: String, code: Int): PendingIntent {
            val intent = Intent(context, SleepAlarmReceiver::class.java).apply {
                this.action = action
            }
            return PendingIntent.getBroadcast(context, code, intent, PI_FLAGS)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.sleep_detect_enabled", false)) return

        when (intent.action) {
            ACTION_SLEEP_CHECK -> {
                Log.d(TAG, "30min elapsed — showing notification")
                createChannel(context)
                showNotification(context)
                scheduleAutoConfirm(context)
            }
            ACTION_AUTO_CONFIRM -> {
                Log.d(TAG, "Auto-confirm — no response")
                confirmSleep(context, prefs)
            }
            ACTION_CONFIRM -> {
                Log.d(TAG, "User confirmed sleep")
                cancelAutoConfirm(context)
                confirmSleep(context, prefs)
            }
            ACTION_DISMISS -> {
                Log.d(TAG, "User dismissed — not sleeping")
                cancelAutoConfirm(context)
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .cancel(NOTIF_ID)
            }
        }
    }

    private fun showNotification(context: Context) {
        val confirmPi = makePi(context, ACTION_CONFIRM, 2001)
        val dismissPi = makePi(context, ACTION_DISMISS, 2002)

        val notif = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("지금 주무시나요?")
            .setContentText("10분 내 응답 없으면 자동으로 취침 기록됩니다")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .addAction(0, "😴 취침", confirmPi)
            .addAction(0, "아직", dismissPi)
            .build()

        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, notif)
    }

    private fun scheduleAutoConfirm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = makePi(context, ACTION_AUTO_CONFIRM, 1002)
        am.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + AUTO_CONFIRM_DELAY,
            pi
        )
    }

    private fun cancelAutoConfirm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(makePi(context, ACTION_AUTO_CONFIRM, 1002))
    }

    private fun confirmSleep(context: Context, prefs: SharedPreferences) {
        // screen_off_time = 화면 꺼진 시각 (≈ 수면 시작)
        val screenOffTime = prefs.getString("flutter.screen_off_time", null)
            ?: System.currentTimeMillis().toString()

        prefs.edit()
            .putBoolean("flutter.sleep_detected", true)
            .putString("flutter.sleep_detected_time", screenOffTime)
            .apply()

        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIF_ID)
        Log.d(TAG, "Sleep confirmed — onset=$screenOffTime")
    }
}
