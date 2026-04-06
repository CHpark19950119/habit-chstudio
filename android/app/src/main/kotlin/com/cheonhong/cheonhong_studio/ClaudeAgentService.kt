package com.cheonhong.cheonhong_studio

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.util.Calendar
import java.util.Locale

/**
 * ClaudeAgentService — 접근성 서비스 기반 폰 사용 감시/제어
 *
 * 기능:
 * 1. 포그라운드 앱 전환 감지 + 사용시간 추적
 * 2. 화면 텍스트 읽기 (AccessibilityNodeInfo)
 * 3. 오버레이 경고 팝업 표시
 * 4. Firestore 양방향 통신 (로그 기록 + 명령 수신)
 * 5. 규칙 엔진 (공부시간 유튜브/게임 차단, 취침시간 경고, 누적 30분 경고)
 */
class ClaudeAgentService : AccessibilityService() {

    companion object {
        private const val TAG = "ClaudeAgent"
        // ★ AUDIT FIX: S-01 — TODO: BuildConfig 또는 local.properties로 이동
        private const val UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2"

        // 싱글톤 참조 — Flutter MethodChannel에서 상태 조회용
        var instance: ClaudeAgentService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    // ─── Firestore ───
    private fun db() = FirebaseFirestore.getInstance()
    private fun iotRef() = db().document("users/$UID/data/iot")

    // ─── 앱 사용 추적 ───
    private var currentApp: String = ""
    private var appStartTime: Long = 0L
    private val appUsageMap = mutableMapOf<String, Long>() // 패키지 → 누적 밀리초

    // ─── 규칙 엔진 ───
    private var rulesEnabled = true
    private var studyHoursStart = 9   // 공부 시간 시작 (기본 09:00)
    private var studyHoursEnd = 23    // 공부 시간 종료 (기본 23:00)
    private var warnThresholdMin = 3  // 유튜브/게임 경고까지 분
    private var dailyLimitMin = 30    // 일일 앱 사용 제한 (분)

    // 차단 대상 패키지
    private val blockedApps = setOf(
        "com.google.android.youtube",
        "com.ss.android.ugc.trill",       // TikTok
        "com.zhiliaoapp.musically",        // TikTok 글로벌
        "com.instagram.android",
        "com.twitter.android",
        "com.reddit.frontpage",
        "com.discord",
        "tv.twitch.android.app",
    )

    // 게임 패키지 감지 키워드
    private val gameKeywords = listOf("game", "nexon", "netmarble", "ncsoft", "krafton", "supercell")

    // ─── 오버레이 ───
    private var overlayView: LinearLayout? = null
    private var windowManager: WindowManager? = null
    private val handler = Handler(Looper.getMainLooper())

    // ─── TTS 엔진 ───
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    // ─── Firestore 명령 리스너 ───
    private var commandListener: ListenerRegistration? = null

    // ─── 경고 쿨다운 ───
    private var lastWarningTime = 0L
    private val WARNING_COOLDOWN_MS = 60_000L // 1분

    // ═══════════════════════════════════════════
    //  라이프사이클
    // ═══════════════════════════════════════════

    // 알림 관련 패키지 — 이벤트 무시 대상
    private val notificationPackages = setOf(
        "com.android.systemui",
        "com.samsung.android.app.smartcapture",
        "com.samsung.android.incallui",
        "com.samsung.android.messaging",
        "com.samsung.android.app.cocktailbarservice",  // Edge panels
        "com.samsung.android.app.aodservice",           // Always On Display
        "com.samsung.android.pluginplatform.res",
        "android",                                       // 시스템 프레임워크
        "com.android.providers.downloads.ui",
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        // 접근성 설정 — 최소 권한, 알림 팝업 방해 방지
        serviceInfo = serviceInfo?.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 500
            // FLAG_REPORT_VIEW_IDS만 — FLAG_RETRIEVE_INTERACTIVE_WINDOWS 사용 안 함
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            // 차단 대상 앱만 감시 (xml에서도 설정하지만 코드에서도 보강)
            packageNames = blockedApps.toTypedArray()
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // TTS 초기화
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.KOREAN
            }
            Log.d(TAG, "TTS 초기화: ${if (ttsReady) "성공" else "실패"}")
        }

        // 설정 로드
        loadPrefs()

        // Firestore 명령 리스너 시작
        startCommandListener()

