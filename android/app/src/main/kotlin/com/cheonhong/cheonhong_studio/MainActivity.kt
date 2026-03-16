package com.cheonhong.cheonhong_studio

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
import android.nfc.NfcAdapter
import android.util.Log
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.os.Bundle
import android.os.Parcelable

class MainActivity : FlutterActivity() {

    private val FOCUS_CHANNEL = "com.cheonhong.cheonhong_studio/focus_mode"
    private val USAGE_CHANNEL = "com.cheonhong.cheonhong_studio/usage_stats"
    private val WIFI_CHANNEL = "com.cheonhong.cheonhong_studio/wifi"
    private val VOLUME_CHANNEL = "com.cheonhong.cheonhong_studio/volume"
    private val NFC_CHANNEL = "com.cheonhong.cheonhong_studio/nfc"
    private val BROWSER_CHANNEL = "com.cheonhong.cheonhong_studio/browser"
    private val SLEEP_CHANNEL = "com.cheonhong.cheonhong_studio/sleep"
    private val BIXBY_CHANNEL = "com.cheonhong.cheonhong_studio/bixby"
    private var nfcChannel: MethodChannel? = null
    private var screenReceiver: android.content.BroadcastReceiver? = null
    private var flutterReadyForNfc: Boolean = false
    private var pendingNfcPayload: HashMap<String, Any>? = null
    private var silentReaderEnabled: Boolean = false
    private var _bgmPlayer: MediaPlayer? = null
    private var _bgmFocusRequest: android.media.AudioFocusRequest? = null


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

// ─── NFC 채널 (NDEF → Flutter 전달) ───
nfcChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL).apply {
    setMethodCallHandler { call, result ->
        when (call.method) {
            "flutterReady" -> {
                flutterReadyForNfc = true
                // 초기 런치 또는 엔진 준비 전 수신된 NFC 인텐트 flush
                pendingNfcPayload?.let { payload ->
                    invokeMethod("onNfcTagFromIntent", payload)
                    pendingNfcPayload = null
                }
                result.success(true)
            }
            "getPendingNfcIntent" -> {
                // ★ NFC 첫 태그 보완: pending payload 명시적 반환
                val payload = pendingNfcPayload
                if (payload != null) {
                    pendingNfcPayload = null
                    result.success(payload)
                } else {
                    result.success(null)
                }
            }
            "enableSilentReader" -> {
                enableSilentReaderMode()
                result.success(true)
            }
            "disableSilentReader" -> {
                disableSilentReaderMode()
                result.success(true)
            }
            "showNotification" -> {
                val title = call.argument<String>("title") ?: "NFC 처리"
                val body = call.argument<String>("body") ?: ""
                showNfcNotification(title, body)
                result.success(true)
            }
            "requestNotificationPermission" -> {
                requestPostNotificationsPermission()
                requestActivityRecognitionPermission()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}

// Cold start: 앱이 NFC 인텐트로 실행된 경우를 위해 초기 intent도 처리 (엔진 준비 전이면 큐에 저장)
handleNfcIntent(intent)?.let { payload ->
    sendNfcToFlutter(payload)
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


        createNfcNotificationChannel()

        // ─── 수면 감지 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SLEEP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    startScreenMonitoring()
                    result.success(true)
                }
                "stopMonitoring" -> {
                    stopScreenMonitoring()
                    result.success(true)
                }
                "consumeSleepDetection" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val detected = prefs.getBoolean("flutter.sleep_detected", false)
                    if (detected) {
                        val time = prefs.getString("flutter.sleep_detected_time", null)
                        prefs.edit()
                            .remove("flutter.sleep_detected")
                            .remove("flutter.sleep_detected_time")
                            .apply()
                        result.success(hashMapOf("detected" to true, "time" to time))
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 빅스비 연동 채널 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIXBY_CHANNEL).setMethodCallHandler { call, result ->
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

// ══════════════════════════════════════════
//  NFC: NDEF 인텐트 처리 → Flutter 전달
// ══════════════════════════════════════════

override fun onDestroy() {
    stopScreenMonitoring()
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

// ══════════════════════════════════════════
//  수면 감지: 화면 꺼짐/켜짐 모니터링
// ══════════════════════════════════════════

private fun startScreenMonitoring() {
    if (screenReceiver != null) return
    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    if (!prefs.getBoolean("flutter.sleep_detect_enabled", false)) return

    SleepAlarmReceiver.createChannel(this)

    screenReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val p = ctx.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            if (!p.getBoolean("flutter.sleep_detect_enabled", false)) return

            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                    if (hour >= 22 || hour < 4) {
                        p.edit().putString("flutter.screen_off_time",
                            System.currentTimeMillis().toString()).apply()
                        SleepAlarmReceiver.scheduleSleepCheck(ctx, 30 * 60 * 1000L)
                        Log.d("SleepDetect", "Screen off at night — 30min alarm set")
                    }
                }
                Intent.ACTION_SCREEN_ON -> {
                    SleepAlarmReceiver.cancelSleepCheck(ctx)
                    Log.d("SleepDetect", "Screen on — alarm cancelled")
                }
            }
        }
    }

    val filter = android.content.IntentFilter().apply {
        addAction(Intent.ACTION_SCREEN_OFF)
        addAction(Intent.ACTION_SCREEN_ON)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
    } else {
        registerReceiver(screenReceiver, filter)
    }
    Log.d("SleepDetect", "Screen monitoring started")
}

private fun stopScreenMonitoring() {
    screenReceiver?.let {
        try { unregisterReceiver(it) } catch (_: Exception) {}
    }
    screenReceiver = null
    SleepAlarmReceiver.cancelSleepCheck(this)
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent) // FlutterActivity가 들고 있는 intent 갱신
    handleNfcIntent(intent)?.let { payload ->
        sendNfcToFlutter(payload)
    }
}

