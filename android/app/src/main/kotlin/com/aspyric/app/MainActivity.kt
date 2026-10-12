package com.aspyric.app

import android.Manifest
import android.app.StatusBarManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.TimeZone
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "com.aspyric.app/capture"
        private const val REQ_SMS = 5101
        private var channelRef: WeakReference<MethodChannel>? = null

        @Volatile
        var isInForeground = false
            private set
        private val main = Handler(Looper.getMainLooper())

        /** Tells a running Flutter UI that new captures are queued. */
        fun notifyCaptured() {
            main.post { channelRef?.get()?.invokeMethod("onCaptured", null) }
        }
    }

    private var channel: MethodChannel? = null
    private var pendingAction: Map<String, String>? = null
    private var pendingSmsResult: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        channelRef = WeakReference(ch)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                "drainCaptured" -> result.success(CaptureStore.drain(this))
                "localTimezone" -> result.success(TimeZone.getDefault().id)
                "captureSupported" -> result.success(captureSupported())
                "hasSmsPermission" -> result.success(captureSupported() && hasSms())
                "requestSmsPermission" -> requestSms(result)
                "scanSmsInbox" -> {
                    val days = (call.argument<Int>("days") ?: 7).coerceIn(1, 90)
                    io.execute {
                        val rows = try { scanInbox(days) } catch (e: Exception) { emptyList() }
                        main.post { result.success(rows) }
                    }
                }
                "notificationAccessEnabled" -> result.success(
                    NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
                )
                "openNotificationAccessSettings" -> {
                    if (!captureSupported()) return@setMethodCallHandler result.success(null)
                    val i = if (Build.VERSION.SDK_INT >= 30) {
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                            ComponentName(this, PaymentNotificationListener::class.java).flattenToString()
                        )
                    } else {
                        Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    }
                    try {
                        startActivity(i)
                    } catch (e: Exception) {
                        startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                    }
                    result.success(null)
                }
                "setCaptureEnabled" -> {
                    CaptureStore.setEnabled(this, call.argument<Boolean>("sms") ?: false, call.argument<Boolean>("notifications") ?: false)
                    result.success(null)
                }
                "updateWidget" -> {
                    QuickAddWidgetProvider.save(this, call.argument<String>("todaySpent") ?: "", call.argument<Int>("pending") ?: 0)
                    result.success(null)
                }
                "requestPinWidget" -> result.success(requestPinWidget())
                "requestAddTile" -> requestAddTile(result)
                "recognizeText" -> recognizeText(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
        handleIntent(intent, coldStart = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, coldStart = false)
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
        CaptureStore.clearReviewNotification(this)
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    override fun onDestroy() {
        if (channelRef?.get() === channel) channelRef = null
        channel = null
        super.onDestroy()
    }

    // ── Launch actions (widget, tile, shortcuts, share sheet, review notif) ──

    private fun handleIntent(intent: Intent?, coldStart: Boolean) {
        val action = parseIntent(intent) ?: return
        // Consume it so a config change / recreate doesn't replay it.
        intent?.data = null
        intent?.action = Intent.ACTION_MAIN
        if (coldStart || channel == null) {
            pendingAction = action
        } else {
            channel?.invokeMethod("onAction", action)
        }
    }

    private fun parseIntent(intent: Intent?): Map<String, String>? {
        intent ?: return null
        when (intent.action) {
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return null
                if (uri.scheme != "aspyric") return null
                val out = mutableMapOf("kind" to (uri.host ?: return null))
                for (k in uri.queryParameterNames) uri.getQueryParameter(k)?.let { out[k] = it }
                return out
            }
            Intent.ACTION_SEND -> {
                val type = intent.type ?: return null
                if (type.startsWith("text/")) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                    return mapOf("kind" to "capture", "text" to text, "source" to "share")
                }
                if (type.startsWith("image/")) {
                    @Suppress("DEPRECATION")
                    val uri = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    else intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri) ?: return null
                    val path = copyToCache(uri) ?: return null
                    return mapOf("kind" to "image", "path" to path, "source" to "share")
                }
            }
        }
        return null
    }

    private fun copyToCache(uri: Uri): String? = try {
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        dir.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 86_400_000) it.delete() }
        val f = File(dir, "shared_${System.currentTimeMillis()}.img")
        contentResolver.openInputStream(uri)?.use { input -> f.outputStream().use { input.copyTo(it) } }
        f.absolutePath
    } catch (e: Exception) {
        null
    }

    // ── SMS ──────────────────────────────────────────────────────────────

    /**
     * Whether this APK includes the SMS receiver + notification listener
     * (src/capture/AndroidManifest.xml). The default release APK leaves them
     * out so Play Protect doesn't block sideloading it.
     */
    private fun captureSupported(): Boolean = try {
        @Suppress("DEPRECATION")
        val info = packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        info.requestedPermissions?.contains(Manifest.permission.RECEIVE_SMS) == true
    } catch (e: Exception) {
        false
    }

    private fun hasSms(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSms(result: MethodChannel.Result) {
        if (!captureSupported()) return result.success(false)
        if (hasSms()) return result.success(true)
        pendingSmsResult?.success(false)
        pendingSmsResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS), REQ_SMS)
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_SMS) {
            pendingSmsResult?.success(hasSms())
            pendingSmsResult = null
        }
    }

    private fun scanInbox(days: Int): List<Map<String, Any?>> {
        if (!hasSms()) return emptyList()
        val since = System.currentTimeMillis() - days * 86_400_000L
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} DESC"
        )?.use { c ->
            while (c.moveToNext() && out.size < 500) {
                val body = c.getString(2) ?: continue
                if (!CaptureStore.looksTransactional(body)) continue
                out.add(
                    mapOf(
                        "id" to "sms-inbox-${c.getLong(0)}",
                        "source" to "sms",
                        "sender" to c.getString(1),
                        "body" to body,
                        "ts" to c.getLong(3),
                    )
                )
            }
        }
        return out
    }

    // ── Widget / tile ────────────────────────────────────────────────────

    private fun requestPinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val mgr = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!mgr.isRequestPinAppWidgetSupported) return false
        return mgr.requestPinAppWidget(ComponentName(this, QuickAddWidgetProvider::class.java), null, null)
    }

    private fun requestAddTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) return result.success(false)
        val sbm = getSystemService(StatusBarManager::class.java) ?: return result.success(false)
        sbm.requestAddTileService(
            ComponentName(this, QuickAddTileService::class.java),
            "Log expense",
            Icon.createWithResource(this, R.mipmap.ic_launcher),
            mainExecutor
        ) { code ->
            result.success(
                code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                    code == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
            )
        }
    }

    // ── OCR (ML Kit, on-device, free) ────────────────────────────────────

    private fun recognizeText(path: String?, result: MethodChannel.Result) {
        if (path == null) return result.error("bad_args", "path is required", null)
        try {
            val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { text -> result.success(text.text) }
                .addOnFailureListener { e -> result.error("ocr_failed", e.message, null) }
                .addOnCompleteListener { recognizer.close() }
        } catch (e: Exception) {
            result.error("ocr_failed", e.message, null)
        }
    }
}
