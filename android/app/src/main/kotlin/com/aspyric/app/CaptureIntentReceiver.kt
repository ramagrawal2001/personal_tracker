package com.aspyric.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Lets an automation app the user installs from the Play Store (MacroDroid,
 * Tasker, Automate…) hand a bank SMS / payment notification text to Aspyric
 * without Aspyric itself declaring SMS or notification-listener permissions —
 * which Play Protect blocks for sideloaded APKs.
 *
 *   Action:  com.aspyric.app.CAPTURE_TEXT   (explicit broadcast to com.aspyric.app)
 *   Extras:  text   = the message body (required)
 *            sender = optional sender / app name
 *
 * The text only lands in the Review Inbox; nothing is logged until the user
 * confirms it, so a bogus broadcast can't touch the ledger.
 */
class CaptureIntentReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.aspyric.app.CAPTURE_TEXT"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val text = (intent.getStringExtra("text") ?: intent.getStringExtra(Intent.EXTRA_TEXT))?.trim().orEmpty()
        if (text.isEmpty() || text.length > 2000) return
        if (!CaptureStore.looksTransactional(text)) return
        CaptureStore.enqueue(context, "sms", text, intent.getStringExtra("sender"), System.currentTimeMillis())
    }
}
