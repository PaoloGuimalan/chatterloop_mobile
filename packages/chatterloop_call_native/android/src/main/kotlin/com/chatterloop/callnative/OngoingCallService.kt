package com.chatterloop.callnative

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * The "in a call" notification, and what it stands for: a microphone
 * foreground service that keeps the call alive - and the mic open - while the
 * app is in the background, in a PiP window, or swiped out of recents.
 *
 * Android 11+ only lets a backgrounded app use the mic through a foreground
 * service that was started while the app was on screen, which is why Dart
 * starts this as the call connects rather than when the user leaves.
 *
 * Also what CallEngineKeeper asks about: while this runs, the Flutter engine
 * running the call survives its activity being destroyed.
 */
class OngoingCallService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        ensureChannel(this)
        val started = try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, build(this), foregroundType())
            true
        } catch (e: Exception) {
            Log.w(TAG, "could not start the ongoing call", e)
            false
        }
        if (!started || !wanted) finish()
        return START_NOT_STICKY
    }

    /**
     * Microphone, when the app may use it - without RECORD_AUDIO, Android 14+
     * refuses a microphone service outright, and there is no call to keep
     * alive without a mic anyway. Plus media projection while the screen is
     * being shared.
     */
    private fun foregroundType(screen: Boolean = state.screenSharing): Int {
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (screen && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        return type
    }

    /**
     * Re-declares what this service is for. Synchronous on purpose: screen
     * capture starts the instant consent returns, and the projection type
     * has to be in place by then.
     */
    private fun declare(screen: Boolean): Boolean = try {
        ServiceCompat.startForeground(this, NOTIFICATION_ID, build(this), foregroundType(screen))
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not change the ongoing call's type", e)
        false
    }

    private fun refresh() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build(this))
    }

    private fun finish() {
        isRunning = false
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
        CallEngineKeeper.onCallEnded()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        isRunning = false
        super.onDestroy()
    }

    private data class State(
        val title: String,
        val text: String,
        val muted: Boolean,
        val startedAt: Long,
        val screenSharing: Boolean = false,
    )

    companion object {
        private const val TAG = "OngoingCallService"
        private const val NOTIFICATION_ID = 0x0CA11
        private const val CHANNEL_ID = "chatterloop_ongoing_call_v1"

        private var instance: OngoingCallService? = null
        private var state = State("Call", "", false, System.currentTimeMillis())

        /** Dart asked for the ongoing call and has not ended it. */
        private var wanted = false

        /** A call is running in this process. */
        @Volatile
        var isRunning = false
            private set

        fun start(
            context: Context,
            title: String,
            text: String,
            muted: Boolean,
            startedAt: Long,
        ): Boolean {
            state = State(title, text, muted, startedAt)
            wanted = true
            return try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, OngoingCallService::class.java),
                )
                isRunning = true
                true
            } catch (e: Exception) {
                Log.w(TAG, "ongoing call refused", e)
                wanted = false
                false
            }
        }

        fun update(title: String?, muted: Boolean?, screenSharing: Boolean?) {
            val stopSharing = screenSharing == false && state.screenSharing
            state = state.copy(
                title = title ?: state.title,
                muted = muted ?: state.muted,
                screenSharing = screenSharing ?: state.screenSharing,
            )
            val service = instance ?: return
            if (!isRunning) return
            // Drop the projection type with the projection. If Android won't
            // allow the change right now (the app is in the background), the
            // notification still stops saying the screen is shared.
            if (stopSharing && service.declare(false)) return
            service.refresh()
        }

        /**
         * The user just allowed screen capture, which starts the moment this
         * returns: add media projection to the call's service now. False when
         * there is no call service to add it to - the capture is then refused.
         */
        fun beginScreenCapture(): Boolean {
            val service = instance ?: return false
            if (!isRunning) return false
            state = state.copy(screenSharing = true)
            if (service.declare(true)) return true
            state = state.copy(screenSharing = false)
            return false
        }

        fun stop() {
            wanted = false
            val service = instance
            if (service != null) {
                service.finish()
            } else {
                isRunning = false
                CallEngineKeeper.onCallEnded()
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Ongoing calls",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows while you are in a call"
                    setShowBadge(false)
                },
            )
        }

        private fun build(context: Context): Notification {
            val s = state
            val mute = if (s.muted) {
                NotificationCompat.Action(
                    R.drawable.cn_ic_mic,
                    "Unmute",
                    CallActionReceiver.intent(context, CallActionReceiver.ACTION_UNMUTE),
                )
            } else {
                NotificationCompat.Action(
                    R.drawable.cn_ic_mic_off,
                    "Mute",
                    CallActionReceiver.intent(context, CallActionReceiver.ACTION_MUTE),
                )
            }
            val stopSharing = NotificationCompat.Action(
                R.drawable.cn_ic_stop_screen_share,
                "Stop sharing",
                CallActionReceiver.intent(context, CallActionReceiver.ACTION_STOP_SCREEN_SHARE),
            )
            val hangUp = NotificationCompat.Action(
                R.drawable.cn_ic_call_end,
                "Hang up",
                CallActionReceiver.intent(context, CallActionReceiver.ACTION_HANGUP),
            )
            val text = when {
                s.screenSharing -> "Sharing your screen"
                s.muted -> "${s.text} · Muted"
                else -> s.text
            }
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(CallNotificationIcons.small(context))
                .setContentTitle(s.title)
                .setContentText(text)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(true)
                .setWhen(s.startedAt)
                .setUsesChronometer(true)
                .setContentIntent(CallNotificationIcons.openApp(context))
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            if (s.screenSharing) builder.addAction(stopSharing)
            return builder
                .addAction(mute)
                .addAction(hangUp)
                .build()
        }
    }
}
