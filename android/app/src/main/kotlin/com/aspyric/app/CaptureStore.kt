package com.aspyric.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native queue of captured money messages (bank SMS, payment-app
 * notifications). The receivers write here even when Flutter isn't running;
 * the Dart side drains it on launch / resume via the capture channel and
 * turns each entry into a review-inbox item. Nothing is ever logged to the
 * ledger without the user confirming it in the app.
 */
object CaptureStore {
    private const val PREFS = "aspyric_capture"
    private const val KEY_QUEUE = "queue"
    private const val KEY_SMS = "sms_enabled"
    private const val KEY_NOTIF = "notif_enabled"
    private const val MAX_QUEUE = 200
    private const val CHANNEL_ID = "capture_inbox"
    private const val REVIEW_NOTIFICATION_ID = 424242

    // Mirrors BankMessageParser.looksTransactional + its reject list (Dart),
    // kept deliberately loose — the Dart parser makes the final call.
    private val amountRe = Regex("(?i)(rs\\.?|inr|₹)\\s*[\\d,]+(\\.\\d{1,2})?|[\\d,]+(\\.\\d{1,2})?\\s*(rs\\.?|inr|₹)")
    private val verbRe = Regex("(?i)\\b(debited|spent|paid|sent|withdrawn|purchase|txn|transaction|charged|credited|received|deposited|refund|debit)")
    private val rejectRe = Regex("(?i)\\b(otp|one time password|verification code)\\b")

    fun looksTransactional(text: String): Boolean =
        amountRe.containsMatchIn(text) && verbRe.containsMatchIn(text) && !rejectRe.containsMatchIn(text)

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun smsEnabled(ctx: Context) = prefs(ctx).getBoolean(KEY_SMS, false)
    fun notificationsEnabled(ctx: Context) = prefs(ctx).getBoolean(KEY_NOTIF, false)

    fun setEnabled(ctx: Context, sms: Boolean, notifications: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_SMS, sms).putBoolean(KEY_NOTIF, notifications).apply()
    }

    @Synchronized
    fun enqueue(ctx: Context, source: String, body: String, sender: String?, ts: Long) {
        val p = prefs(ctx)
        val arr = try { JSONArray(p.getString(KEY_QUEUE, "[]")) } catch (e: Exception) { JSONArray() }
        val id = "$source-${sender ?: ""}-$ts-${body.hashCode()}"
        for (i in 0 until arr.length()) {
            if (arr.optJSONObject(i)?.optString("id") == id) return
        }
        val o = JSONObject()
            .put("id", id)
            .put("source", source)
            .put("body", body)
            .put("sender", sender ?: JSONObject.NULL)
            .put("ts", ts)
        arr.put(o)
        // Bounded: drop the oldest if the app hasn't been opened in ages.
        val trimmed = JSONArray()
        val start = maxOf(0, arr.length() - MAX_QUEUE)
        for (i in start until arr.length()) trimmed.put(arr.get(i))
        p.edit().putString(KEY_QUEUE, trimmed.toString()).apply()

        // Post first: a live app drains (and, if in the foreground, clears) it.
        postReviewNotification(ctx, trimmed.length(), body)
        MainActivity.notifyCaptured()
    }

    @Synchronized
    fun drain(ctx: Context): List<Map<String, Any?>> {
        val p = prefs(ctx)
        val arr = try { JSONArray(p.getString(KEY_QUEUE, "[]")) } catch (e: Exception) { JSONArray() }
        p.edit().putString(KEY_QUEUE, "[]").apply()
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "id" to o.optString("id"),
                    "source" to o.optString("source"),
                    "body" to o.optString("body"),
                    "sender" to (if (o.isNull("sender")) null else o.optString("sender")),
                    "ts" to o.optLong("ts"),
                )
            )
        }
        // Keep the "review" notification while the app is only in the
        // background — a background drain must not silently swallow the alert.
        if (MainActivity.isInForeground) clearReviewNotification(ctx)
        return out
    }

    fun clearReviewNotification(ctx: Context) {
        NotificationManagerCompat.from(ctx).cancel(REVIEW_NOTIFICATION_ID)
    }

    private fun postReviewNotification(ctx: Context, count: Int, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Detected transactions", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Transactions found in bank SMS / payment notifications, waiting for review"
                }
            )
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("aspyric://inbox"), ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(ctx, 7001, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val amount = amountRe.find(body)?.value?.trim()
        val title = if (count <= 1) "New transaction detected${if (amount != null) " · $amount" else ""}"
        else "$count transactions to review"
        val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_aspyric)
            .setContentTitle(title)
            .setContentText("Tap to review and log it in Aspyric")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body.take(240)))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(REVIEW_NOTIFICATION_ID, n)
        } catch (_: SecurityException) {
        }
    }
}
