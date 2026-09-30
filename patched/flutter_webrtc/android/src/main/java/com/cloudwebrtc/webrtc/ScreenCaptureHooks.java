package com.cloudwebrtc.webrtc;

/**
 * CHATTERLOOP PATCH - not in upstream flutter_webrtc.
 *
 * The two moments of a screen capture (getDisplayMedia) the host app has to
 * act on, which nothing else in this plugin exposes:
 *
 *   consent  The user allowed the capture, and it starts the instant this
 *            returns. Android 10+ refuses to start it unless a foreground
 *            service of type mediaProjection is running by then - and Android
 *            14+ only lets such a service start AFTER consent. Upstream grants
 *            consent and starts capturing in the same callback, leaving no
 *            moment in between to start that service; this is that moment.
 *   stopped  The capture ended - through the system's own stop control, or
 *            another app taking the projection over - which upstream only logs.
 *
 * Chatterloop's MainActivity sets [listener]; see chatterloop_call_native's
 * CallScreenShare.
 */
public final class ScreenCaptureHooks {

    public interface Listener {
        /**
         * The user allowed screen capture; it starts right after this returns.
         * Return false to abort it (getDisplayMedia then fails).
         */
        boolean onCaptureConsented();

        /** The capture ended, whoever ended it. */
        void onCaptureStopped();
    }

    public static volatile Listener listener;

    private ScreenCaptureHooks() {}
}
