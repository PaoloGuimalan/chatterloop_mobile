package com.chatterloop.callnative

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Rings for an incoming call: the ringtone on loop at ringer volume, and the
 * ring vibration, for as long as the call rings.
 *
 * Why the app plays it instead of the notification: Android stops a
 * notification's looping sound the moment the user opens the notification
 * shade - to look at the very call that is ringing - and a notification's
 * vibration follows the phone's "vibrate for calls" setting, which many phones
 * ship switched off. A phone call does neither, and neither does this.
 *
 * The notification itself is posted by Dart (flutter_local_notifications) on a
 * silent channel. This service ADOPTS it as its foreground notification, so the
 * ring and its notification live and die together: stopping the ring removes
 * the notification, and dismissing the notification stops the ring.
 *
 * One ring at a time - a second call arriving while one rings is posted as a
 * silent waiting call by Dart and never reaches here.
 */
class CallRingService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finish() }
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var focusRequest: AudioFocusRequest? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = intent?.getIntExtra(EXTRA_REQUEST, -1) ?: -1
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val id = intent.getIntExtra(EXTRA_ID, 0)

        val started = try {
            val notification = adopt(
                id,
                intent.getStringExtra(EXTRA_CHANNEL) ?: "",
                intent.getIntExtra(EXTRA_DECLINE_INDEX, -1),
            )
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            } else {
                0
            }
            ServiceCompat.startForeground(this, id, notification, type)
            true
        } catch (e: Exception) {
            Log.w(TAG, "could not ring in the foreground", e)
            false
        }

        if (!started) {
            report(request, false)
            if (ringingId == null) stopSelf()
            return START_NOT_STICKY
        }

        stopFeedback()
        ringingId = id
        startFeedback(
            intent.getStringExtra(EXTRA_SOUND) ?: "",
            intent.getLongArrayExtra(EXTRA_PATTERN) ?: LongArray(0),
        )
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, intent.getLongExtra(EXTRA_TIMEOUT, 45_000L))
        report(request, true)
        return START_NOT_STICKY
    }

    /**
     * The ring's own notification, as Dart posted it, wired so that:
     *  - dismissing it stops the ring (it has no other way to), and
     *  - its Decline stops the ring at once, then does what it always did.
     * Falls back to a plain one if it is somehow not in the tray - a
     * foreground service has to show something.
     */
    private fun adopt(id: Int, channelId: String, declineIndex: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        val notification = manager.activeNotifications.firstOrNull { it.id == id }
            ?.notification
            ?: NotificationCompat.Builder(this, channelId)
                .setSmallIcon(CallNotificationIcons.small(this))
                .setContentTitle("Incoming call")
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setContentIntent(CallNotificationIcons.openApp(this))
                .build()

        notification.deleteIntent =
            CallActionReceiver.intent(this, CallActionReceiver.ACTION_RING_DISMISSED, id)
        val decline = notification.actions?.getOrNull(declineIndex)
        val original = decline?.actionIntent
        if (decline != null && original != null) {
            decline.actionIntent = CallActionReceiver.declineIntent(this, id, original)
        }
        return notification
    }

    private fun startFeedback(sound: String, pattern: LongArray) {
        val audio = getSystemService(AudioManager::class.java)
        val notifications = getSystemService(NotificationManager::class.java)

        // Never louder than the phone is set to be: Do Not Disturb silences the
        // ring completely (the notification still shows), the ringer switch
        // decides between ringing, vibrating and nothing, and an ongoing phone
        // call is never rung over.
        val filter = notifications.currentInterruptionFilter
        if (filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        ) {
            return
        }
        if (audio.mode == AudioManager.MODE_IN_CALL ||
            audio.mode == AudioManager.MODE_IN_COMMUNICATION
        ) {
            return
        }
        when (audio.ringerMode) {
            AudioManager.RINGER_MODE_NORMAL -> {
                playSound(audio, sound)
                vibrate(pattern)
            }
            AudioManager.RINGER_MODE_VIBRATE -> vibrate(pattern)
            else -> Unit
        }
    }

    private fun playSound(audio: AudioManager, sound: String) {
        val resId = resources.getIdentifier(sound, "raw", packageName)
        if (resId == 0) return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(
                    this@CallRingService,
                    Uri.parse("android.resource://$packageName/$resId"),
                )
                isLooping = true
                prepare()
                start()
            }
            // Pause music and videos while it rings, like a phone call does.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(attributes)
                    .build()
                    .also { audio.requestAudioFocus(it) }
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(
                    null,
                    AudioManager.STREAM_RING,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "could not play the ringtone", e)
            player?.release()
            player = null
        }
    }

    /**
     * Vibrates as a COMMUNICATION REQUEST - someone asking to talk. Unlike a
     * ringtone vibration, that follows the phone's notification vibration
     * rather than its often-off "vibrate for calls" switch, and unlike a plain
     * notification vibration Android still allows it from the background.
     */
    private fun vibrate(pattern: LongArray) {
        if (pattern.isEmpty()) return
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (v == null || !v.hasVibrator()) return
        vibrator = v
        try {
            when {
                Build.VERSION.SDK_INT >= 33 -> v.vibrate(
                    VibrationEffect.createWaveform(pattern, 0),
                    VibrationAttributes.createForUsage(
                        VibrationAttributes.USAGE_COMMUNICATION_REQUEST,
                    ),
                )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    @Suppress("DEPRECATION")
                    v.vibrate(
                        VibrationEffect.createWaveform(pattern, 0),
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST)
                            .build(),
                    )
                }
                else -> {
                    @Suppress("DEPRECATION")
                    v.vibrate(
                        pattern,
                        0,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST)
                            .build(),
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "could not vibrate", e)
        }
    }

    private fun stopFeedback() {
        player?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
        val audio = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(null)
        }
        focusRequest = null
    }

    /** Stops the ring and takes its notification down with it. */
    private fun finish() {
        handler.removeCallbacks(timeout)
        stopFeedback()
        val id = ringingId
        ringingId = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (id != null) getSystemService(NotificationManager::class.java).cancel(id)
        stopSelf()
    }

    /** Android 14+: a short service past its time limit must stop now. */
    override fun onTimeout(startId: Int) = finish()

    override fun onTimeout(startId: Int, fgsType: Int) = finish()

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        stopFeedback()
        ringingId = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "CallRingService"
        private const val EXTRA_ID = "notificationId"
        private const val EXTRA_CHANNEL = "channelId"
        private const val EXTRA_TIMEOUT = "timeoutMs"
        private const val EXTRA_SOUND = "sound"
        private const val EXTRA_PATTERN = "vibrationPattern"
        private const val EXTRA_DECLINE_INDEX = "declineActionIndex"
        private const val EXTRA_REQUEST = "request"

        /** How long Dart waits to hear whether the ring started. */
        private const val REPORT_TIMEOUT_MS = 4_000L

        private var instance: CallRingService? = null

        /** The notification currently ringing, if any. */
        @Volatile
        var ringingId: Int? = null
            private set

        private val main = Handler(Looper.getMainLooper())
        private var nextRequest = 0
        private val pending = mutableMapOf<Int, (Boolean) -> Unit>()

        /**
         * Starts ringing for [notificationId] and reports through [onResult]
         * whether it actually rang. False when Android refused the foreground
         * service (the app is in the background without an exemption).
         */
        fun start(
            context: Context,
            notificationId: Int,
            channelId: String,
            timeoutMs: Long,
            sound: String,
            vibrationPattern: LongArray,
            declineActionIndex: Int,
            onResult: (Boolean) -> Unit,
        ) {
            val request = ++nextRequest
            pending[request] = onResult
            main.postDelayed({ report(request, false) }, REPORT_TIMEOUT_MS)

            val intent = Intent(context, CallRingService::class.java)
                .putExtra(EXTRA_REQUEST, request)
                .putExtra(EXTRA_ID, notificationId)
                .putExtra(EXTRA_CHANNEL, channelId)
                .putExtra(EXTRA_TIMEOUT, timeoutMs)
                .putExtra(EXTRA_SOUND, sound)
                .putExtra(EXTRA_PATTERN, vibrationPattern)
                .putExtra(EXTRA_DECLINE_INDEX, declineActionIndex)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException and friends.
                Log.w(TAG, "ringer refused", e)
                report(request, false)
            }
        }

        /** Stops the ring for [notificationId], or any ring when null. */
        fun stop(notificationId: Int?) {
            val service = instance ?: return
            if (notificationId == null || notificationId == ringingId) service.finish()
        }

        private fun report(request: Int, started: Boolean) {
            pending.remove(request)?.invoke(started)
        }
    }
}
