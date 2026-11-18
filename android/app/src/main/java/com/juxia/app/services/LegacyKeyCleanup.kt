package com.juxia.app.services

import android.content.Context
import android.util.Log
import java.security.KeyStore

// 句栖 · 旧版 AI Key 清理（翻译自 LegacyKeyCleanup.ets：删除 Asset Store alias "juxia.ai.key"）
// 安卓侧等价物：AndroidKeyStore 条目 + 旧版 SharedPreferences 文件。全程静默，失败仅记日志。
object LegacyKeyCleanup {
    private const val LEGACY_ALIAS = "juxia.ai.key"

    fun clear(context: Context) {
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (ks.containsAlias(LEGACY_ALIAS)) ks.deleteEntry(LEGACY_ALIAS)
        } catch (e: Exception) {
            Log.e("juxia", "legacy keystore cleanup fail", e)
        }
        try {
            context.deleteSharedPreferences("juxia_ai_key")
            context.deleteSharedPreferences("juxia_ai")
        } catch (e: Exception) {
            Log.e("juxia", "legacy prefs cleanup fail", e)
        }
    }
}
