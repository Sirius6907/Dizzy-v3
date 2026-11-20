package com.sirius6907.dizzyv3

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.playtorrio/power"
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireLocks" -> {
                    try {
                        // 1. High-Performance Low-Latency Wi-Fi Lock
                        if (wifiLock == null) {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                            } else {
                                WifiManager.WIFI_MODE_FULL_HIGH_PERF
                            }
                            wifiLock = wifiManager?.createWifiLock(lockMode, "playtorrio:stream_wifi")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wifiLock?.isHeld == false) {
                            wifiLock?.acquire()
                        }

                        // 2. Partial Wake Lock (prevents CPU sleep during streaming)
                        if (wakeLock == null) {
                            val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "playtorrio:stream_wake")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wakeLock?.isHeld == false) {
                            wakeLock?.acquire(3 * 60 * 60 * 1000L) // 3 hours timeout safety
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "releaseLocks" -> {
                    try {
                        if (wifiLock?.isHeld == true) {
                            wifiLock?.release()
                        }
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Zero-dep system share sheet (ACTION_SEND chooser).
        // Called by NativeShare.shareText; no share_plus needed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sirius6907.dizzyv3/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    try {
                        val text = call.argument<String>("text").orEmpty()
                        if (text.isEmpty()) {
                            result.success(false)
                        } else {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(sendIntent, "Share invite"))
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 18+ private mode: FLAG_SECURE blanks screenshots and the Android
        // recents thumbnail while the adult surface is on screen. Mirrors
        // PrivateModeShield.setSecure in lib/services/adult.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sirius6907.dizzyv3/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    try {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SECURE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Phase K3: microphone foreground service — start/stop the ongoing        // call notification that keeps LiveKit alive with the screen off.
        // Phase K2/K3: background services need the engine to talk back.
        DownloadForegroundService.engine = flutterEngine
        MediaPlaybackService.engine = flutterEngine

        // Phase K1: now-playing media session. Dart owns playback and
        // publishes what is on deck; MediaPlaybackService renders it as a
        // MediaStyle notification bound to a MediaSessionCompat and sends
        // transport presses back over this same channel. This handler is the
        // only thing that ever starts the service — without it every publish
        // threw MissingPluginException, so no notification was ever shown and
        // no lock-screen / Bluetooth controls existed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MediaPlaybackService.CH).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "show", "update", "hide" -> {
                        val hide = call.method == "hide"
                        val intent = Intent(this, MediaPlaybackService::class.java)
                            .putExtra("cmd", if (hide) "hide" else "show")
                        if (!hide) {
                            val args = call.arguments as? Map<*, *>
                            intent.putExtra("title", args?.get("title") as? String ?: "Dizzy")
                            intent.putExtra("subtitle", args?.get("subtitle") as? String)
                            intent.putExtra("playing", args?.get("playing") as? Boolean ?: false)
                            intent.putExtra(
                                "positionMs",
                                (args?.get("positionMs") as? Number)?.toLong() ?: 0L
                            )
                            intent.putExtra(
                                "durationMs",
                                (args?.get("durationMs") as? Number)?.toLong() ?: 0L
                            )
                            intent.putExtra("art", args?.get("art") as? String)
                        }
                        if (hide) {
                            // No foreground obligation on the way down, and a
                            // background startService may be refused — stopping
                            // the service still clears the notification.
                            try {
                                startService(intent)
                            } catch (_: IllegalStateException) {
                                stopService(Intent(this, MediaPlaybackService::class.java))
                            }
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // Android 12+ can refuse a background foreground-start. The
                // music must keep playing, so report it and let Dart retry.
                result.error("MEDIA_SERVICE", e.message, null)
            }
        }

        // Phase K2: downloads foreground service. Same shape as the media
        // handler above — Dart publishes one aggregate progress notification
        // and this is the only thing that starts the service, so without it
        // DownloadFgBridge.show() threw MissingPluginException and progress
        // never appeared outside the app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DownloadForegroundService.CH).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "show" -> {
                        val args = call.arguments as? Map<*, *>
                        val active = (args?.get("active") as? Number)?.toInt() ?: 0
                        val percent = (args?.get("percent") as? Number)?.toInt() ?: 0
                        val label = args?.get("label") as? String ?: ""
                        if (active <= 0) {
                            stopService(Intent(this, DownloadForegroundService::class.java))
                        } else {
                            val intent = Intent(this, DownloadForegroundService::class.java)
                                .putExtra("active", active)
                                .putExtra("percent", percent)
                                .putExtra("label", label)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, DownloadForegroundService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // A refused foreground start must not kill the download
                // itself; report it so Dart can retry on the next tick.
                result.error("DOWNLOAD_SERVICE", e.message, null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sirius6907.dizzyv3/voice").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val room = call.argument<String>("room") ?: ""
                        val intent = Intent(this, VoiceForegroundService::class.java)
                            .putExtra(VoiceForegroundService.EXTRA_ROOM, room)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOICE_START", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, VoiceForegroundService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOICE_STOP", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Staged-update install (Phase I2): hand a locally verified APK to the
        // system installer through the OTA plugin's own FileProvider (already
        // registered in the manifest) with an explicit read grant.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sirius6907.dizzyv3/install").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    try {
                        val path = call.argument<String>("path").orEmpty()
                        val file = java.io.File(path)
                        if (path.isEmpty() || !file.exists()) {
                            result.success(false)
                        } else {
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this,
                                "$packageName.ota_update_provider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Signing-cert channel: the updater reads this install's own cert fingerprint
        // and picks the matching GitHub asset (release-key vs legacy-key), so every
        // old install can update IN PLACE — no uninstall ever needed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sirius6907.dizzyv3/signing").setMethodCallHandler { call, result ->
            when (call.method) {
                "getCertSha256" -> {
                    try {
                        val pm = applicationContext.packageManager
                        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pm.getPackageInfo(applicationContext.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                                .signingInfo?.apkContentsSigners
                        } else {
                            @Suppress("DEPRECATION")
                            pm.getPackageInfo(applicationContext.packageName, PackageManager.GET_SIGNATURES).signatures
                        }
                        val sig = signatures?.firstOrNull()
                        if (sig == null) {
                            result.success(null)
                        } else {
                            val digest = MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
                            result.success(digest.joinToString("") { "%02x".format(it) })
                        }
                    } catch (e: Exception) {
                        result.error("SIGN_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}