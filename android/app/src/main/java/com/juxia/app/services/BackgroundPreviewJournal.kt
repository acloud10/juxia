package com.juxia.app.services

import android.content.Context
import com.juxia.app.data.Store

/**
 * 背景面板的“仅预览”会临时写 settings.theme/skin。
 * 正常退出由面板恢复；这里额外落一份原始值，进程被杀后下次启动可恢复。
 */
object BackgroundPreviewJournal {
    private const val PREF = "juxia_prefs"
    private const val KEY_THEME = "bg_preview_theme"
    private const val KEY_SKIN = "bg_preview_skin"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun write(ctx: Context, theme: String, skin: String) {
        prefs(ctx).edit()
            .putString(KEY_THEME, theme)
            .putString(KEY_SKIN, skin)
            .commit()
    }

    fun clear(ctx: Context) {
        prefs(ctx).edit().remove(KEY_THEME).remove(KEY_SKIN).commit()
    }

    fun recover(ctx: Context) {
        val p = prefs(ctx)
        val theme = p.getString(KEY_THEME, null) ?: return
        val skin = p.getString(KEY_SKIN, null) ?: return
        try {
            val s = Store.instance.data.settings
            s.theme = theme
            s.skin = skin
            Store.instance.saveSettings()
        } finally {
            clear(ctx)
        }
    }
}
