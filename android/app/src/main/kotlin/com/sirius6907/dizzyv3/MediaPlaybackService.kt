package com.sirius6907.dizzyv3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
// MediaStyle lives in androidx.media, not androidx.core.
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.core.app.ServiceCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Phase K1 — the "now playing" layer for music and audiobook playback.
 *
 * Dart owns playback (media_kit/mpv) and every decision about what plays
 * next; this service only renders that state as a MediaStyle notification
 * bound to a [MediaSessionCompat], so the same controls appear on the lock
 * screen, on Bluetooth headsets and in Android Auto.
 *
 * Transport presses and audio-focus loss come back to Dart over the
 * method channel — the native side never decides what should play, and a
 * failed foreground start or a missing artwork file must never stop the
 * music, so every path here is fail-soft.
 */
class MediaPlaybackService : android.app.Service() {

    companion object {
        const val CHANNEL_ID = "dizzy_media"
        const val NOTIFICATION_ID = 8833
        const val CH = "com.sirius6907.dizzyv3/media"
        private const val CHANNEL_NAME = "Now playing"
        private const val CMD = "cmd"
        private const val ART_MAX_PX = 512

        private const val REQ_PREV = 6101
        private const val REQ_REW = 6102
        private const val REQ_PLAY = 6103
        private const val REQ_FFWD = 6104
        private const val REQ_NEXT = 6105

        /** Set by [MainActivity] while the Flutter engine is alive. */
        var engine: FlutterEngine? = null
    }

