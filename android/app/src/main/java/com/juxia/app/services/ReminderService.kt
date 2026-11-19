package com.juxia.app.services

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.juxia.app.data.Store
import java.util.Calendar

// 句栖 · 回访提醒（翻译自 ReminderService.ets：按天聚合 + running/queued 合并）
// 语义映射：鸿蒙 reminderAgent（系统日历式托管）→ AlarmManager exact + 通知。
// 权限前提（manifest 已声明）：POST_NOTIFICATIONS(API 33+)、SCHEDULE_EXACT_ALARM(API 31+)。
object ReminderService {
    const val CHANNEL_ID = "revisit"
    const val EXTRA_DAY_KEY = "com.juxia.app.extra.DAY_KEY"
    const val EXTRA_COUNT = "com.juxia.app.extra.COUNT"
    const val ACTION_REVISIT = "com.juxia.app.action.REVISIT_ALARM"
    private const val RC_BASE = 4100

    private val running = mutableMapOf<String, MutableList<Long>>()
    private val queued = mutableListOf<Pair<android.content.Context, Boolean>>()
    private var queuedAsk = false
    @Volatile private var rescheduling = false

    fun dayKey(ts: Long): Long {
        val c = Calendar.getInstance().apply { timeInMillis = ts }
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    fun ensureChannel(ctx: Context) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "回访提醒", NotificationManager.IMPORTANCE_HIGH)
                )
            }
        } catch (_: Exception) {}
    }

    fun isNotificationEnabled(ctx: Context): Boolean =
        try { NotificationManagerCompat.from(ctx).areNotificationsEnabled() }
        catch (e: Exception) { false }

    /** 重新排程全部回访；requestPermission=true 时顺带发起通知权限请求（需 Activity） */
    fun rescheduleAll(ctx: Context, requestPermission: Boolean = false) {
        ensureChannel(ctx)
        val act = ctx as? Activity
        if (requestPermission && act != null && !isNotificationEnabled(ctx)) {
            if (rescheduling) {
                if (!queuedAsk) { queuedAsk = true; queued.add(ctx to true) }
                return
            }
            queuedAsk = true
            try {
                act.requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 42)
            } catch (e: Exception) {}
            return
        }
        if (rescheduling) {
            if (!queued.any { !it.second }) queued.add(ctx to false)
            return
        }
        rescheduling = true
        try {
            doReschedule(ctx)
        } finally {
            rescheduling = false
            if (!queuedAsk && queued.any { it.second }) {
                queuedAsk = true
                queued.add(ctx to true)
            }
            val next = queued.firstOrNull()
            if (next != null) {
                queued.removeAt(0)
                rescheduleAll(next.first, next.second)
            }
        }
    }

    private fun requestCode(dayKey: Long): Int = RC_BASE + ((dayKey / 86400000L) % 100000).toInt()

    private fun doReschedule(ctx: Context) {
        val store = Store.instance
        val st = store.data
        // 1) 取消旧闹钟（requestCode 由 dayKey 推出；额外防御用旧表里的 dayKey）
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val oldKeys = st.meta.revisitReminderIds.keys.mapNotNull { it.toLongOrNull() }
        for (key in oldKeys) {
            val pi = PendingIntent.getBroadcast(
                ctx, requestCode(key),
                Intent(ctx, RevisitAlarmReceiver::class.java).setAction(ACTION_REVISIT),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pi != null) am.cancel(pi)
        }
        // 2) 全量重排：按天聚合「将来」到期的回访
        //    对齐鸿蒙 ReminderService.doReschedule：只排 e.revisitAt > now，
        //    这样 90 天后的约定能在当天由系统闹钟叫醒，而不是等到用户下次打开应用。
        val now = System.currentTimeMillis()
        val grouped = LinkedHashMap<Long, MutableList<Long>>()
        for (e in st.own) {
            if (e.archAt <= 0 || e.revisitAt <= now) continue
            grouped.getOrPut(dayKey(e.revisitAt)) { mutableListOf() }.add(e.revisitAt)
        }
        val newIds = mutableMapOf<String, Long>()
        for ((key, tsList) in grouped) {
            val t = tsList.minOrNull() ?: continue
            val at = t
            val content = "有 ${tsList.size} 件旧事，到了轻轻回看的时间。"
            val intent = Intent(ctx, RevisitAlarmReceiver::class.java)
                .setAction(ACTION_REVISIT)
                .putExtra(EXTRA_DAY_KEY, key)
                .putExtra(EXTRA_COUNT, tsList.size)
            val pi = PendingIntent.getBroadcast(
                ctx, requestCode(key), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (e: SecurityException) {
                // 无 exact 权限时降级为窗口调度，保证至少能响
                am.setWindow(AlarmManager.RTC_WAKEUP, at, 5 * 60_000, pi)
            }
            newIds[key.toString()] = key
        }
        // 3) 回写映射
        st.meta.revisitReminderIds = newIds.toMutableMap()
        store.saveKv()
    }

    fun cancelAll(ctx: Context) {
        val st = Store.instance.data
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (key in st.meta.revisitReminderIds.keys.mapNotNull { it.toLongOrNull() }) {
            val pi = PendingIntent.getBroadcast(
                ctx, requestCode(key),
                Intent(ctx, RevisitAlarmReceiver::class.java).setAction(ACTION_REVISIT),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pi != null) am.cancel(pi)
        }
        st.meta.revisitReminderIds = mutableMapOf()
        Store.instance.saveKv()
    }

    /** 闹钟触发：发通知；点按回到今日并打开回访（由 MainActivity 消费 extra） */
    class RevisitAlarmReceiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            ensureChannel(ctx)
            val count = intent.getIntExtra(EXTRA_COUNT, 0)
            val content = if (count > 0) "有 $count 件旧事，到了轻轻回看的时间。" else "有旧事到了轻轻回看的时间。"
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                ?.apply { putExtra("open_revisit", true); addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            val pi = open?.let {
                PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_IMMUTABLE)
            }
            val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("句栖 · 轻轻回访")
                .setContentText(content)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try {
                NotificationManagerCompat.from(ctx).notify(4100, n)
            } catch (e: SecurityException) {
                // 通知权限被拒：静默放弃，应用内今日页仍有到期卡片
            }
        }
    }
}
