package com.juxia.app.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import android.graphics.Typeface

// 句栖 · 主题令牌（翻译自 Theme.ets：经典/朴素 × 日间/夜间，色值逐字保留）
// ArkTS 用 8 位十六进制 ARGB 字符串；这里原样存字符串，用 argb() 解析成 Compose Color，
// 方便与鸿蒙版逐值对照。
data class Tokens(
    var bg: String = "#ede6d3",
    var ink: String = "#4f4f4c",
    var inkStrong: String = "#3a3a37",
    var inkSoft: String = "#666257",
    var line: String = "#244f4f4c",
    var lineSoft: String = "#144f4f4c",
    var card: String = "#9efffdf6",
    var cardSolid: String = "#fbf7ec",
    var seal: String = "#b8434a",
    var sealSoft: String = "#1ab8434a",
    var sealInk: String = "#fdf6ea",
    var inputBg: String = "#6bffffff",
    var shadowColor: String = "#14483f2a",
    var shadowLift: String = "#1e483f2a",
    var radiusCard: Float = 18f,
    var radiusBtn: Float = 999f,
    var radiusInput: Float = 14f,
    var plain: Boolean = false,
    var blurCard: Int = 10,
    var tabBg: String = "#c7fbf7ec",
    var toastBottom: Float = 110f,
) {
    val bgColor: Color get() = argb(bg)
    val inkColor: Color get() = argb(ink)
    val inkStrongColor: Color get() = argb(inkStrong)
    val inkSoftColor: Color get() = argb(inkSoft)
    val lineColor: Color get() = argb(line)
    val lineSoftColor: Color get() = argb(lineSoft)
    val cardColor: Color get() = argb(card)
    val cardSolidColor: Color get() = argb(cardSolid)
    val sealColor: Color get() = argb(seal)
    val sealSoftColor: Color get() = argb(sealSoft)
    val sealInkColor: Color get() = argb(sealInk)
    val inputBgColor: Color get() = argb(inputBg)
    val tabBgColor: Color get() = argb(tabBg)
}

fun argb(hex: String): Color {

    // 6 位是 RRGGBB；Compose 的 Color(Long) 需要 AARRGGBB，否则 alpha=0 全透明。
    val c = android.graphics.Color.parseColor(if (hex.startsWith("#")) hex else "#$hex")
    return Color(
        android.graphics.Color.red(c),
        android.graphics.Color.green(c),
        android.graphics.Color.blue(c),
        android.graphics.Color.alpha(c)
    )  // ArkTS 8 位即含 alpha：'#AARRGGBB'
}

fun getTokens(skin: String, dark: Boolean): Tokens {
    val t = Tokens()
    t.plain = skin == "plain"
    if (t.plain) {
        t.radiusCard = 10f
        t.radiusBtn = 8f
        t.radiusInput = 8f
        t.blurCard = 0
        t.toastBottom = 64f
        if (dark) {
            t.bg = "#1b1a17"; t.ink = "#efe9dc"; t.inkStrong = "#f7f2e6"; t.inkSoft = "#b8b0a2"
            t.line = "#26ffffff"; t.lineSoft = "#14ffffff"; t.card = "#ff262420"; t.cardSolid = "#262420"
            t.seal = "#c25a44"; t.sealSoft = "#24c25a44"; t.sealInk = "#f4efe4"; t.inputBg = "#33ffffff"
            t.shadowColor = "#33000000"; t.shadowLift = "#3d000000"; t.tabBg = "#ff242422"
        } else {
            t.bg = "#f5efe2"; t.ink = "#362f26"; t.inkStrong = "#2f2921"; t.inkSoft = "#666257"
            t.line = "#ffded2b8"; t.lineSoft = "#1a362f26"; t.card = "#fffaf5ea"; t.cardSolid = "#faf5ea"
            t.seal = "#b3432b"; t.sealSoft = "#17b3432b"; t.sealInk = "#f7f1e4"; t.inputBg = "#b3f5efe2"
            t.shadowColor = "#0d362f26"; t.shadowLift = "#12362f26"; t.tabBg = "#fffaf5ea"
        }
        return t
    }
    if (dark) {
        t.bg = "#1c1915"; t.ink = "#e9e4d5"; t.inkStrong = "#f4efe2"; t.inkSoft = "#a39c89"
        t.line = "#26e9e4d5"; t.lineSoft = "#14e9e4d5"; t.card = "#d92b261d"; t.cardSolid = "#2b271e"
        t.seal = "#b04f3b"; t.sealSoft = "#2bb04f3b"; t.sealInk = "#fdf6ea"; t.inputBg = "#38000000"
        t.shadowColor = "#52000000"; t.shadowLift = "#5c000000"; t.tabBg = "#d92b271e"
    } else {
        t.bg = "#ede6d3"; t.ink = "#4f4f4c"; t.inkStrong = "#3a3a37"; t.inkSoft = "#666257"
        t.line = "#244f4f4c"; t.lineSoft = "#144f4f4c"; t.card = "#a8f7f1e2"; t.cardSolid = "#f7f1e2"
        t.seal = "#bd5238"; t.sealSoft = "#17bd5238"; t.sealInk = "#fdf6ea"; t.inputBg = "#6bfaf4e6"
        t.shadowColor = "#14483f2a"; t.shadowLift = "#1e483f2a"; t.tabBg = "#c7f7f1e2"
    }
    return t
}

// 字体：猫啃硬笔楷书内嵌（对应鸿蒙 registerFont 的 JuxiaMaoken）
// Compose 的 Font(path) 需要 AssetManager 且无单参 String 重载（编译阻断#5）——
// 改经 Fonts 单例用 Typeface.createFromAsset 加载，JuxiaApp.onCreate 初始化。
object Fonts {
    lateinit var serif: FontFamily
        private set
    val ready: Boolean get() = ::serif.isInitialized
    fun init(app: android.app.Application) {
        if (ready) return
        serif = try {
            FontFamily(Typeface.createFromAsset(app.assets, "fonts/MaokenYingBiKaiShuJ.ttf"))
        } catch (e: Exception) {
            FontFamily.Default
        }
    }
}
val FontSerif: FontFamily
    get() = if (Fonts.ready) Fonts.serif else FontFamily.Default

// 决策（2026-11-16）：钉住通用无衬线，不跟随系统字体换装（鸿蒙版 FONT_SANS 同款语义）。
// 注意：不含字体文件，使用平台 generic sans-serif 解析；随系统"字号"缩放由 settings.fontScaleFollow 单独控制。
val FontSans: FontFamily = FontFamily.SansSerif
