package com.chatterloop.callnative

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine

/**
 * Keeps a call alive past its screen.
 *
 * A call runs in Dart, and Dart runs in the Flutter engine, which by default
 * dies with the activity. The activity dies more often than it seems: closing
 * a PiP window destroys it, and so does swiping the app out of recents. During
 * a call that would hang up on the user, so the host activity hands its engine
 * here instead of destroying it, and the next activity - opened from the
 * ongoing-call notification - picks the same engine back up, call and screens
 * exactly as they were.
 *
 * Only ever during a call (while OngoingCallService runs). The moment the call
 * ends, an engine with no screen left is destroyed, so the app never lingers
 * headless - still connected, and so still counted as online.
 *
 * Host activity wiring (MainActivity):
 *   provideFlutterEngine      -> CallEngineKeeper.take()
 *   onDestroy, before super   -> CallEngineKeeper.retainIfInCall(engine, ...)
 *   shouldDestroyEngineWithHost -> !CallEngineKeeper.isRetained(engine)
 */
object CallEngineKeeper {
    private val main = Handler(Looper.getMainLooper())
    private var retained: FlutterEngine? = null

    /** The activity is going away; keep its engine if a call is running in it. */
    fun retainIfInCall(engine: FlutterEngine?, changingConfigurations: Boolean) {
        if (engine == null || changingConfigurations) return
        if (OngoingCallService.isRunning) retained = engine
    }

    fun isRetained(engine: FlutterEngine?): Boolean = engine != null && engine === retained

    /** For a new activity: the engine still running a call, if there is one. */
    fun take(): FlutterEngine? = retained.also { retained = null }

    /**
     * The call is over. An engine nobody came back for has nothing left to
     * do. The delay lets Dart finish the leave that ended the call.
     */
    fun onCallEnded() {
        main.postDelayed({
            val engine = retained ?: return@postDelayed
            if (OngoingCallService.isRunning) return@postDelayed
            retained = null
            engine.destroy()
        }, 2_000)
    }
}
