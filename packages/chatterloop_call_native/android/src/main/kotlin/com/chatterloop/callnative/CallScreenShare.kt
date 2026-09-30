package com.chatterloop.callnative

/**
 * Screen sharing in a call, as seen from the capture itself - the two moments
 * flutter_webrtc's ScreenCaptureHooks (a Chatterloop patch) reports. The host
 * activity connects them, since this plugin doesn't depend on flutter_webrtc:
 *
 *   ScreenCaptureHooks.listener = object : ScreenCaptureHooks.Listener {
 *       override fun onCaptureConsented() = CallScreenShare.onConsented()
 *       override fun onCaptureStopped() = CallScreenShare.onStopped()
 *   }
 */
object CallScreenShare {

    /**
     * The user allowed screen capture and it is about to start. Android
     * requires a media projection foreground service by then - the call's own
     * ongoing-call service takes that on. False (no call running) refuses the
     * capture.
     */
    fun onConsented(): Boolean = OngoingCallService.beginScreenCapture()

    /**
     * The capture ended, possibly from outside the app - the system's own
     * "stop sharing" control. The Dart side stops sharing properly (closes the
     * producer so the others' tile goes away); if it already had, this is a
     * no-op there.
     */
    fun onStopped() {
        CallNativePlugin.dispatchCallAction("stopScreenShare")
    }
}
