package com.aspyric.app

import android.app.Notification
import android.content.pm.ApplicationInfo
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads payment confirmations from UPI / bank / wallet apps (and the SMS app's
 * own notification, which covers bank SMS without needing SMS permission).
 * Only money-looking notifications from known finance packages are queued;
 * everything else is ignored and never stored.
 */
class PaymentNotificationListener : NotificationListenerService() {

    companion object {
        private val ALLOWED = setOf(
            // UPI / wallets
            "com.google.android.apps.nbu.paisa.user", // Google Pay
            "com.phonepe.app",
            "net.one97.paytm",
            "in.org.npci.upiapp", // BHIM
            "in.amazon.mShop.android.shopping",
            "com.dreamplug.androidapp", // CRED
            "com.mobikwik_new",
            "indwin.c3.shareapp", // slice
            "money.jupiter",
            "com.epifi.paisa", // Fi
            "com.whatsapp", // WhatsApp Pay
            // Banks
            "com.snapwork.hdfc", "com.hdfcbank.payzapp", "com.hdfc.retail.banking",
            "com.csam.icici.bank.imobile",
            "com.sbi.lotusintouch", "com.sbi.SBIFreedomPlus",
            "com.axis.mobile",
            "com.msf.kbank.mobile",
            "com.bankofbaroda.mconnect",
            "com.idfcfirstbank.optimus",
            "com.yesbank", "com.indusind.indie",
            // SMS apps → bank SMS text
            "com.google.android.apps.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.oneplus.mms",
            "com.miui.mms",
        )

        fun isFinancePackage(pkg: String, debuggable: Boolean): Boolean {
            if (pkg in ALLOWED) return true
            if (debuggable && pkg == "com.android.shell") return true // adb `cmd notification post` testing
            val p = pkg.lowercase()
            return p.contains("bank") || p.contains("upi") || p.contains("wallet")
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!CaptureStore.notificationsEnabled(this)) return
        if (sbn.packageName == packageName) return
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isFinancePackage(sbn.packageName, debuggable)) return
        val n = sbn.notification ?: return
        // Skip summaries / ongoing ("Payment in progress…") notifications.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = n.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val body = listOf(title, text).filter { it.isNotBlank() }.joinToString(". ")
        if (body.isBlank() || !CaptureStore.looksTransactional(body)) return

        CaptureStore.enqueue(this, "notification", body, sbn.packageName, sbn.postTime)
    }
}
