package com.sirius6907.dizzyv3

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phase K2 — downloads foreground service (`foregroundServiceType="dataSync"`).
 *
 * The whole point is that a 40-minute download survives the screen turning
 * off: while this is running Android treats the app as busy instead of
 * reclaimable. The notification is also the only progress surface that
 * exists once the app is not on screen, so it carries the aggregate state
 * plus Pause / Cancel, forwarded back to Dart over [CH].
 */
class DownloadForegroundService : android.app.Service() {

    companion object {
        const val CHANNEL_ID = "dizzy_downloads"
        const val NOTIFICATION_ID = 8822
        const val CH = "com.sirius6907.dizzyv3/downloads"

        /** Set by MainActivity so notifications can talk back to Dart. */
        var engine: FlutterEngine? = null

        private var active = 0
        private var percent = 0
        private var label = "Dizzy"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            if (it.hasExtra("active")) active = it.getIntExtra("active", active)
            if (it.hasExtra("percent")) percent = it.getIntExtra("percent", percent)
            if (it.hasExtra("label")) label = it.getStringExtra("label") ?: label
        }
        val action = intent?.getStringExtra("action")
        if (action != null) {
            // A button on the notification: hand it back to Dart.
            sendToFlutter("onAction", action)
            if (action == "stop") {
                stopEverything()
                return START_NOT_STICKY
            }
        }
        ensureChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    0
                }
            )
        } catch (e: SecurityException) {
            // Missing permission must not take the downloads down with it.
            stopSelf()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): android.app.Notification {
        val pause = actionIntent("pause")
        val cancel = actionIntent("stop")

        val title = if (active > 0) {
            "$active download${if (active == 1) "" else "s"} running"
        } else {
            "Downloads"
        }
        val text = if (active > 0) "$percent% · $label" else "Starting…"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, percent, active > 0 && percent <= 0)
            .addAction(0, "Pause", pause)
            .addAction(0, "Cancel", cancel)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun actionIntent(action: String): PendingIntent {
        val intent = Intent(this, DownloadForegroundService::class.java)
            .putExtra("action", action)
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun sendToFlutter(method: String, arg: String) {
        val e = engine ?: return
        try {
            MethodChannel(e.dartExecutor.binaryMessenger, CH)
                .invokeMethod(method, arg)
        } catch (_: Exception) {
        }
    }

    private fun stopEverything() {
        active = 0
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        stopSelf()
    }

    override fun onDestroy() {
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows download progress while Dizzy is not open"
            setShowBadge(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }
}
