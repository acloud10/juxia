package com.juxia.app.model

import kotlinx.serialization.Serializable

// 句栖 · 背景图配置（翻译自 BackgroundStyle.ets；from() 的逐项默认值与钳制原样保留）
@Serializable
data class BgImageStyle(
    var path: String = "",
    var brightness: Double = 1.0,
    var blur: Int = 0,
    var scrim: Double = 0.0,
    var glowValue: Int = 100,
    var grainValue: Int = 100,
    var ditherValue: Int = 100,
) {
    companion object {
        fun from(src: BgImageStyle?, glowDefault: Int, grainDefault: Int): BgImageStyle {
            val x = BgImageStyle(glowValue = glowDefault, grainValue = grainDefault)
            if (src == null) return x
            x.path = src.path
            x.brightness = (if (src.brightness.isNaN()) 1.0 else src.brightness).coerceIn(0.0, 1.5)
            x.blur = src.blur.coerceIn(0, 100)
            x.scrim = (if (src.scrim.isNaN()) 0.0 else src.scrim).coerceIn(0.0, 1.0)
            x.glowValue = src.glowValue.coerceIn(0, 100)
            x.grainValue = src.grainValue.coerceIn(0, 150)
            x.ditherValue = src.ditherValue.coerceIn(0, 100)
            return x
        }
    }
}

@Serializable
data class BackgroundStyle(
    var light: BgImageStyle = BgImageStyle(glowValue = 100, grainValue = 0),
    var dark: BgImageStyle = BgImageStyle(glowValue = 100, grainValue = 100),
    var lightClassic: BgImageStyle = BgImageStyle(glowValue = 100, grainValue = 0),
    var lightPlain: BgImageStyle = BgImageStyle(glowValue = 0, grainValue = 0),
    var darkClassic: BgImageStyle = BgImageStyle(glowValue = 100, grainValue = 100),
    var darkPlain: BgImageStyle = BgImageStyle(glowValue = 100, grainValue = 100),
    var glow: String = "normal",
    var glowValue: Int = 100,
    var dither: Boolean = true,
    var ditherValue: Int = 100,
    var grain: String = "normal",
    var grainValue: Int = 100,
) {
    companion object {
        fun from(src: BackgroundStyle?): BackgroundStyle {
            val x = BackgroundStyle()
            if (src == null) return x
            x.light = BgImageStyle.from(src.light, 100, 0)
            x.dark = BgImageStyle.from(src.dark, 100, 100)
            x.lightClassic = BgImageStyle.from(src.lightClassic, 100, 0)
            x.lightPlain = BgImageStyle.from(src.lightPlain, 0, 0)
            x.darkClassic = BgImageStyle.from(src.darkClassic, 100, 100)
            x.darkPlain = BgImageStyle.from(src.darkPlain, 100, 100)
            x.glow = src.glow.takeIf { it == "off" || it == "weak" || it == "normal" } ?: "normal"
            x.glowValue = src.glowValue.coerceIn(0, 100)
            x.dither = src.dither
            x.ditherValue = if (!x.dither && src.ditherValue == 100) 0 else src.ditherValue.coerceIn(0, 100)
            x.grain = src.grain.takeIf { it == "off" || it == "weak" || it == "normal" } ?: "normal"
            x.grainValue = src.grainValue.coerceIn(0, 150)
            return x
        }
    }
}
