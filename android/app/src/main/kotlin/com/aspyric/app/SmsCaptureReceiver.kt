package com.aspyric.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/** Queues incoming bank / card / UPI SMS for review (only when enabled). */
class SmsCaptureReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!CaptureStore.smsEnabled(context)) return
        val messages = try { Telephony.Sms.Intents.getMessagesFromIntent(intent) } catch (e: Exception) { null } ?: return
        // A long SMS arrives as several parts — stitch them back per sender.
        messages.filterNotNull().groupBy { it.originatingAddress ?: "" }.forEach { (sender, parts) ->
            val body = parts.joinToString("") { it.messageBody ?: "" }
            if (!CaptureStore.looksTransactional(body)) return@forEach
            val ts = parts.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
            CaptureStore.enqueue(context, "sms", body, sender.ifEmpty { null }, ts)
        }
    }
}
