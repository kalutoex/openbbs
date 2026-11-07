package org.openbbs.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 上传期间的前台服务。
 *
 * 安卓把退到后台的应用当闲人看：几分钟不碰就把进程冻住，网络请求挂在那儿不动。
 * 一个 1GB 的包要传十几分钟，这中间人不可能一直盯着云盘页。
 * 挂上前台服务并配一条通知，系统就认这是"正在干活"，不冻。
 *
 * 它自己不传东西——上传还在 Dart 那边跑，这里只负责让进程活着，顺便把进度摆出来。
 */
class UploadService : Service() {

    companion object {
        private const val CHANNEL = "openbbs_upload"
        private const val NOTIFY_ID = 9001

        fun start(ctx: Context, title: String, text: String) {
            val i = Intent(ctx, UploadService::class.java).apply {
                putExtra("title", title)
                putExtra("text", text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, UploadService::class.java))
        }
    }

    private var title = "正在上传"
    private var text = ""
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        channel()
    }

    private fun channel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val m = getSystemService(NotificationManager::class.java)
        if (m.getNotificationChannel(CHANNEL) != null) return
        val c = NotificationChannel(CHANNEL, "上传", NotificationManager.IMPORTANCE_LOW)
        c.description = "上传文件时显示进度"
        c.setShowBadge(false)
        m.createNotificationChannel(c)
    }

    private fun build(pct: Int): Notification {
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pi = if (open != null) {
            PendingIntent.getActivity(
                this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else null
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        b.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        if (pi != null) b.setContentIntent(pi)
        if (pct in 0..100) {
            b.setProgress(100, pct, pct <= 0)
        }
        return b.build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        title = intent?.getStringExtra("title") ?: title
        text = intent?.getStringExtra("text") ?: text
        val n = build(-1)
        if (!started) {
            started = true
            // 五分钟内必须真的调一次 startForeground，否则系统直接抛异常。
            startForeground(NOTIFY_ID, n)
        } else {
            val m = getSystemService(NotificationManager::class.java)
            m.notify(NOTIFY_ID, n)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        started = false
        super.onDestroy()
    }
}
