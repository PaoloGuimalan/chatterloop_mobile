package com.chatterloop.callnative

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** What every call notification needs from the host app. */
internal object CallNotificationIcons {

    /**
     * The app's monochrome status-bar icon (res/drawable/ic_stat_chatterloop),
     * or its launcher icon if it has none.
     */
    fun small(context: Context): Int {
        val id = context.resources.getIdentifier("ic_stat_chatterloop", "drawable", context.packageName)
        return if (id != 0) id else context.applicationInfo.icon
    }

    /**
     * Brings the app back exactly as it was left - the call screen, during a
     * call - rather than starting it over.
     */
    fun openApp(context: Context): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