        Log.d(TAG, "★ ClaudeAgentService 시작됨")
    }

    override fun onDestroy() {
        instance = null
        commandListener?.remove()
        dismissOverlay()
        tts?.shutdown()
        tts = null
        Log.d(TAG, "ClaudeAgentService 종료됨")
        super.onDestroy()
    }

    override fun onInterrupt() {
        Log.d(TAG, "ClaudeAgentService 중단됨")
    }

    // ═══════════════════════════════════════════
    //  접근성 이벤트 핸들러
    // ═══════════════════════════════════════════

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // TYPE_WINDOW_STATE_CHANGED 이외는 전부 무시
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return

        // ── 알림/팝업 관련 이벤트 즉시 무시 (헤드업 알림 억제 방지) ──
        // 1. 자기 자신
        if (pkg == packageName) return
        // 2. 알림/시스템 관련 패키지
        if (pkg in notificationPackages) return
        // 3. 시스템 앱 전체
        if (pkg.startsWith("com.android.")) return
        // 4. 삼성 시스템 앱
        if (pkg.startsWith("com.samsung.")) return
        // 5. 삼성 SEC 앱 (시스템 컴포넌트)
        if (pkg.startsWith("com.sec.")) return
        // 6. 보호 앱 (텔레그램, 카톡)
        if (pkg == "org.telegram.messenger") return
        if (pkg == "com.kakao.talk") return

        // ── 차단 대상 앱만 처리 ──
        val isBlocked = blockedApps.contains(pkg) ||
            gameKeywords.any { pkg.lowercase().contains(it) }
        if (!isBlocked) return

        onAppChanged(pkg)
    }

    // ═══════════════════════════════════════════
    //  앱 전환 감지 + 사용시간 추적
    // ═══════════════════════════════════════════

    private fun onAppChanged(newApp: String) {
        val now = System.currentTimeMillis()

        // 이전 앱 사용시간 기록
        if (currentApp.isNotEmpty() && appStartTime > 0) {
            val elapsed = now - appStartTime
            if (elapsed > 1000) { // 1초 이상만
                val prev = appUsageMap.getOrDefault(currentApp, 0L)
                appUsageMap[currentApp] = prev + elapsed
            }
        }

        // 새 앱 시작
        if (newApp != currentApp) {
            Log.d(TAG, "앱 전환: $currentApp → $newApp")
            currentApp = newApp
            appStartTime = now

            // 규칙 체크
            if (rulesEnabled) {
                checkRules(newApp)
            }
        }
    }

    // ═══════════════════════════════════════════
    //  규칙 엔진
    // ═══════════════════════════════════════════

    private fun checkRules(pkg: String) {
        val cal = Calendar.getInstance()
        val hour = cal.get(Calendar.HOUR_OF_DAY)

        // 규칙 1: 취침 시간 (01:00~06:00) 폰 사용 경고
        if (hour in 1..5) {
            showWarningThrottled("취침 시간입니다. 폰을 내려놓으세요.", "sleep")
            return
        }

        // 규칙 2: 공부 시간에 차단 앱 열면 경고
        val isStudyHours = hour in studyHoursStart until studyHoursEnd
        val isBlocked = blockedApps.contains(pkg) || gameKeywords.any { pkg.lowercase().contains(it) }

        if (isStudyHours && isBlocked) {
            // 3분 후 경고 (즉시 경고 안 함)
            val appName = getAppLabel(pkg)
            handler.postDelayed({
                if (currentApp == pkg) {
                    showWarningThrottled("공부 시간에 $appName 사용 중. 집중하세요.", "study")
                    logWarning(pkg, "study_time_violation")
                }
            }, warnThresholdMin * 60_000L)
            return
        }

        // 규칙 3: 일일 누적 30분 초과 경고
        val totalUsageMin = appUsageMap.values.sum() / 60_000
        if (totalUsageMin > dailyLimitMin) {
            showWarningThrottled("오늘 폰 사용 ${totalUsageMin}분. 제한(${dailyLimitMin}분) 초과.", "daily_limit")
        }
    }

    private fun showWarningThrottled(message: String, type: String) {
        val now = System.currentTimeMillis()
        if (now - lastWarningTime < WARNING_COOLDOWN_MS) return
        lastWarningTime = now

        showOverlay(message)
        logWarning(currentApp, type)
    }

    // ═══════════════════════════════════════════
    //  오버레이 경고 팝업
    // ═══════════════════════════════════════════

    fun showOverlay(message: String, durationMs: Long = 8000L) {
        // ★ 알림으로 확실하게 표시
        showNotification(message = message)

        // 오버레이도 시도 (실패해도 알림은 이미 감)
        handler.post {
            dismissOverlay()

            val layout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xE6000000.toInt()) // 반투명 검정
                setPadding(48, 40, 48, 40)
                gravity = Gravity.CENTER
            }

            // 제목
            val titleView = TextView(this).apply {
                text = "⚠ CLAUDE AGENT"
                setTextColor(0xFFFFD700.toInt())
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 16)
            }
            layout.addView(titleView)

            // 메시지
            val msgView = TextView(this).apply {
                text = message
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 15f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 24)
            }
            layout.addView(msgView)

            // 닫기 안내
            val closeView = TextView(this).apply {
                text = "자동으로 사라집니다"
                setTextColor(0x99FFFFFF.toInt())
                textSize = 11f
                gravity = Gravity.CENTER
            }
            layout.addView(closeView)

            val params = WindowManager.LayoutParams().apply {
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.WRAP_CONTENT
                type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
                format = PixelFormat.TRANSLUCENT
                gravity = Gravity.CENTER
                flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            }

            try {
                windowManager?.addView(layout, params)
                overlayView = layout

                // 자동 닫기
                handler.postDelayed({ dismissOverlay() }, durationMs)
            } catch (e: Exception) {
                Log.e(TAG, "오버레이 표시 실패: ${e.message}")
            }
        }
    }

    fun dismissOverlay() {
        handler.post {
            overlayView?.let {
                try { windowManager?.removeView(it) } catch (_: Exception) {}
            }
            overlayView = null
        }
    }

    fun showNotification(title: String = "⚠ CLAUDE AGENT", message: String) {
        val channelId = "claude_agent_alert"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Claude Agent", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Claude Agent 경고 알림"
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        nm.notify(9999, notification)
        Log.d(TAG, "알림 표시: $message")
    }

    // ═══════════════════════════════════════════
    //  화면 텍스트 읽기
    // ═══════════════════════════════════════════

    /**
     * 화면 텍스트 읽기 — canRetrieveWindowContent=false이므로 비활성화됨.
     * ADB `uiautomator dump`로 대체: adb shell uiautomator dump /dev/tty
     */
    fun getScreenText(): String {
        Log.d(TAG, "getScreenText: canRetrieveWindowContent=false — ADB uiautomator로 대체 필요")
        return "(canRetrieveWindowContent disabled — use ADB uiautomator dump)"
    }

    // ═══════════════════════════════════════════
    //  Firestore 로그 기록
    // ═══════════════════════════════════════════

    /** 앱 사용 로그를 Firestore에 기록 */
    fun flushUsageLog() {
        val cal = Calendar.getInstance()
        val timeStr = String.format("%02d:%02d", cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))

        // 상위 5개 앱만 기록 (비어있으면 빈 리스트)
        val topApps = appUsageMap.entries
            .sortedByDescending { it.value }
            .take(5)
            .map { entry ->
                hashMapOf(
                    "app" to entry.key,
                    "label" to getAppLabel(entry.key),
                    "minutes" to (entry.value / 60_000)
                )
            }

        val data = hashMapOf(
            "agent.appUsage" to hashMapOf(
                "updatedAt" to FieldValue.serverTimestamp(),
                "time" to timeStr,
                "currentApp" to currentApp.ifEmpty { "unknown" },
                "currentAppLabel" to if (currentApp.isNotEmpty()) getAppLabel(currentApp) else "unknown",
                "topApps" to topApps,
                "totalMinutes" to (appUsageMap.values.sum() / 60_000)
            )
        )

        iotRef().set(data, SetOptions.merge())
            .addOnSuccessListener { Log.d(TAG, "앱 사용 로그 기록 완료") }
            .addOnFailureListener { Log.e(TAG, "앱 사용 로그 기록 실패: ${it.message}") }
    }

    private fun logWarning(pkg: String, type: String) {
        val cal = Calendar.getInstance()
        val timeStr = String.format("%02d:%02d", cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))

        val data = hashMapOf(
            "agent.lastWarning" to hashMapOf(
                "time" to timeStr,
                "type" to type,
                "app" to pkg,
                "label" to getAppLabel(pkg),
                "ts" to FieldValue.serverTimestamp()
            )
        )

        iotRef().set(data, SetOptions.merge())
    }

    // ═══════════════════════════════════════════
    //  Firestore 명령 수신
    // ★ AUDIT FIX: A-03 — TODO: Firestore Security Rules로 iot.agent.command 쓰기를 인증된 사용자만 허용
    // 현재 Firestore Rules가 open이면 누구나 원격 명령 실행 가능 (S-03과 연계)
    // ═══════════════════════════════════════════

    private fun startCommandListener() {
        commandListener = iotRef().addSnapshotListener { snapshot, error ->
            if (error != null || snapshot == null) return@addSnapshotListener

            @Suppress("UNCHECKED_CAST")
            val agentMap = snapshot.get("agent") as? Map<String, Any> ?: return@addSnapshotListener
            val cmd = agentMap["command"] as? Map<String, Any> ?: return@addSnapshotListener
            val action = cmd["action"] as? String ?: return@addSnapshotListener
            val handled = cmd["handled"] as? Boolean ?: false

            if (handled) return@addSnapshotListener

            Log.d(TAG, "명령 수신: $action")

            when (action) {
                // 오버레이 경고 표시
                "showOverlay" -> {
                    val msg = cmd["message"] as? String ?: "주의!"
                    val duration = (cmd["duration"] as? Long) ?: 8000L
                    showOverlay(msg, duration)
                }
                // 홈으로 보내기 (현재 앱 종료)
                "goHome" -> {
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
                // 뒤로가기
                "goBack" -> {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                }
                // 화면 텍스트 읽기 → Firestore에 결과 기록
                "readScreen" -> {
                    val text = getScreenText()
                    iotRef().update(
                        "agent.screenText", hashMapOf(
                            "text" to text,
                            "app" to currentApp,
                            "ts" to FieldValue.serverTimestamp()
                        )
                    )
                }
                // 규칙 활성화/비활성화
                "setRules" -> {
                    rulesEnabled = cmd["enabled"] as? Boolean ?: true
                    savePrefs()
                }
                // 앱 사용 로그 즉시 기록
                "flushLog" -> {
                    flushUsageLog()
                }
                // 설정 업데이트
                "updateSettings" -> {
                    (cmd["studyHoursStart"] as? Long)?.let { studyHoursStart = it.toInt() }
                    (cmd["studyHoursEnd"] as? Long)?.let { studyHoursEnd = it.toInt() }
                    (cmd["warnThresholdMin"] as? Long)?.let { warnThresholdMin = it.toInt() }
                    (cmd["dailyLimitMin"] as? Long)?.let { dailyLimitMin = it.toInt() }
                    savePrefs()
                }
                // 앱 강제 종료
                "killApp" -> {
                    val pkg = cmd["package"] as? String
                    if (pkg != null) {
                        killApp(pkg)
                    }
                }
                // URL 열기 (크롬)
                "openUrl" -> {
                    val url = cmd["url"] as? String
                    if (url != null) {
                        openUrl(url)
                    }
                }
                // 앱 실행
                "openApp" -> {
                    val pkg = cmd["package"] as? String
                    if (pkg != null) {
                        openApp(pkg)
                    }
                }
                // 볼륨 제어
                "setVolume" -> {
                    val level = (cmd["level"] as? Long)?.toInt() ?: 7
                    setVolume(level)
                }
                // 화면 밝기
                "setBrightness" -> {
                    val level = (cmd["level"] as? Long)?.toInt() ?: 128
                    setBrightness(level)
                }
                // 화면 잠금
                "lockScreen" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
                    }
                }
                // TTS 음성 경고
                "speak" -> {
                    val text = cmd["text"] as? String ?: "알림"
                    speak(text)
                }
                // 앱 사용 리포트
                "getAppUsageReport" -> {
                    getAppUsageReport()
                }
            }

            // 처리 완료 마킹
            iotRef().update("agent.command.handled", true)
        }
    }

    // ═══════════════════════════════════════════
    //  원격 명령 구현
    // ═══════════════════════════════════════════

    /** 앱 강제 종료 — 최근 앱 목록에서 제거 방식 */
    private fun killApp(pkg: String) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            @Suppress("DEPRECATION")
            am.killBackgroundProcesses(pkg)
            // 홈으로 보내서 포그라운드도 중단
            if (currentApp == pkg) {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
            Log.d(TAG, "앱 종료: $pkg")
        } catch (e: Exception) {
            Log.e(TAG, "앱 종료 실패: ${e.message}")
        }
    }

    /** URL을 기본 브라우저로 열기 */
    private fun openUrl(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            Log.d(TAG, "URL 열기: $url")
        } catch (e: Exception) {
            Log.e(TAG, "URL 열기 실패: ${e.message}")
        }
    }

    /** 앱 실행 */
    private fun openApp(pkg: String) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.d(TAG, "앱 실행: $pkg")
            } else {
                Log.e(TAG, "앱 실행 실패: $pkg 런치 인텐트 없음")
            }
        } catch (e: Exception) {
            Log.e(TAG, "앱 실행 실패: ${e.message}")
        }
    }

    /** 미디어 볼륨 설정 (0~15) */
    private fun setVolume(level: Int) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val clamped = level.coerceIn(0, maxVol)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, clamped, 0)
            Log.d(TAG, "볼륨 설정: $clamped/$maxVol")
        } catch (e: Exception) {
            Log.e(TAG, "볼륨 설정 실패: ${e.message}")
        }
    }

    /** 화면 밝기 설정 (0~255) */
    private fun setBrightness(level: Int) {
        try {
            // 자동 밝기 끄기
            Settings.System.putInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            val clamped = level.coerceIn(0, 255)
            Settings.System.putInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                clamped
            )
            Log.d(TAG, "밝기 설정: $clamped/255")
        } catch (e: Exception) {
            Log.e(TAG, "밝기 설정 실패 (WRITE_SETTINGS 권한 필요): ${e.message}")
        }
    }

    /** TTS 음성 출력 */
    private fun speak(text: String) {
        if (ttsReady && tts != null) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "claude_agent_speak")
            Log.d(TAG, "TTS 발화: $text")
        } else {
            Log.e(TAG, "TTS 미준비, 알림으로 대체")
            showNotification(message = "🔊 $text")
        }
    }

    /** UsageStatsManager로 오늘 앱 사용 리포트 생성 → Firestore 기록 */
    private fun getAppUsageReport() {
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = Calendar.getInstance()
            val endTime = cal.timeInMillis
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            val startTime = cal.timeInMillis

            val stats = usm.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, startTime, endTime
            )

            val report = mutableListOf<Map<String, Any>>()
            if (stats != null) {
                for (s in stats) {
                    val totalMin = (s.totalTimeInForeground / 60_000).toInt()
                    if (totalMin < 1) continue
                    val pkg = s.packageName
                    // 시스템 앱 필터
                    if (pkg.startsWith("com.android.") || pkg.startsWith("com.sec.") ||
                        pkg == packageName || pkg.startsWith("com.samsung.")) continue

                    report.add(mapOf(
                        "package" to pkg,
                        "label" to getAppLabel(pkg),
                        "minutes" to totalMin
                    ))
                }
            }

            val sorted = report.sortedByDescending { it["minutes"] as Int }.take(15)
            val totalMin = sorted.sumOf { it["minutes"] as Int }

            val now = Calendar.getInstance()
            val timeStr = String.format("%02d:%02d", now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE))

            val data = hashMapOf(
                "agent.usageReport" to hashMapOf(
                    "ts" to FieldValue.serverTimestamp(),
                    "time" to timeStr,
                    "totalMinutes" to totalMin,
                    "apps" to sorted
                )
            )

            iotRef().set(data, SetOptions.merge())
                .addOnSuccessListener { Log.d(TAG, "앱 사용 리포트 기록 완료 (${sorted.size}개 앱, ${totalMin}분)") }
                .addOnFailureListener { Log.e(TAG, "앱 사용 리포트 기록 실패: ${it.message}") }

        } catch (e: Exception) {
            Log.e(TAG, "앱 사용 리포트 실패: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════
    //  SharedPreferences (설정 저장)
    // ═══════════════════════════════════════════

    private fun loadPrefs() {
        val prefs = getSharedPreferences("claude_agent", Context.MODE_PRIVATE)
        rulesEnabled = prefs.getBoolean("rules_enabled", true)
        studyHoursStart = prefs.getInt("study_start", 9)
        studyHoursEnd = prefs.getInt("study_end", 23)
        warnThresholdMin = prefs.getInt("warn_threshold", 3)
        dailyLimitMin = prefs.getInt("daily_limit", 30)
    }

    private fun savePrefs() {
        getSharedPreferences("claude_agent", Context.MODE_PRIVATE).edit().apply {
            putBoolean("rules_enabled", rulesEnabled)
            putInt("study_start", studyHoursStart)
            putInt("study_end", studyHoursEnd)
            putInt("warn_threshold", warnThresholdMin)
            putInt("daily_limit", dailyLimitMin)
            apply()
        }
    }

    // ═══════════════════════════════════════════
    //  유틸
    // ═══════════════════════════════════════════

    private fun getAppLabel(pkg: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(ai).toString()
        } catch (_: Exception) {
            pkg.substringAfterLast('.')
        }
    }

    /** 현재 상태 요약 (Flutter에서 조회) */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "running" to true,
            "rulesEnabled" to rulesEnabled,
            "currentApp" to currentApp,
            "totalMinutes" to (appUsageMap.values.sum() / 60_000),
            "trackedApps" to appUsageMap.size,
            "studyHours" to "$studyHoursStart~$studyHoursEnd",
            "dailyLimitMin" to dailyLimitMin
        )
    }
}
