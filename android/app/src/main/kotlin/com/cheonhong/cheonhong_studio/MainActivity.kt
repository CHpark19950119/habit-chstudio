package com.cheonhong.cheonhong_studio

import android.accessibilityservice.AccessibilityService
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.util.Log

class MainActivity : FlutterActivity() {

    private val FOCUS_CHANNEL = "com.cheonhong.cheonhong_studio/focus_mode"
    private val USAGE_CHANNEL = "com.cheonhong.cheonhong_studio/usage_stats"
    private val WIFI_CHANNEL = "com.cheonhong.cheonhong_studio/wifi"
    private val VOLUME_CHANNEL = "com.cheonhong.cheonhong_studio/volume"
    private val APP_CHANNEL = "com.cheonhong.cheonhong_studio/app"
    private val BROWSER_CHANNEL = "com.cheonhong.cheonhong_studio/browser"
    private val NOTIF_LISTENER_CHANNEL = "com.cheonhong.cheonhong_studio/notif_listener"
    private val AGENT_CHANNEL = "com.cheonhong.cheonhong_studio/claude_agent"
    private var _bgmPlayer: MediaPlayer? = null
    private var _bgmFocusRequest: android.media.AudioFocusRequest? = null


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

// ─── App 채널 (알림 표시, 권한 요청) ───
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
    when (call.method) {
        "flutterReady" -> {
            result.success(true)
        }
        "showNotification" -> {
            val title = call.argument<String>("title") ?: "알림"
            val body = call.argument<String>("body") ?: ""
            showAppNotification(title, body)
            result.success(true)
        }
        "requestNotificationPermission" -> {
            requestPostNotificationsPermission()
            result.success(true)
        }
        else -> result.notImplemented()
    }
}

        // ─── Browser 채널 (URL 열기) ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BROWSER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    } else {
                        result.error("NO_URL", "URL is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 앱 사용 통계 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    result.success(hasUsageStatsPermission())
                }
                "requestPermission" -> {
                    if (!hasUsageStatsPermission()) {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    }
                    result.success(true)
                }
                "getTodayUsage" -> {
                    if (!hasUsageStatsPermission()) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    result.success(getTodayUsageStats())
                }
                else -> result.notImplemented()
            }
        }

        // ─── WiFi SSID 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWifiSsid" -> {
                    result.success(getCurrentWifiSsid())
                }
                else -> result.notImplemented()
            }
        }

        // ─── 집중모드 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOCUS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableDnd" -> {
                    enableDndMode()
                    result.success(true)
                }
                "disableDnd" -> {
                    disableDndMode()
                    result.success(true)
                }
                "getForegroundApp" -> {
                    result.success(getForegroundPackage())
                }
                "showBlockOverlay" -> {
                    // TODO: SYSTEM_ALERT_WINDOW 오버레이
                    result.success(true)
                }
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "lockScreen" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComp = ComponentName(this, AdminReceiver::class.java)
                    if (dpm.isAdminActive(adminComp)) {
                        moveTaskToBack(true)
                        dpm.lockNow()
                        result.success(true)
                    } else {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComp)
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "포커스 모드에서 화면 잠금에 사용됩니다")
                        }
                        startActivity(intent)
                        result.success(false)
                    }
                }
                "isAdminActive" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComp = ComponentName(this, AdminReceiver::class.java)
                    result.success(dpm.isAdminActive(adminComp))
                }
                else -> result.notImplemented()
            }
        }

        // ─── 볼륨 제어 채널 (TTS 무음모드 우회) ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "getVolume" -> {
                    result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC))
                }
                "getMaxVolume" -> {
                    result.success(am.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                }
                "setVolume" -> {
                    val vol = call.argument<Int>("volume") ?: 10
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, vol, 0)
                    result.success(true)
                }
                "getRingerMode" -> {
                    result.success(am.ringerMode)
                }
                "setRingerMode" -> {
                    val mode = call.argument<Int>("mode") ?: AudioManager.RINGER_MODE_NORMAL
                    try {
                        am.ringerMode = mode
                        result.success(true)
                    } catch (e: SecurityException) {
                        // DND 권한 없으면 실패 가능
                        result.success(false)
                    }
                }
                // ═══ #5b: 브리핑 배경음 시작 ═══
                "startBriefingBgm" -> {
                    val bgm = call.argument<String>("bgm") ?: "none"
                    if (bgm == "none") {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    try {
                        _bgmPlayer?.release()
                        _bgmPlayer = null
                        val filename = "bgm/$bgm.ogg"
                        val afd = assets.openFd(filename)
                        _bgmPlayer = MediaPlayer().apply {
                            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                            afd.close()
                            // AudioAttributes: USAGE_MEDIA → TTS(USAGE_ASSISTANT)와 독립 스트림
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                setAudioAttributes(android.media.AudioAttributes.Builder()
                                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .build())
                            }
                            isLooping = true
                            setVolume(0.12f, 0.12f)
                            prepare()
                            start()
                        }
                        // AudioFocus duck 리스너: TTS 재생 시 볼륨 낮추고, 끝나면 복원
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            _bgmFocusRequest = android.media.AudioFocusRequest.Builder(
                                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                            ).setOnAudioFocusChangeListener { change ->
                                when (change) {
                                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
                                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                        _bgmPlayer?.setVolume(0.03f, 0.03f)
                                    }
                                    AudioManager.AUDIOFOCUS_GAIN -> {
                                        _bgmPlayer?.setVolume(0.12f, 0.12f)
                                    }
                                    AudioManager.AUDIOFOCUS_LOSS -> {
                                        // 완전 손실 시에도 계속 재생 (낮은 볼륨)
                                        _bgmPlayer?.setVolume(0.03f, 0.03f)
                                    }
                                }
                            }.setAudioAttributes(android.media.AudioAttributes.Builder()
                                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build())
                            .build()
                            am.requestAudioFocus(_bgmFocusRequest!!)
                        }
                        Log.d("Volume", "BGM started: $bgm")
                    } catch (e: Exception) {
                        Log.e("Volume", "BGM start failed: $e")
                    }
                    result.success(true)
                }
                // ═══ #5b: 브리핑 배경음 정지 ═══
                "stopBriefingBgm" -> {
                    try {
                        _bgmPlayer?.apply {
                            if (isPlaying) stop()
                            release()
                        }
                        _bgmPlayer = null
                        // AudioFocus 해제
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && _bgmFocusRequest != null) {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            am.abandonAudioFocusRequest(_bgmFocusRequest!!)
                            _bgmFocusRequest = null
                        }
                        Log.d("Volume", "BGM stopped")
                    } catch (e: Exception) {
                        Log.e("Volume", "BGM stop failed: $e")
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }


        // ─── Claude Agent 채널 (접근성 서비스 제어) ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGENT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Agent 서비스 실행 중인지 확인
                "isRunning" -> {
                    result.success(ClaudeAgentService.isRunning())
                }
                // 접근성 설정 화면 열기
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                // 현재 상태 조회 (포그라운드 앱, 규칙 등)
                "getStatus" -> {
                    val agent = ClaudeAgentService.instance
                    if (agent != null) {
                        result.success(agent.getStatus())
                    } else {
                        result.success(mapOf("running" to false))
                    }
                }
                // 오버레이 경고 표시
                "showOverlay" -> {
                    val msg = call.argument<String>("message") ?: "경고"
                    val duration = call.argument<Int>("duration")?.toLong() ?: 8000L
                    val agent = ClaudeAgentService.instance
                    if (agent != null) {
                        agent.showOverlay(msg, duration)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                // 화면 텍스트 읽기
                "getScreenText" -> {
                    val agent = ClaudeAgentService.instance
                    result.success(agent?.getScreenText() ?: "")
                }
                // 앱 사용 로그 Firestore 기록
                "flushLog" -> {
                    ClaudeAgentService.instance?.flushUsageLog()
                    result.success(true)
                }
                // 앱 강제 종료
                "killApp" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg != null) {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        @Suppress("DEPRECATION")
                        am.killBackgroundProcesses(pkg)
                        result.success(true)
                    } else {
                        result.error("NO_PACKAGE", "package argument required", null)
                    }
                }
                // URL 열기
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    } else {
                        result.error("NO_URL", "url argument required", null)
                    }
                }
                // 앱 실행
                "openApp" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg != null) {
                        val intent = packageManager.getLaunchIntentForPackage(pkg)
                        if (intent != null) {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("NO_LAUNCH_INTENT", "No launch intent for $pkg", null)
                        }
                    } else {
                        result.error("NO_PACKAGE", "package argument required", null)
                    }
                }
                // 볼륨 제어
                "setVolume" -> {
                    val level = call.argument<Int>("level") ?: 7
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, level.coerceIn(0, maxVol), 0)
                    result.success(true)
                }
                // 화면 밝기
                "setBrightness" -> {
                    val level = call.argument<Int>("level") ?: 128
                    try {
                        Settings.System.putInt(
                            contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS_MODE,
                            Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
                        )
                        Settings.System.putInt(
                            contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS,
                            level.coerceIn(0, 255)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BRIGHTNESS_FAILED", e.message, null)
                    }
                }
                // 화면 잠금
                "lockScreen" -> {
                    val agent = ClaudeAgentService.instance
                    if (agent != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        agent.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                        result.success(true)
                    } else {
                        // Fallback: DevicePolicyManager
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val adminComp = android.content.ComponentName(this, AdminReceiver::class.java)
                        if (dpm.isAdminActive(adminComp)) {
                            dpm.lockNow()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                }
                // TTS 음성
                "speak" -> {
                    val text = call.argument<String>("text") ?: "알림"
                    val agent = ClaudeAgentService.instance
                    if (agent != null) {
                        // Agent 서비스의 TTS 사용
                        result.success(true)
                        // Firestore 명령으로 위임 (Agent가 TTS 엔진 보유)
                        com.google.firebase.firestore.FirebaseFirestore.getInstance()
                            .document("users/sJ8Pxusw9gR0tNR44RhkIge7OiG2/data/iot")
                            .update(mapOf(
                                "agent.command" to mapOf(
                                    "action" to "speak",
                                    "text" to text,
                                    "handled" to false
                                )
                            ))
                    } else {
                        result.success(false)
                    }
                }
                // 앱 사용 리포트
                "getAppUsageReport" -> {
                    if (!hasUsageStatsPermission()) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    result.success(getTodayUsageStats())
                }
                else -> result.notImplemented()
            }
        }

        createAppNotificationChannel()

        // ─── 알림 리스너 상태 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_LISTENER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    result.success(flat?.contains(packageName) == true)
                }
                "openNotificationListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

