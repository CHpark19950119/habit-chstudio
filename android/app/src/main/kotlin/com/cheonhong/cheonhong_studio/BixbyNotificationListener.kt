package com.cheonhong.cheonhong_studio

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.LocationServices
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import android.content.BroadcastReceiver
import android.content.IntentFilter
import java.util.Calendar

/**
 * 빅스비 루틴 알림 감지 → 외출/귀가 자동 기록
 *
 * - "CHSTUDIO_OUT"  → movement.pending 기록 + GPS
 * - "CHSTUDIO_HOME" → pending이면 취소, confirmed out이면 귀가 기록
 * - 화면 ON/OFF → phone.lastScreenOn 기록 (CF 취침 판정용)
 */
class BixbyNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "BixbyListener"
        private const val UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2"
        private const val OUT_KEYWORD = "CHSTUDIO_OUT"
        private const val HOME_KEYWORD = "CHSTUDIO_HOME"
        private const val MY_BOT = "8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo"
        private const val MY_CHAT = "8724548311"
        private const val GF_BOT = "8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc"
        private const val GF_CHAT = "8624466505"
        private const val ACTIVITY_REQ_CODE = 1001
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
        val content = "$title $text"

        when {
            content.contains(OUT_KEYWORD) -> handleOut()
            content.contains(HOME_KEYWORD) -> handleHome()
        }
    }

    // ═══════════════════════════════════════════
    //  OUT — 즉시 기록 안 함, pending만 저장
    // ═══════════════════════════════════════════

    private fun handleOut() {
        Log.d(TAG, "OUT detected")

        // Firestore 즉시 기록 (GPS는 별도 비동기)
        writeOutPending(null, null)

        // GPS 1회 획득 → lastLocation 업데이트 (실패해도 무관)
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
            ) {
                val client = LocationServices.getFusedLocationProviderClient(this)
                client.lastLocation.addOnSuccessListener { location: Location? ->
                    if (location != null) {
                        iotRef().set(
                            hashMapOf("lastLocation" to hashMapOf(
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                                "updatedAt" to FieldValue.serverTimestamp()
                            )),
                            SetOptions.merge()
                        )
                        Log.d(TAG, "GPS saved: ${location.latitude},${location.longitude}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "GPS error: ${e.message}")
        }
    }

    private fun writeOutPending(lat: Double?, lng: Double?) {
        val timeStr = timeStr()

        // ★ FIX: dot notation update → 기존 returnedAtLocal 등 보존
        val updates = mutableMapOf<String, Any>(
            "movement.pending" to true,
            "movement.leftAt" to FieldValue.serverTimestamp(),
            "movement.leftAtLocal" to timeStr,
            "movement.type" to "pending"
        )

        if (lat != null && lng != null) {
            updates["lastLocation.latitude"] = lat
            updates["lastLocation.longitude"] = lng
            updates["lastLocation.updatedAt"] = FieldValue.serverTimestamp()
        }

        // SharedPreferences → Flutter 상태 동기화 (Firestore보다 먼저)
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        prefs.edit()
            .putString("flutter.nfc_state", "outing")
            .putString("flutter.nfc_state_date", todayKey())
            .apply()

        // 텔레그램 즉시 발송 (Firestore 응답 기다리지 않음)
        sendTelegram("🚶 외출 감지 $timeStr — 확인 중", meOnly = true)

        iotRef().update(updates as Map<String, Any>)
            .addOnSuccessListener {
                Log.d(TAG, "OUT pending saved: $timeStr")
                // 외출 시작 → Activity Recognition 시작
                startActivityRecognition()
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "OUT update error: ${e.message}")
                // 문서 없으면 set으로 fallback
                iotRef().set(
                    hashMapOf("movement" to hashMapOf(
                        "pending" to true,
                        "leftAt" to FieldValue.serverTimestamp(),
                        "leftAtLocal" to timeStr,
                        "type" to "pending"
                    )),
                    SetOptions.merge()
                )
                startActivityRecognition()
            }
    }

    // ═══════════════════════════════════════════
    //  HOME — pending이면 취소, confirmed이면 귀가
    // ═══════════════════════════════════════════

    private fun handleHome() {
        Log.d(TAG, "HOME detected")

        iotRef().get().addOnSuccessListener { doc ->
            @Suppress("UNCHECKED_CAST")
            val movement = doc.get("movement") as? Map<String, Any> ?: return@addOnSuccessListener
            val pending = movement["pending"] as? Boolean ?: false
            val type = movement["type"] as? String ?: ""

            if (pending) {
                // 20분 안 됐음 → pending 취소 (외출 아님)
                val returnTime = timeStr()
                iotRef().update(
                    mapOf(
                        "movement.pending" to false,
                        "movement.type" to "cancelled"
                    )
                )
                stopActivityRecognition()
                val leftLocal = movement["leftAtLocal"] as? String
                val dur = calcDuration(leftLocal, returnTime)
                sendTelegram("✅ 복귀 $returnTime — 외출 취소$dur", meOnly = true)
                Log.d(TAG, "HOME: pending cancelled (short outing)")
            } else if (type == "out") {
                // 확정된 외출에서 귀가
                confirmReturn(movement)
            }
        }
    }

    private fun confirmReturn(movement: Map<String, Any>) {
        val returnTime = timeStr()
        val dateStr = todayKey()

        // 경과시간 계산
        val leftAtLocal = movement["leftAtLocal"] as? String
        val durationStr = calcDuration(leftAtLocal, returnTime)

        // data/iot movement 업데이트 — CF onIotWrite가 timeRecords + 텔레그램 처리
        iotRef().update(
            mapOf(
                "movement.type" to "home",
                "movement.returnedAt" to FieldValue.serverTimestamp(),
                "movement.returnedAtLocal" to returnTime
            )
        )

        // 귀가 → Activity Recognition 중지
        stopActivityRecognition()

        // SharedPreferences → Flutter 상태 동기화
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        prefs.edit()
            .putString("flutter.nfc_state", "returned")
            .putString("flutter.nfc_state_date", dateStr)
            .apply()

        Log.d(TAG, "HOME: iot event written $returnTime")
    }

    // ═══════════════════════════════════════════
    //  Activity Recognition — 이동/정지 감지
    // ═══════════════════════════════════════════

    private fun activityPendingIntent(): PendingIntent {
        val intent = Intent(this, ActivityTransitionReceiver::class.java)
        return PendingIntent.getBroadcast(
            this, ACTIVITY_REQ_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    private fun startActivityRecognition() {
        // 권한 확인 (Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION)
                != PackageManager.PERMISSION_GRANTED
            ) {
                Log.w(TAG, "ACTIVITY_RECOGNITION 권한 없음 — 스킵")
                return
            }
        }

        val transitions = mutableListOf(
            // 정지 진입
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            // 걷기 진입
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.WALKING)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            // 달리기 진입
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.RUNNING)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            // 차량 진입
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            // 자전거 진입
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.ON_BICYCLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
        )

        val request = ActivityTransitionRequest(transitions)

        // 날짜 변경 시 이전 transitions 클리어
        iotRef().update(
            mapOf(
                "activity.current" to "moving",
                "activity.date" to todayKey(),
                "activity.updatedAt" to FieldValue.serverTimestamp(),
                "activity.transitions" to listOf(
                    hashMapOf("type" to "moving", "time" to timeStr())
                )
            )
        )

        ActivityRecognition.getClient(this)
            .requestActivityTransitionUpdates(request, activityPendingIntent())
            .addOnSuccessListener { Log.d(TAG, "Activity Recognition 시작") }
            .addOnFailureListener { Log.e(TAG, "Activity Recognition 실패: ${it.message}") }
    }

    private fun stopActivityRecognition() {
        ActivityRecognition.getClient(this)
            .removeActivityTransitionUpdates(activityPendingIntent())
            .addOnSuccessListener { Log.d(TAG, "Activity Recognition 중지") }
            .addOnFailureListener { Log.e(TAG, "Activity Recognition 중지 실패: ${it.message}") }
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

    private fun calcDuration(from: String?, to: String): String {
        if (from == null) return ""
        try {
            val fp = from.split(":").map { it.toInt() }
            val tp = to.split(":").map { it.toInt() }
            val m = (tp[0] * 60 + tp[1]) - (fp[0] * 60 + fp[1])
            if (m <= 0) return ""
            return " (${m / 60}h${(m % 60).toString().padStart(2, '0')}m)"
        } catch (_: Exception) {
            return ""
        }
    }

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
        }.start()
    }
}
