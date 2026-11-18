package com.juxia.app.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.juxia.app.data.Store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 句栖 · 开机重排提醒
// 二轮#12：与 Application 的 init 并发时 initializing 守卫会让本接收器拿到"未就绪"——
// 必须等 ready 再 reschedule，否则读到空数据、提醒丢失。
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val pending = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                Store.instance.init(ctx.applicationContext)
                var guard = 0
                while (!Store.instance.ready.value && guard++ < 200) delay(50)
                ReminderService.rescheduleAll(ctx.applicationContext)
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }
    }
}
