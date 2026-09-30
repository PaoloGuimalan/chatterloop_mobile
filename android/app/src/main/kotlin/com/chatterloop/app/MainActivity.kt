package com.chatterloop.app

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import com.chatterloop.callnative.CallEngineKeeper
import com.chatterloop.callnative.CallPip
import com.chatterloop.callnative.CallScreenShare
import com.cloudwebrtc.webrtc.ScreenCaptureHooks
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /** Saves downloaded attachments into the shared Downloads collection. */
    private val mediaSaver = MediaSaver()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Let the app's OWN background show behind the system bars.
        //
        // This has to be native - Flutter's SystemUiOverlayStyle cannot express
        // it. The app targets SDK 36, and from SDK 35 Android enforces
        // edge-to-edge and IGNORES systemNavigationBarColor. On top of that,
        // with THREE-BUTTON navigation the system draws its own contrast scrim
        // behind the bar, chosen from the OS theme rather than ours - which is
        // why the navigation bar stayed light grey with dark icons while the
        // app was in dark mode, and why the status bar (which gets no such
        // scrim) themed correctly all along.
        //
        // Turning contrast enforcement off is the documented way to opt out of
        // that scrim. The bar then shows whatever the app paints underneath,
        // so it follows the in-app theme like everything else. Gesture
        // navigation was never affected - it has no scrim to begin with - so
        // this only changes the three-button case.
        //
        // API 29+; below that the scrim does not exist and the colour set from
        // Dart still applies.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }

        // Screen sharing in calls: flutter_webrtc captures, the call's own
        // foreground service makes Android allow it. See CallScreenShare.
        ScreenCaptureHooks.listener = object : ScreenCaptureHooks.Listener {
            override fun onCaptureConsented() = CallScreenShare.onConsented()
            override fun onCaptureStopped() = CallScreenShare.onStopped()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ConversationShortcuts.register(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // The Activity, not applicationContext: on API 28 and below saving a
        // download needs WRITE_EXTERNAL_STORAGE, and a runtime permission can
        // only be requested from an Activity.
        mediaSaver.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    // ── Calls ───────────────────────────────────────────────────────────────
    // A call must outlive this activity: closing its PiP window or swiping the
    // app out of recents destroys the activity, and by default the engine
    // (and the Dart running the call) with it. See CallEngineKeeper.

    /** The engine still running a call from a previous activity, if any. */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        CallEngineKeeper.take()

    override fun shouldDestroyEngineWithHost(): Boolean =
        !CallEngineKeeper.isRetained(flutterEngine)

    override fun onDestroy() {
        CallEngineKeeper.retainIfInCall(flutterEngine, isChangingConfigurations)
        super.onDestroy()
    }

    /** Dart swaps the call screen for its compact PiP layout on this. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        CallPip.onModeChanged(isInPictureInPictureMode)
    }

    /**
     * MediaSaver's legacy (pre-29) path asks for WRITE_EXTERNAL_STORAGE, and
     * this is the only place Android delivers the answer.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mediaSaver.onRequestPermissionsResult(requestCode, grantResults)
    }
}