    private var session: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var isShown = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val focusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            // Another app took the audio (call, assistant, headset yanked).
            // We do not fight for it: Dart pauses, which is what a user expects.
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    if (hasFocus) {
                        hasFocus = false
                        sendToDart("onFocusLost")
                    }
                }
                AudioManager.AUDIOFOCUS_GAIN -> hasFocus = true
            }
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
        ensureChannel()
        session = MediaSessionCompat(this, "DizzyMedia").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = sendToDart("onPlayPause", "play")
                override fun onPause() = sendToDart("onPlayPause", "pause")
                override fun onSkipToNext() = sendToDart("onNext")
                override fun onSkipToPrevious() = sendToDart("onPrev")
                override fun onStop() = sendToDart("onStop")
                override fun onFastForward() = sendToDart("onSeek", 10000L)
                override fun onRewind() = sendToDart("onSeek", -10000L)
                override fun onSeekTo(pos: Long) = sendToDart("onSeekTo", pos)
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val cmd = intent?.getStringExtra(CMD) ?: return START_NOT_STICKY
        when (cmd) {
            "hide" -> {
                abandonFocus()
                hide()
            }
            "show", "update" -> render(intent)
            else -> dispatch(cmd)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        abandonFocus()
        session?.isActive = false
        session?.release()
        session = null
        super.onDestroy()
    }

    /** A notification / lock-screen button press: forward, never decide here. */
    private fun dispatch(cmd: String) {
        when (cmd) {
            "play", "pause", "playPause" -> sendToDart("onPlayPause", cmd)
            "next" -> sendToDart("onNext")
            "prev" -> sendToDart("onPrev")
            "rew" -> sendToDart("onSeek", -10000L)
            "ffwd" -> sendToDart("onSeek", 10000L)
            "stop" -> sendToDart("onStop")
        }
    }

    /** Draws (or refreshes) the notification and stays in the foreground. */
    private fun render(intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Dizzy"
        val subtitle = intent.getStringExtra("subtitle")
        val playing = intent.getBooleanExtra("playing", false)
        val position = intent.getLongExtra("positionMs", 0L)
        val duration = intent.getLongExtra("durationMs", 0L)
        val art = intent.getStringExtra("art")

        val notification =
            buildNotification(title, subtitle, playing, position, duration, art)
        try {
            if (isShown) {
                notificationManager()?.notify(NOTIFICATION_ID, notification)
            } else {
                startInForeground(notification)
                isShown = true
            }
        } catch (e: Exception) {
            // Android 12+ can refuse a foreground start. The music must keep
            // playing anyway, so fall back to a plain notification.
            try {
                notificationManager()?.notify(NOTIFICATION_ID, notification)
            } catch (_: Exception) {
            }
        }

        publishSessionState(title, subtitle, playing, position, duration)

        if (playing) {
            requestFocus()
        }
    }

    private fun publishSessionState(
        title: String,
        subtitle: String?,
        playing: Boolean,
        position: Long,
        duration: Long
    ) {
        val s = session ?: return
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_STOP
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    position,
                    if (playing) 1f else 0f
                )
                .build()
        )
        s.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(
                    MediaMetadataCompat.METADATA_KEY_ARTIST,
                    subtitle ?: ""
                )
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .build()
        )
    }

    private fun buildNotification(
        title: String,
        subtitle: String?,
        playing: Boolean,
        position: Long,
        duration: Long,
        art: String?
    ): Notification {
        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(subtitle ?: if (playing) "Playing" else "Paused")
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setContentIntent(openAppIntent())
            // prev · rewind · play/pause · forward · next — compact row shows
            // prev, play and next (indices 0, 2, 4).
            .addAction(actionButton(android.R.drawable.ic_media_previous, "prev", REQ_PREV))
            .addAction(actionButton(android.R.drawable.ic_media_rew, "rew", REQ_REW))
            .addAction(
                actionButton(
                    if (playing) android.R.drawable.ic_media_pause
                    else android.R.drawable.ic_media_play,
                    "playPause",
                    REQ_PLAY
                )
            )
            .addAction(actionButton(android.R.drawable.ic_media_ff, "ffwd", REQ_FFWD))
            .addAction(actionButton(android.R.drawable.ic_media_next, "next", REQ_NEXT))
            .setStyle(
                MediaStyle()
                    .setMediaSession(session?.sessionToken)
                    .setShowActionsInCompactView(0, 2, 4)
            )

        loadArtwork(art)?.let { b.setLargeIcon(it) }

        if (duration > 0) {
            b.setProgress(
                duration.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                position.coerceIn(0L, duration).toInt(),
                false
            )
        }
        return b.build()
    }

    private fun actionButton(icon: Int, cmd: String, requestCode: Int):
        NotificationCompat.Action {
        val intent = Intent(this, MediaPlaybackService::class.java)
            .putExtra(CMD, cmd)
        val pending = PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val label = when (cmd) {
            "prev" -> "Previous"
            "next" -> "Next"
            "rew" -> "Back 10 seconds"
            "ffwd" -> "Forward 10 seconds"
            "playPause" -> "Play or pause"
            else -> cmd
        }
        return NotificationCompat.Action.Builder(icon, label, pending).build()
    }

    private fun openAppIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: return null
        return PendingIntent.getActivity(
            this,
            6200,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Artwork is a local path — decoded and capped so a huge cover cannot OOM us. */
    private fun loadArtwork(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.isFile) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= ART_MAX_PX ||
                bounds.outHeight / (sample * 2) >= ART_MAX_PX
            ) {
                sample *= 2
            }
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply { inSampleSize = sample }
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = notificationManager() ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
        )
    }

    private fun notificationManager(): NotificationManager? =
        getSystemService(NotificationManager::class.java)

    private fun startInForeground(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun hide() {
        if (isShown) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            isShown = false
        }
        publishSessionState("", null, false, 0L, 0L)
        stopSelf()
    }

    private fun requestFocus() {
        if (hasFocus) return
        val am = audioManager ?: return
        hasFocus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN
            )
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(false)
                .build()
                .also { focusRequest = it }
            am.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonFocus() {
        if (!hasFocus) return
        hasFocus = false
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
    }

    private fun sendToDart(method: String, arg: Any? = null) {
        val e = engine ?: return
        mainHandler.post {
            MethodChannel(e.dartExecutor.binaryMessenger, CH)
                .invokeMethod(method, arg, object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
        }
    }
}
