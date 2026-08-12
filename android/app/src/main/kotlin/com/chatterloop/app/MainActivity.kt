package com.chatterloop.app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ConversationShortcuts.register(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
