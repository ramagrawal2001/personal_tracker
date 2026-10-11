package com.aspyric.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews

/** Home-screen widget: today's spend + one-tap Expense / Income / Voice / Scan. */
class QuickAddWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS = "aspyric_widget"

        fun save(ctx: Context, todaySpent: String, pending: Int) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("todaySpent", todaySpent)
                .putInt("pending", pending)
                .apply()
            refreshAll(ctx)
        }

        fun refreshAll(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, QuickAddWidgetProvider::class.java))
            for (id in ids) mgr.updateAppWidget(id, build(ctx))
        }

        private fun link(ctx: Context, uri: String, req: Int): PendingIntent {
            val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri), ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(ctx, req, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun build(ctx: Context): RemoteViews {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = RemoteViews(ctx.packageName, R.layout.widget_quick_add)
            v.setTextViewText(R.id.widget_today, p.getString("todaySpent", null) ?: "Tap + to log")
            val pending = p.getInt("pending", 0)
            if (pending > 0) {
                v.setViewVisibility(R.id.widget_pending, View.VISIBLE)
                v.setTextViewText(R.id.widget_pending, "$pending to review")
                v.setOnClickPendingIntent(R.id.widget_pending, link(ctx, "aspyric://inbox", 8005))
            } else {
                v.setViewVisibility(R.id.widget_pending, View.GONE)
            }
            v.setOnClickPendingIntent(R.id.widget_expense, link(ctx, "aspyric://add?type=expense&source=widget", 8001))
            v.setOnClickPendingIntent(R.id.widget_income, link(ctx, "aspyric://add?type=income&source=widget", 8002))
            v.setOnClickPendingIntent(R.id.widget_voice, link(ctx, "aspyric://voice?source=widget", 8003))
            v.setOnClickPendingIntent(R.id.widget_scan, link(ctx, "aspyric://scan?source=widget", 8004))
            v.setOnClickPendingIntent(R.id.widget_header, link(ctx, "aspyric://add?type=expense&source=widget", 8006))
            return v
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, build(context))
    }
}
