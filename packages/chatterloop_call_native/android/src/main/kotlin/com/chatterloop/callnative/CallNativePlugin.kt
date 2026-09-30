package com.chatterloop.callnative

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * The Dart-facing half of the plugin. One instance per Flutter engine: the
 * app's own, plus the background isolates that draw pushes and handle
 * notification actions. Any of them can ring or stop a ring; only the engine
 * that hosts the UI - the one the call runs in - receives call actions and
 * PiP changes back.
 */
class CallNativePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    PluginRegistry.UserLeaveHintListener {

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        if (uiPlugin === this) uiPlugin = null
    }

    // ── Activity ────────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        uiPlugin = this
        binding.addOnNewIntentListener(this)
        binding.addOnUserLeaveHintListener(this)
        CallPip.attach(binding.activity)
        stopRingIfOpenedFromIt(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding?.removeOnUserLeaveHintListener(this)
        activityBinding = null
        CallPip.detach()
        // uiPlugin stays: during a call the engine outlives its activity (see
        // CallEngineKeeper), and Hang up from the notification must still
        // reach the Dart side running the call.
    }

    override fun onNewIntent(intent: Intent): Boolean {
        stopRingIfOpenedFromIt(intent)
        return false
    }

    override fun onUserLeaveHint() = CallPip.onUserLeaveHint()

    /**
     * Join on the ringing notification opens the app. Stop the ringtone the
     * moment it does - Dart would stop it too, but only once a cold-started
     * app has booted, which is seconds of ringing after the user answered.
     * flutter_local_notifications puts the notification's id in the intent.
     */
    private fun stopRingIfOpenedFromIt(intent: Intent?) {
        val id = intent?.getIntExtra("notificationId", Int.MIN_VALUE) ?: return
        if (id != Int.MIN_VALUE && id == CallRingService.ringingId) {
            CallRingService.stop(id)
        }
    }

    // ── Dart → native ───────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("detached", "No context", null)
        when (call.method) {
            "startRinging" -> {
                val pattern = (call.argument<List<Number>>("vibrationPattern") ?: emptyList())
                    .map { it.toLong() }
                    .toLongArray()
                CallRingService.start(
                    ctx,
                    notificationId = call.argument<Int>("notificationId") ?: 0,
                    channelId = call.argument<String>("channelId") ?: "",
                    timeoutMs = (call.argument<Number>("timeoutMs") ?: 45_000).toLong(),
                    sound = call.argument<String>("sound") ?: "",
                    vibrationPattern = pattern,
                    declineActionIndex = call.argument<Int>("declineActionIndex") ?: -1,
                ) { started -> result.success(started) }
            }
            "stopRinging" -> {
                CallRingService.stop(call.argument<Int>("notificationId"))
                result.success(null)
            }
            "startOngoingCall" -> result.success(
                OngoingCallService.start(
                    ctx,
                    title = call.argument<String>("title") ?: "",
                    text = call.argument<String>("text") ?: "",
                    muted = call.argument<Boolean>("muted") ?: false,
                    startedAt = (call.argument<Number>("startedAt")
                        ?: System.currentTimeMillis()).toLong(),
                ),
            )
            "updateOngoingCall" -> {
                OngoingCallService.update(
                    title = call.argument<String>("title"),
                    muted = call.argument<Boolean>("muted"),
                    screenSharing = call.argument<Boolean>("screenSharing"),
                )
                result.success(null)
            }
            "stopOngoingCall" -> {
                OngoingCallService.stop()
                result.success(null)
            }
            "isInCall" -> result.success(OngoingCallService.isRunning)
            "isPipSupported" -> result.success(CallPip.isSupported(ctx))
            "updatePip" -> {
                CallPip.update(
                    enabled = call.argument<Boolean>("enabled") ?: false,
                    muted = call.argument<Boolean>("muted") ?: false,
                    aspectWidth = call.argument<Int>("aspectWidth") ?: 9,
                    aspectHeight = call.argument<Int>("aspectHeight") ?: 16,
                )
                result.success(null)
            }
            "exitPip" -> {
                CallPip.exit()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "chatterloop/call_native"

        /** The plugin on the engine that hosts the UI and the call. */
        @Volatile
        private var uiPlugin: CallNativePlugin? = null

        /**
         * Hands a call action (hangup, mute, unmute) to the Dart side running
         * the call. False when nothing is there to take it.
         */
        fun dispatchCallAction(action: String): Boolean {
            val channel = uiPlugin?.channel ?: return false
            channel.invokeMethod("onCallAction", mapOf("action" to action))
            return true
        }

        fun dispatchPipChanged(inPip: Boolean) {
            uiPlugin?.channel?.invokeMethod("onPipChanged", mapOf("inPip" to inPip))
        }
    }
}
