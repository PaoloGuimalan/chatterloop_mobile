package com.chatterloop.app

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Publishes long-lived conversation shortcuts so message notifications qualify
 * for Android's Conversation treatment (API 30+): the contact's avatar shown
 * large, the app icon badged on it in colour, and placement in the shade's
 * dedicated Conversations section.
 *
 * Android grants that treatment only when THREE things line up - MessagingStyle,
 * a long-lived dynamic shortcut carrying a Person, and the notification's
 * shortcutId pointing at it. flutter_local_notifications covers the first and
 * third but has no ShortcutManager code at all, which is the only reason this
 * file exists.
 *
 * Registered from MainActivity, so it runs in the UI isolate only. That is a
 * deliberate trade: the FCM background isolate has no Activity, and reaching it
 * would mean packaging this as a real plugin for GeneratedPluginRegistrant to
 * find. Shortcuts persist across restarts and setLongLived keeps them cached
 * after eviction, so every conversation the user has actually seen stays
 * covered; only a never-before-seen conversation's FIRST notification falls
 * back to the plain layout.
 */
object ConversationShortcuts {
    private const val CHANNEL = "chatterloop/conversation_shortcuts"

    /** Required for the system to treat a shortcut as a conversation. */
    private const val CATEGORY_CONVERSATION = "android.shortcut.conversation"

    /**
     * Hard ceiling regardless of what the device reports. The conversations
     * surface only ever shows a handful, and every extra shortcut costs an
     * avatar decode on a path that runs during list load.
     */
    private const val MAX_SHORTCUTS = 8

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    @Suppress("UNCHECKED_CAST")
                    val items = call.argument<List<Map<String, Any?>>>("conversations")
                        ?: emptyList()
                    result.success(sync(context, items))
                }
                "clearAll" -> {
                    ShortcutManagerCompat.removeAllDynamicShortcuts(context)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Replaces the whole dynamic set in one call, which is also how pruning is
     * handled: pushing individually throws once the device cap is hit, and a
     * thrown push means the notification silently loses conversation status.
     * Replacing sidesteps the cap entirely.
     */
    private fun sync(context: Context, items: List<Map<String, Any?>>): Boolean {
        return try {
            val cap = minOf(
                MAX_SHORTCUTS,
                ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)
                    .takeIf { it > 0 } ?: MAX_SHORTCUTS,
            )

            val shortcuts = items.take(cap).mapNotNull { item ->
                val id = item["id"] as? String ?: return@mapNotNull null
                val label = (item["label"] as? String)?.takeIf { it.isNotBlank() } ?: id
                val icon = loadIcon(item["iconPath"] as? String)

                val person = Person.Builder()
                    .setName(label)
                    .setKey(id)
                    .apply { icon?.let { setIcon(it) } }
                    .build()

                // A shortcut without an intent is rejected outright. This one
                // only fires if the user launches the shortcut from the
                // launcher's long-press menu - notification taps are routed
                // separately, through the local-notification payload.
                val intent = Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW)
                    .putExtra("conversationId", id)

                ShortcutInfoCompat.Builder(context, id)
                    .setShortLabel(label)
                    .setLongLabel(label)
                    .setPerson(person)
                    .setLongLived(true)
                    .setCategories(setOf(CATEGORY_CONVERSATION))
                    .setIntent(intent)
                    .apply { icon?.let { setIcon(it) } }
                    .build()
            }

            ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
        } catch (e: Exception) {
            // Never surface as an error: a missing shortcut costs the fancy
            // layout, nothing more, and this runs during conversation-list load.
            false
        }
    }

    /**
     * The PNG is already circle-cropped by NotificationRenderer, so
     * createWithBitmap is correct here - createWithAdaptiveBitmap would apply
     * its own mask on top and clip the circle's edges.
     */
    private fun loadIcon(path: String?): IconCompat? {
        if (path.isNullOrEmpty()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            BitmapFactory.decodeFile(path)?.let { IconCompat.createWithBitmap(it) }
        } catch (e: Exception) {
            null
        }
    }
}
