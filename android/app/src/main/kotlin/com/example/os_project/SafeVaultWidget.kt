package com.example.os_project

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class SafeVaultWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.safe_vault_widget)
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(
                    context, 900, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            // No record names, dates or other vault information is copied outside encrypted storage.
            manager.updateAppWidget(id, views)
        }
    }
    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            SafeVaultWidget().onUpdate(context, manager,
                manager.getAppWidgetIds(ComponentName(context, SafeVaultWidget::class.java)))
        }
    }
}