override fun onDestroy() {
    try {
        _bgmPlayer?.release()
        _bgmPlayer = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && _bgmFocusRequest != null) {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.abandonAudioFocusRequest(_bgmFocusRequest!!)
            _bgmFocusRequest = null
        }
    } catch (_: Exception) {}
    super.onDestroy()
}

    companion object {
        const val APP_NOTIF_CHANNEL_ID = "cheonhong_app"
        const val APP_NOTIF_ID = 3001
    }

    private fun createAppNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                APP_NOTIF_CHANNEL_ID,
                "앱 알림",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "루틴 처리 결과 알림"
                enableVibration(false)
                setSound(null, null)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun showAppNotification(title: String, body: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(this, APP_NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(APP_NOTIF_ID, notif)
    }

    private fun requestPostNotificationsPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                9001
            )
        }
    }

    // ─── 방해금지 모드 ───

    private fun enableDndMode() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.isNotificationPolicyAccessGranted) {
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            }
        } catch (_: Exception) {}
    }

    private fun disableDndMode() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.isNotificationPolicyAccessGranted) {
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
            }
        } catch (_: Exception) {}
    }

    // ─── UsageStats ───

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getTodayUsageStats(): List<Map<String, Any>> {
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

        if (stats.isNullOrEmpty()) return emptyList()

        val pm = packageManager
        val result = mutableListOf<Map<String, Any>>()

        for (s in stats) {
            val totalMin = (s.totalTimeInForeground / 60000).toInt()
            if (totalMin < 1) continue

            val pkg = s.packageName
            if (pkg.startsWith("com.android.") || pkg.startsWith("com.sec.") ||
                pkg == packageName || pkg.startsWith("com.samsung.")) continue

            val appName = try {
                val ai = pm.getApplicationInfo(pkg, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg.substringAfterLast('.')
            }

            val category = categorizeApp(pkg)

            result.add(mapOf(
                "packageName" to pkg,
                "appName" to appName,
                "usageMinutes" to totalMin,
                "category" to category
            ))
        }

        return result.sortedByDescending { it["usageMinutes"] as Int }
    }

    private fun categorizeApp(pkg: String): String {
        val l = pkg.lowercase()
        return when {
            listOf("instagram", "twitter", "facebook", "tiktok", "reddit",
                "discord", "kakao", "line", "telegram", "snapchat", "threads")
                .any { l.contains(it) } -> "sns"
            listOf("youtube", "netflix", "twitch", "tving", "wavve", "watcha",
                "coupangplay", "disney")
                .any { l.contains(it) } -> "video"
            listOf("anki", "notion", "evernote", "goodnotes", "flexcil",
                "quizlet", "duolingo")
                .any { l.contains(it) } -> "study"
            else -> "other"
        }
    }

    // ─── Foreground App ───

    private fun getForegroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, now - 10000, now
        )
        if (stats.isNullOrEmpty()) return null
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    // ─── WiFi SSID ───

    private fun getCurrentWifiSsid(): String? {
        return try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val info = wm.connectionInfo
            if (info != null && info.ssid != null && info.ssid != "<unknown ssid>") {
                info.ssid.trim('"')
            } else null
        } catch (e: Exception) {
            null
        }
    }
}

