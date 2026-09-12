package com.chatterloop.app

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Puts a file the app has already downloaded into the device's SHARED
 * Downloads collection, so it shows up in Files / Downloads like any other
 * download rather than being buried in app-private storage.
 *
 * This has to be native. From API 29 (scoped storage) an app cannot write a
 * path under the public Downloads directory at all - dart:io sees it as
 * permission denied - and the only sanctioned route in is a MediaStore
 * insert, which has no Flutter plugin in this project's dependency set. The
 * alternative was adding a downloader package; one Kotlin file against a
 * stable platform API is the smaller commitment, and it is the same
 * MethodChannel shape [ConversationShortcuts] already uses.
 *
 * Two eras, because minSdk is below 29:
 *
 *   API 29+   MediaStore.Downloads insert, IS_PENDING while the bytes are
 *             copied. No permission of any kind is required.
 *   API 23-28 a plain write into Environment's public Downloads directory,
 *             which DOES require WRITE_EXTERNAL_STORAGE at runtime - hence
 *             the permission plumbing below, and the maxSdkVersion="28" on
 *             the manifest declaration.
 *
 * Copies run on a background thread: these are user-chosen attachments capped
 * at 100MB (kMaxUploadBytes), and moving that much through the main thread
 * would freeze the UI mid-conversation. MethodChannel results must be
 * delivered on the main thread, so each one is posted back.
 */
class MediaSaver {
    companion object {
        private const val CHANNEL = "chatterloop/media_saver"
        private const val PERMISSION_REQUEST = 0x1D10
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The one save waiting on a permission answer, if any. */
    private var pending: (() -> Unit)? = null
    private var pendingDenied: (() -> Unit)? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val path = call.argument<String>("path")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType")
                        ?: "application/octet-stream"
                    if (path.isNullOrEmpty() || fileName.isNullOrEmpty()) {
                        result.error("bad_args", "path and fileName are required", null)
                        return@setMethodCallHandler
                    }
                    withStoragePermission(
                        activity,
                        onGranted = { save(activity, path, fileName, mimeType, result) },
                        onDenied = {
                            result.error(
                                "permission_denied",
                                "Storage permission was not granted",
                                null,
                            )
                        },
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Forwarded from MainActivity - an Activity's permission callback is the
     * only place the answer arrives, and this class has no way to receive it
     * on its own.
     */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val proceed = pending
        val denied = pendingDenied
        pending = null
        pendingDenied = null
        if (granted) proceed?.invoke() else denied?.invoke()
    }

    private fun withStoragePermission(
        activity: Activity,
        onGranted: () -> Unit,
        onDenied: () -> Unit,
    ) {
        // API 29+ writes through MediaStore, which needs nothing.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            onGranted()
            return
        }
        val permission = Manifest.permission.WRITE_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            onGranted()
            return
        }
        // One request in flight at a time. A second download arriving while
        // the dialog is up fails fast rather than queueing behind a prompt the
        // user may never answer.
        if (pending != null) {
            onDenied()
            return
        }
        pending = onGranted
        pendingDenied = onDenied
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(permission),
            PERMISSION_REQUEST,
        )
    }

    private fun save(
        context: Context,
        path: String,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        io.execute {
            try {
                val source = File(path)
                if (!source.exists()) throw IllegalStateException("staged file is gone")
                val saved =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        saveViaMediaStore(context, source, fileName, mimeType)
                    } else {
                        saveViaPublicDirectory(context, source, fileName)
                    }
                main.post { result.success(saved) }
            } catch (e: Exception) {
                main.post {
                    result.error("save_failed", e.message, null)
                }
            }
        }
    }

    private fun saveViaMediaStore(
        context: Context,
        source: File,
        fileName: String,
        mimeType: String,
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            // Hidden from other apps until the bytes are all there, so nothing
            // can open a half-copied file.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore refused the insert")
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IllegalStateException("no output stream")
                source.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            // A pending row nothing ever finished writing is invisible AND
            // undeletable by the user, so it has to go on the way out.
            resolver.delete(uri, null, null)
            throw e
        }
        return uri.toString()
    }

    private fun saveViaPublicDirectory(
        context: Context,
        source: File,
        fileName: String,
    ): String {
        val downloads =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!downloads.exists()) downloads.mkdirs()
        val destination = uniqueFile(downloads, fileName)
        source.inputStream().use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        // Pre-29 there is no MediaStore insert doing this for us, so an
        // unscanned file is invisible to Gallery and to anything else reading
        // the index - it only exists to a file manager walking the directory.
        MediaScannerConnection.scanFile(
            context,
            arrayOf(destination.absolutePath),
            null,
            null,
        )
        return destination.absolutePath
    }

    /** "photo.jpg", then "photo (1).jpg", ... - never silently overwrite. */
    private fun uniqueFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(directory, "$stem ($counter)$ext")
            counter++
        }
        return candidate
    }
}
