package com.chatterloop.callnative

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.IntentCompat

/**
 * Every button on a call notification or the PiP window lands here: Hang up,
 * Mute, Unmute, a ring being dismissed, and a ring's Decline.
 */
class CallActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, Int.MIN_VALUE)
        when (intent.action) {
            ACTION_HANGUP -> {
                // Nobody left to hang up - the call's engine is gone. At least
                // stop claiming there is a call.
                if (!CallNativePlugin.dispatchCallAction("hangup")) OngoingCallService.stop()
            }
            ACTION_MUTE -> CallNativePlugin.dispatchCallAction("mute")
            ACTION_UNMUTE -> CallNativePlugin.dispatchCallAction("unmute")
            ACTION_STOP_SCREEN_SHARE -> CallNativePlugin.dispatchCallAction("stopScreenShare")
            ACTION_RING_DISMISSED -> CallRingService.stop(id)
            ACTION_DECLINE -> {
                // Silence first, then let the Decline do what it always did
                // (flutter_local_notifications' own handling, which records the
                // decline in Dart).
                CallRingService.stop(id)
                val forward = IntentCompat.getParcelableExtra(
                    intent,
                    EXTRA_FORWARD,
                    PendingIntent::class.java,
                )
                try {
                    forward?.send()
                } catch (e: PendingIntent.CanceledException) {
                    Log.w("CallActionReceiver", "decline forward was cancelled", e)
                }
            }
        }
    }

    companion object {
        const val ACTION_HANGUP = "com.chatterloop.callnative.HANGUP"
        const val ACTION_MUTE = "com.chatterloop.callnative.MUTE"
        const val ACTION_UNMUTE = "com.chatterloop.callnative.UNMUTE"
        const val ACTION_STOP_SCREEN_SHARE = "com.chatterloop.callnative.STOP_SCREEN_SHARE"
        const val ACTION_RING_DISMISSED = "com.chatterloop.callnative.RING_DISMISSED"
        const val ACTION_DECLINE = "com.chatterloop.callnative.DECLINE"
        private const val EXTRA_ID = "notificationId"
        private const val EXTRA_FORWARD = "forward"

        fun intent(context: Context, action: String, id: Int = 0): PendingIntent {
            val intent = Intent(context, CallActionReceiver::class.java)
                .setAction(action)
                .putExtra(EXTRA_ID, id)
            return PendingIntent.getBroadcast(
                context,
                requestCode(action, id),
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        /** Wraps a ring's own Decline so it stops the ringer first. */
        fun declineIntent(context: Context, id: Int, original: PendingIntent): PendingIntent {
            val intent = Intent(context, CallActionReceiver::class.java)
                .setAction(ACTION_DECLINE)
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_FORWARD, original)
            return PendingIntent.getBroadcast(
                context,
                requestCode(ACTION_DECLINE, id),
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun requestCode(action: String, id: Int) = 31 * action.hashCode() + id
    }
}
