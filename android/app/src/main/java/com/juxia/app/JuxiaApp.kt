package com.juxia.app

import android.app.Application
import com.juxia.app.data.Store
import com.juxia.app.services.MaterialRepair
import com.juxia.app.services.ReminderService
import com.juxia.app.services.RestoreRecovery
import com.juxia.app.services.AppError
import com.juxia.app.services.BackgroundPreviewJournal
import com.juxia.app.state.UiState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// 句栖 · Application（对应 EntryAbility 的 onCreate + Index 启动序列的数据段）
// 启动序列：Store.init → RestoreRecovery（恢复日志收尾）→ MaterialRepair（索引自愈）。
// 字体在 Compose 侧按需加载（assets/fonts/MaokenYingBiKaiShuJ.ttf）；隐私门/引导/boot 屏在 MainActivity。
class JuxiaApp : Application() {
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        com.juxia.app.ui.theme.Fonts.init(this)
        ReminderService.ensureChannel(this)
        AppError.listener = { r ->
            UiState.showToast(if (r.hint.isBlank()) r.title else "${r.title}${r.hint}")
        }
        appScope.launch {
            try {
                Store.instance.init(this@JuxiaApp)
            } catch (e: Exception) {
                // init 内部已报 AppError；兜底仅吞异常，避免崩溃
            }
            try {
                RestoreRecovery.recover(this@JuxiaApp)
            } catch (e: Exception) {
            }
            try {
                MaterialRepair.run(this@JuxiaApp)
            } catch (e: Exception) {
            }
        }
    }
}