// ★ NFC 첫 태그 보완: foreground dispatch로 앱이 포그라운드에서 NFC 우선 수신
override fun onResume() {
    super.onResume()
    enableNfcForegroundDispatch()
}

override fun onPause() {
    super.onPause()
    disableNfcForegroundDispatch()
}

private fun enableNfcForegroundDispatch() {
    try {
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
        val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)

        // NDEF_DISCOVERED 우선, TECH_DISCOVERED 폴백
        val ndefFilter = android.content.IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED).apply {
            try { addDataScheme("cheonhong") } catch (_: Exception) {}
        }
        val techFilter = android.content.IntentFilter(NfcAdapter.ACTION_TECH_DISCOVERED)
        val tagFilter = android.content.IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED)

        adapter.enableForegroundDispatch(
            this, pendingIntent,
            arrayOf(ndefFilter, techFilter, tagFilter),
            arrayOf(
                arrayOf(android.nfc.tech.Ndef::class.java.name),
                arrayOf(android.nfc.tech.NdefFormatable::class.java.name),
                arrayOf(android.nfc.tech.NfcA::class.java.name)
            )
        )
        Log.d("NFC", "✅ Foreground dispatch enabled")
    } catch (e: Exception) {
        Log.w("NFC", "⚠️ Foreground dispatch error: ${e.message}")
    }
}

private fun disableNfcForegroundDispatch() {
    try {
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
        adapter.disableForegroundDispatch(this)
    } catch (_: Exception) {}
}

private fun sendNfcToFlutter(payload: HashMap<String, Any>) {
    val ch = nfcChannel
    if (ch != null && flutterReadyForNfc) {
        ch.invokeMethod("onNfcTagFromIntent", payload)
    } else {
        // 엔진/Flutter 준비 전이면 보류 (가장 최근 1건만 유지)
        pendingNfcPayload = payload
    }
}

