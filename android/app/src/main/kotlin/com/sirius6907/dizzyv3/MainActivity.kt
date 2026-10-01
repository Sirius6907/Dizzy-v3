package com.sirius6907.dizzyv3

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
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