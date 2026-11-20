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
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * Phase K1 — the "now playing" layer for music and audiobook playback.
 *
 * Dart owns playback (media_kit/mpv) and every decision about what plays
 * next; this service only renders that state as a custom card bound to a
 * [MediaSessionCompat], so the same controls appear on the lock screen, on
 * Bluetooth headsets and in Android Auto.
 *
 * The card is a hand-built [RemoteViews] layout instead of MediaStyle: the
 * system MediaStyle body owns its own action row and silently drops anything
 * we add, so a literal close (X) in the corner is only possible with our own
 * layout. The media session is untouched — lock screen and Bluetooth keep
 * working through [MediaSessionCompat].
 *
 * Transport presses, audio-focus loss and the close button come back to Dart
 * over the method channel — the native side never decides what should play,
 * and a failed foreground start or a missing artwork file must never stop the
 * music, so every path here is fail-soft.
 */
class MediaPlaybackService : android.app.Service() {

    companion object {
        const val CHANNEL_ID = "dizzy_media"
        const val NOTIFICATION_ID = 8833
        const val CH = "com.sirius6907.dizzyv3/media"
        private const val CHANNEL_NAME = "Now playing"
        private const val CMD = "cmd"

        /**
         * The card only ever draws a few dozen dp of cover art, so a small
         * bitmap is enough — and it keeps the notification binder payload
         * far below the transaction limit that a full-size cover can hit.
         */
        private const val ART_MAX_PX = 256
        private const val THUMB_MAX_PX = 128

        private const val REQ_PREV = 6101
        private const val REQ_REW = 6102
        private const val REQ_PLAY = 6103
        private const val REQ_FFWD = 6104
        private const val REQ_NEXT = 6105

        /** The corner (X). */
        private const val REQ_CLOSE = 6106

        /** Swipe-to-dismiss. Same command, separate intent so both fit. */
        private const val REQ_SWIPED = 6107

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
            // Tapping the lock-screen / Bluetooth card reopens Dizzy instead of
            // doing nothing.
            openAppIntent()?.let { setSessionActivity(it) }
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
            // The X (and a swipe) tear the card down and tell Dart to pause.
            // Without the pause the audio would keep playing with no way back
            // to the widget, which is worse than no button at all.
            "close" -> closeFromUser()
        }
    }

    /**
     * The user dismissed the card. Order matters: Dart is told first so the
     * pause lands while the service is still alive, then focus is dropped and
     * the foreground notification is removed.
     */
    private fun closeFromUser() {
        sendToDart("onClose")
        abandonFocus()
        hide()
    }

    /** Draws (or refreshes) the notification and stays in the foreground. */
    private fun render(intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Dizzy"
        val subtitle = intent.getStringExtra("subtitle")
        val playing = intent.getBooleanExtra("playing", false)
        val position = intent.getLongExtra("positionMs", 0L)
        val duration = intent.getLongExtra("durationMs", 0L)
        val art = intent.getStringExtra("art")

        // Decode the cover once: the notification and the session metadata
        // share the same bitmap so a big cover is not decoded twice.
        val artwork = loadArtwork(art)

        val notification =
            buildNotification(title, subtitle, playing, position, duration, artwork)
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

        publishSessionState(title, subtitle, playing, position, duration, art, artwork)

        if (playing) {
            requestFocus()
        }
    }

    private fun publishSessionState(
        title: String,
        subtitle: String?,
        playing: Boolean,
        position: Long,
        duration: Long,
        artPath: String?,
        artwork: Bitmap?
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
                .apply {
                    artwork?.let {
                        putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
                        putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, it)
                    }
                    // Some launchers read the URI rather than the bitmap.
                    if (!artPath.isNullOrBlank()) {
                        putString(
                            MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI,
                            Uri.fromFile(File(artPath)).toString()
                        )
                    }
                }
                .build()
        )
    }

    private fun buildNotification(
        title: String,
        subtitle: String?,
        playing: Boolean,
        position: Long,
        duration: Long,
        art: Bitmap?
    ): Notification {
        val state = subtitleOrState(subtitle, playing)
        val thumb = thumbnail(art)

        val compact = RemoteViews(packageName, R.layout.np_compact).apply {
            bindArt(R.id.np_art, thumb)
            setTextViewText(R.id.np_title, title)
            setTextViewText(R.id.np_subtitle, state)
            setImageViewResource(
                R.id.np_play,
                if (playing) R.drawable.np_pause else R.drawable.np_play
            )
            setOnClickPendingIntent(R.id.np_play, servicePending("playPause", REQ_PLAY))
            setOnClickPendingIntent(R.id.np_close, servicePending("close", REQ_CLOSE))
            // Taps on the artwork / text behave like tapping the notification.
            openAppIntent()?.let { setOnClickPendingIntent(R.id.np_root, it) }
        }

        val expanded = RemoteViews(packageName, R.layout.np_expanded).apply {
            bindArt(R.id.np_big_art, thumb)
            setTextViewText(R.id.np_big_title, title)
            setTextViewText(R.id.np_big_subtitle, state)
            setImageViewResource(
                R.id.np_big_play,
                if (playing) R.drawable.np_pause else R.drawable.np_play
            )
            setOnClickPendingIntent(R.id.np_big_close, servicePending("close", REQ_CLOSE))
            // Same rule as the collapsed row: an empty part of the card is a
            // tap on the notification, not a dead zone.
            openAppIntent()?.let { setOnClickPendingIntent(R.id.np_big_root, it) }
            setOnClickPendingIntent(R.id.np_big_play, servicePending("playPause", REQ_PLAY))
            setOnClickPendingIntent(R.id.np_big_prev, servicePending("prev", REQ_PREV))
            setOnClickPendingIntent(R.id.np_big_next, servicePending("next", REQ_NEXT))
            setOnClickPendingIntent(R.id.np_big_rew, servicePending("rew", REQ_REW))
            setOnClickPendingIntent(R.id.np_big_ffwd, servicePending("ffwd", REQ_FFWD))
            if (duration > 0) {
                val max = duration.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                setProgressBar(
                    R.id.np_progress,
                    max,
                    position.coerceIn(0L, duration).toInt(),
                    false
                )
                setTextViewText(R.id.np_elapsed, mmss(position))
                setTextViewText(R.id.np_total, mmss(duration))
            } else {
                // Live streams have no timeline; drop the row instead of
                // drawing an empty 0:00 / 0:00 track.
                setViewVisibility(R.id.np_progress, View.GONE)
                setViewVisibility(R.id.np_times, View.GONE)
            }
        }

        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            // Flat white glyph — a launcher mipmap renders as a grey square.
            .setSmallIcon(R.drawable.ic_stat_music)
            // Kept for the fallback renderers (Auto, OEM lockscreens) that
            // ignore custom views; the card itself uses the RemoteViews below.
            .setContentTitle(title)
            .setContentText(state)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setContentIntent(openAppIntent())
            .setCustomContentView(compact)
            .setCustomBigContentView(expanded)
            // An un-dismissed card must never outlive the playback: a swipe
            // takes the same path as the X.
            .setDeleteIntent(servicePending("close", REQ_SWIPED))

        art?.let { b.setLargeIcon(it) }
        return b.build()
    }

    /** A bitmap small enough for a [RemoteViews] without risking the binder limit. */
    private fun RemoteViews.bindArt(id: Int, art: Bitmap?) {
        // No cover: leave the view alone. Its background drawable is the
        // deliberate "empty cover" tile, so the row never looks broken.
        if (art != null) setImageViewBitmap(id, art)
    }

    private fun servicePending(cmd: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, MediaPlaybackService::class.java)
            .putExtra(CMD, cmd)
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
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

    /** Cover art is drawn at 42–52dp; nothing larger needs to cross the binder. */
    private fun thumbnail(src: Bitmap?): Bitmap? {
        if (src == null) return null
        val largest = maxOf(src.width, src.height)
        if (largest <= THUMB_MAX_PX) return src
        val scale = THUMB_MAX_PX.toFloat() / largest
        return try {
            Bitmap.createScaledBitmap(
                src,
                (src.width * scale).toInt().coerceAtLeast(1),
                (src.height * scale).toInt().coerceAtLeast(1),
                true
            )
        } catch (_: Exception) {
            src
        }
    }

    private fun subtitleOrState(subtitle: String?, playing: Boolean): String {
        if (!subtitle.isNullOrBlank()) return subtitle
        return getString(if (playing) R.string.np_playing else R.string.np_paused)
    }

    /** `3:07`, or `1:02:09` once the track passes an hour. */
    private fun mmss(ms: Long): String {
        val total = (ms.coerceAtLeast(0L) / 1000L)
        val seconds = total % 60
        val minutes = (total / 60) % 60
        val hours = total / 3600
        return if (hours > 0) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%d:%02d", minutes, seconds)
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
        // stopForeground only removes a notification it owns; the fail-soft
        // path above can have posted a plain one, so cancel explicitly too.
        try {
            notificationManager()?.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {
        }
        publishSessionState("", null, false, 0L, 0L, null, null)
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