private fun handleNfcIntent(intent: Intent?): HashMap<String, Any>? {
    if (intent == null) return null

    val action = intent.action ?: ""
    // 1) 커스텀 스킴 VIEW (NDEF URI + AAR로 실행될 때 흔함)
    if (action == Intent.ACTION_VIEW) {
        val data = intent.data ?: return null
        val role = data.getQueryParameter("role") ?: ""
        val tagId = data.getQueryParameter("tagId") ?: ""
        return hashMapOf(
            "uri" to data.toString(),
            "role" to role,
            "tagUid" to tagId
        )
    }

    // 2) NDEF_DISCOVERED / TECH_DISCOVERED 로 들어오는 경우
    if (action == "android.nfc.action.NDEF_DISCOVERED" || action == "android.nfc.action.TECH_DISCOVERED" || action == "android.nfc.action.TAG_DISCOVERED") {
        // ★ NFC 첫 태그 보완: TAG_DISCOVERED에서도 UID 추출
        val tag = intent.getParcelableExtra<android.nfc.Tag>(NfcAdapter.EXTRA_TAG)
        val tagUidHex = tag?.id?.joinToString("") { "%02X".format(it) } ?: ""

        // 먼저 intent.data를 시도
        val data = intent.data
        if (data != null) {
            val role = data.getQueryParameter("role") ?: ""
            val tagId = data.getQueryParameter("tagId") ?: tagUidHex
            return hashMapOf(
                "uri" to data.toString(),
                "role" to role,
                "tagUid" to tagId
            )
        }

        // fallback: EXTRA_NDEF_MESSAGES에서 URI 레코드 추출
        try {
            val rawMsgs = intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
            if (rawMsgs != null && rawMsgs.isNotEmpty()) {
                val msg = rawMsgs[0] as NdefMessage
                val recs = msg.records
                if (recs.isNotEmpty()) {
                    val maybeUri = parseUriFromNdefRecord(recs[0])
                    if (maybeUri != null) {
                        val role = maybeUri.getQueryParameter("role") ?: ""
                        val tagId = maybeUri.getQueryParameter("tagId") ?: tagUidHex
                        return hashMapOf(
                            "uri" to maybeUri.toString(),
                            "role" to role,
                            "tagUid" to tagId
                        )
                    }
                }
            }
        } catch (_: Exception) { }

        // ★ NFC 첫 태그 보완: NDEF 없어도 UID만으로 전달 (UID 매칭 폴백)
        if (tagUidHex.isNotEmpty()) {
            Log.d("NFC", "TAG_DISCOVERED fallback: UID=$tagUidHex")
            return hashMapOf(
                "uri" to "",
                "role" to "",
                "tagUid" to tagUidHex
            )
        }
    }

    return null
}

// NDEF URI 레코드(RTD_URI 또는 WELL_KNOWN U)에서 Uri 파싱 (간단 버전)
private fun parseUriFromNdefRecord(record: NdefRecord): Uri? {
    return try {
        // WELL_KNOWN + RTD_URI
        val isWellKnownUri =
            record.tnf == NdefRecord.TNF_WELL_KNOWN &&
            record.type.contentEquals(NdefRecord.RTD_URI)

        if (!isWellKnownUri) return null

        val payload = record.payload ?: return null
        if (payload.isEmpty()) return null

        // NFC Forum "URI Record Type Definition"
        // payload[0] = URI Identifier Code (prefix)
        val prefix = when (payload[0].toInt()) {
            0x00 -> ""
            0x01 -> "http://www."
            0x02 -> "https://www."
            0x03 -> "http://"
            0x04 -> "https://"
            else -> ""
        }
        val uriStr = prefix + String(payload, 1, payload.size - 1, Charsets.UTF_8)
        Uri.parse(uriStr)
    } catch (_: Exception) {
        null
    }
}

private fun enableSilentReaderMode() {
    val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
    if (silentReaderEnabled) return
    silentReaderEnabled = true

    val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS

    adapter.enableReaderMode(
        this,
        { /* reader callback not used */ },
        flags,
        Bundle()
    )
}

private fun disableSilentReaderMode() {
    val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
    if (!silentReaderEnabled) return
    silentReaderEnabled = false
    adapter.disableReaderMode(this)
}


    companion object {
        const val NFC_NOTIF_CHANNEL_ID = "cheonhong_nfc"
        const val NFC_NOTIF_ID = 3001
    }

    private fun createNfcNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NFC_NOTIF_CHANNEL_ID,
                "NFC 처리 알림",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "NFC 태그 처리 결과 알림"
                enableVibration(false)
                setSound(null, null)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun showNfcNotification(title: String, body: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(this, NFC_NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NFC_NOTIF_ID, notif)
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

    private fun requestActivityRecognitionPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                9002
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

