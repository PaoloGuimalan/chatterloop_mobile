package com.chatterloop.callnative

import android.app.Activity
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.annotation.RequiresApi

/**
 * Picture-in-picture for calls. Dart decides WHEN the app may shrink into a
 * PiP window (a video call on screen) and this makes it happen when the user
 * leaves the app:
 *
 *   Android 12+   auto-enter, so the swipe home animates straight into PiP.
 *   Android 8-11  entered from onUserLeaveHint, the same gesture.
 *   below 8       no PiP; the ongoing-call notification still covers it.
 *
 * The whole Flutter UI is what shrinks - there is one activity - so Dart swaps
 * the call screen for a compact layout while [isInPip] (see the host
 * activity's onPictureInPictureModeChanged).
 */
object CallPip {
    private const val TAG = "CallPip"

    private var activity: Activity? = null
    private var enabled = false
    private var muted = false
    private var aspect = Rational(9, 16)

    var isInPip = false
        private set

    fun isSupported(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    fun attach(activity: Activity) {
        this.activity = activity
        // A closed PiP window can take its activity down without ever saying
        // PiP ended. The activity attaching now is full-screen - say so, or
        // Dart would keep drawing the tiny PiP layout.
        val inPipNow = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            activity.isInPictureInPictureMode
        if (isInPip != inPipNow) onModeChanged(inPipNow)
        apply()
    }

    fun detach() {
        activity = null
    }

    fun update(enabled: Boolean, muted: Boolean, aspectWidth: Int, aspectHeight: Int) {
        this.enabled = enabled
        this.muted = muted
        aspect = clamp(Rational(aspectWidth.coerceAtLeast(1), aspectHeight.coerceAtLeast(1)))
        apply()
    }

    /** The call ended while it was a PiP window: close the window with it. */
    fun exit() {
        val a = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && a.isInPictureInPictureMode) {
            a.moveTaskToBack(false)
        }
    }

    fun onUserLeaveHint() {
        val a = activity ?: return
        if (!enabled || !isSupported(a)) return
        // 12+ enters on its own (setAutoEnterEnabled) - entering here too
        // would fight the system's animation.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                a.enterPictureInPictureMode(params(a))
            } catch (e: Exception) {
                // PiP switched off for this app in system settings.
                Log.w(TAG, "could not enter PiP", e)
            }
        }
    }

    /** Called by the host activity's onPictureInPictureModeChanged. */
    fun onModeChanged(inPip: Boolean) {
        isInPip = inPip
        CallNativePlugin.dispatchPipChanged(inPip)
    }

    private fun apply() {
        val a = activity ?: return
        if (!isSupported(a) || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            a.setPictureInPictureParams(params(a))
        } catch (e: Exception) {
            Log.w(TAG, "could not update PiP", e)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun params(context: Context): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspect)
            .setActions(actions(context))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(enabled)
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun actions(context: Context): List<RemoteAction> {
        val mute = if (muted) {
            RemoteAction(
                Icon.createWithResource(context, R.drawable.cn_ic_mic_off),
                "Unmute",
                "Unmute",
                CallActionReceiver.intent(context, CallActionReceiver.ACTION_UNMUTE),
            )
        } else {
            RemoteAction(
                Icon.createWithResource(context, R.drawable.cn_ic_mic),
                "Mute",
                "Mute",
                CallActionReceiver.intent(context, CallActionReceiver.ACTION_MUTE),
            )
        }
        val hangUp = RemoteAction(
            Icon.createWithResource(context, R.drawable.cn_ic_call_end),
            "Hang up",
            "Hang up",
            CallActionReceiver.intent(context, CallActionReceiver.ACTION_HANGUP),
        )
        return listOf(mute, hangUp)
    }

    /** Android rejects anything flatter or taller than 2.39:1. */
    private fun clamp(ratio: Rational): Rational {
        val value = ratio.toFloat()
        return when {
            value > 2.39f -> Rational(239, 100)
            value < 1 / 2.39f -> Rational(100, 239)
            else -> ratio
        }
    }
}
