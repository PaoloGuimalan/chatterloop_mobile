package com.chatterloop.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ConversationShortcuts.register(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
