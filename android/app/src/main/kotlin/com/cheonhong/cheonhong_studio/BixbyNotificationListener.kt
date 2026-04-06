package com.cheonhong.cheonhong_studio

import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import android.content.BroadcastReceiver
import android.content.IntentFilter
import java.util.Calendar

/**
 * AppNotificationListener — 알림 감지 기반 자동화
 *
 * - Tuya 도어센서 알림 → 자동 기상 (07:00~15:00, 하루 1번)
 * - 화면 ON/OFF → phone.lastScreenOn 기록 (CF 취침 판정용)
 * - 외출/귀가는 OwnTracks webhook으로 대체됨
 */
class BixbyNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "AppNotifListener"
        // ★ AUDIT FIX: S-01 — TODO: BuildConfig 또는 local.properties로 이동
        private const val UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2"
        private const val MY_BOT = "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50"
        private const val MY_CHAT = "8724548311"
        private const val GF_BOT = "8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc"
        private const val GF_CHAT = "8624466505"
        private const val SCREEN_THROTTLE_MS = 5 * 60 * 1000L  // 5분 throttle
    }

    private fun db() = FirebaseFirestore.getInstance()
    private fun iotRef() = db().document("users/$UID/data/iot")

    // ★ 서비스 시작 시각 — 이전 알림 무시용
    private val serviceStartTime = System.currentTimeMillis()

    // ★ 화면 상태 감지
    private var screenReceiver: BroadcastReceiver? = null
    private var lastScreenOnWrite = 0L

    override fun onCreate() {
        super.onCreate()
        registerScreenReceiver()
    }

    override fun onDestroy() {
        unregisterScreenReceiver()
        super.onDestroy()
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) return
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> {
                        val now = System.currentTimeMillis()
                        if (now - lastScreenOnWrite < SCREEN_THROTTLE_MS) return
                        lastScreenOnWrite = now
                        iotRef().update(
                            mapOf("phone.lastScreenOn" to FieldValue.serverTimestamp())
                        ).addOnFailureListener {
                            iotRef().set(
                                hashMapOf("phone" to hashMapOf("lastScreenOn" to FieldValue.serverTimestamp())),
                                SetOptions.merge()
                            )
                        }
                        Log.d(TAG, "Screen ON → phone.lastScreenOn updated")
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        Log.d(TAG, "Screen receiver registered")
    }

    private fun unregisterScreenReceiver() {
        screenReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        screenReceiver = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return

        // ★ FIX: 서비스 시작 전에 게시된 알림 무시 (앱 업데이트 시 재처리 방지)
        if (sbn.postTime < serviceStartTime) {
            Log.d(TAG, "Ignoring old notification (postTime=${sbn.postTime} < start=$serviceStartTime)")
            return
        }

        val extras = notification.extras ?: return
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""

        // ★ Tuya 도어센서 알림 감지 (com.tuya.smart)
        val pkg = sbn.packageName ?: ""
        if (pkg == "com.tuya.smart") {
            handleTuyaNotification(title, text, sbn.key)
            return
        }

        // 외출/귀가는 OwnTracks webhook으로 처리 — 여기서는 무시
    }

    // ═══════════════════════════════════════════
    //  유틸
    // ═══════════════════════════════════════════

    private fun timeStr(): String {
        val cal = Calendar.getInstance()
        return String.format(
            "%02d:%02d",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE)
        )
    }

    private fun todayKey(): String {
        val cal = Calendar.getInstance()
        if (cal.get(Calendar.HOUR_OF_DAY) < 4) {
            cal.add(Calendar.DAY_OF_MONTH, -1)
        }
        return String.format(
            "%d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH)
        )
    }

    // ═══════════════════════════════════════════
    //  Tuya 도어센서 → iot.door rawEvent만 기록 (판단은 CF가)
    // ═══════════════════════════════════════════

    private var lastDoorEventTime = 0L
    private val DOOR_EVENT_COOLDOWN = 30_000L  // 30초 쿨다운

    private fun handleTuyaNotification(title: String, text: String, notifKey: String) {
        val combined = "$title $text".lowercase()

        // 도어센서 관련 알림만 처리
        val doorKeywords = listOf("문", "door", "열림", "open", "닫힘", "close", "센서", "sensor", "기상")
        val isDoorRelated = doorKeywords.any { combined.contains(it) }
        if (!isDoorRelated) {
            Log.d(TAG, "Tuya non-door notification ignored: title=$title text=$text")
            return
        }

        // 쿨다운 (30초 이내 중복 방지)
        val now = System.currentTimeMillis()
        if (now - lastDoorEventTime < DOOR_EVENT_COOLDOWN) return
        lastDoorEventTime = now

        val isOpen = listOf("열림", "open", "기상").any { combined.contains(it) }
        val state = if (isOpen) "open" else "closed"

        // ★ iot.door에 raw event만 기록 — 판단(기상/외출 등)은 CF가 한다
        iotRef().set(
            hashMapOf("door" to hashMapOf(
                "state" to state,
                "isOpen" to isOpen,
                "lastChanged" to FieldValue.serverTimestamp(),
                "lastEventTime" to timeStr(),
                "lastEventDate" to todayKey(),
                "source" to "tuya_notification"
            )),
            SetOptions.merge()
        )

        Log.d(TAG, "Door event relayed: state=$state time=${timeStr()}")

        // 알림 자동 삭제
        try { cancelNotification(notifKey) } catch (_: Exception) {}
    }

    // ★ AUDIT FIX: A-02 — Thread 내 예외를 UncaughtExceptionHandler로 로깅
    private fun sendTelegram(msg: String, meOnly: Boolean = false) {
        Thread {
            try {
                val bots = if (meOnly) arrayOf(MY_BOT to MY_CHAT)
                           else arrayOf(MY_BOT to MY_CHAT, GF_BOT to GF_CHAT)
                for ((token, chatId) in bots) {
                    val url = java.net.URL("https://api.telegram.org/bot$token/sendMessage")
                    val conn = url.openConnection() as java.net.HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    conn.doOutput = true
                    conn.outputStream.write(
                        """{"chat_id":"$chatId","text":"$msg"}""".toByteArray(Charsets.UTF_8)
                    )
                    conn.responseCode
                    conn.disconnect()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Telegram error: ${e.message}")
            }
        }.apply {
            uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, e ->
                Log.e(TAG, "Telegram thread uncaught: ${e.message}")
            }
        }.start()
    }
}
