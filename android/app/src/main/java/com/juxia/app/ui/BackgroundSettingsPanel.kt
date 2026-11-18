package com.juxia.app.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.BgImageStyle
import com.juxia.app.services.BackgroundService
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import kotlinx.coroutines.launch
import java.io.File

// 句栖 · 背景设置面板（翻译自 BackgroundSettingsPanel.ets：经典/朴素×明暗四路 + 滑杆 + 选图）
// 说明：选图当前为"直存"（pick→压缩保存）；鸿蒙版的裁剪页（拖动+双指缩放）待 BackgroundCropPage 批次补齐。
@Composable
private fun bgSliderColors() = SliderDefaults.colors(
    thumbColor = appTokens().sealColor,
    activeTrackColor = appTokens().sealColor,
    inactiveTrackColor = appTokens().lineColor,
    activeTickColor = appTokens().sealColor,
    inactiveTickColor = appTokens().lineColor
)

@Composable
fun BackgroundSettingsPanel(onClose: () -> Unit) {
    val st = Store.instance
    val t = appTokens()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val activity = ctx as? androidx.activity.ComponentActivity

    var editKey by remember { mutableStateOf("light") }
    var resetAsk by remember { mutableStateOf(false) }
    // 背景面板里的浅色/深色与朴素只是预览；关闭后恢复外部主题/皮肤。
    val originalTheme = remember { st.data.settings.theme }
    val originalSkin = remember { st.data.settings.skin }

    fun restoreExternal(): Unit {
        st.data.settings.theme = originalTheme
        st.data.settings.skin = originalSkin
        st.saveSettings()
        UiState.syncFromStore()
        UiState.applyBackground()
    }

    fun closePanel(): Unit {
        restoreExternal()
        onClose()
    }

    val keys = listOf("light" to "经典 · 日间", "dark" to "经典 · 夜间",
                      "lightPlain" to "朴素 · 日间", "darkPlain" to "朴素 · 夜间")

    fun styleOf(key: String): BgImageStyle {
        val b = st.data.settings.background
        return when (key) {
            "light" -> b.light
            "dark" -> b.dark
            "lightPlain" -> b.lightPlain
            else -> b.darkPlain
        }
    }

    fun ensurePlain(key: String) {
        val b = st.data.settings.background
        val plain = if (key == "lightPlain") b.lightPlain else b.darkPlain
        if (plain.path.isNotEmpty()) return
        val src = if (key == "lightPlain") (if (b.lightClassic.path.isNotEmpty()) b.lightClassic else b.light) else (if (b.darkClassic.path.isNotEmpty()) b.darkClassic else b.dark)
        plain.path = src.path
        plain.brightness = src.brightness
        plain.blur = src.blur
        plain.scrim = src.scrim
        if (plain.glowValue == 100) plain.glowValue = src.glowValue
    }

    fun applyTheme(theme: String) {
        st.data.settings.theme = theme
        st.saveSettings()
        UiState.syncFromStore()
    }

    fun applySkin(skin: String) {
        st.data.settings.skin = skin
        st.saveSettings()
        UiState.syncFromStore()
    }

    fun effectiveKey(): String {
        val skin = st.data.settings.skin
        val dark = st.data.settings.theme == "dark" ||
            (st.data.settings.theme == "system" && UiState.systemDark.value)
        return if (skin == "plain") (if (dark) "darkPlain" else "lightPlain")
               else (if (dark) "dark" else "light")
    }

    fun selectKey(key: String) {
        editKey = key
        val s = styleOf(key)
        if (key == effectiveKey()) {
            UiState.applyBackground()
        }
    }

    fun activateKey(key: String) {
        if (key == "light" || key == "dark") {
            val wasPlain = st.data.settings.skin == "plain"
            applyTheme(key)
            applySkin("classic")
            selectKey(key)
            if (wasPlain) UiState.showToast("已切回经典；朴素单独调节请点\"高级\"")
            return
        }
        if (key == "lightPlain" || key == "darkPlain") {
            ensurePlain(key)
            applySkin("plain")
            applyTheme(if (key == "lightPlain") "light" else "dark")
        }
        selectKey(key)
    }



    fun update(style: BgImageStyle, save: () -> Unit) {
        save()
        st.saveSettings()
        if (editKey == effectiveKey()) UiState.applyBackground()
        UiState.bumpBgSaved()
    }

    com.juxia.app.ui.AppSheet(onClose = { closePanel() }) {
        Text("背景", color = t.inkStrongColor, fontFamily = FontSerif, fontSize = 17.sp, letterSpacing = 2.sp)
        Text("浅色 / 深色与朴素浅色 / 深色仅用于预览；关闭后会恢复原来的主题与界面设置。",
            color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp,
            modifier = Modifier.padding(top = 6.dp))
        Spacer(Modifier.height(12.dp))
        keys.forEach { (k, n) ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(n, color = t.inkColor, fontFamily = FontSerif, fontSize = 14.sp)
                    if (k == effectiveKey()) Text("（生效中）", color = t.sealColor, fontFamily = FontSans,
                        fontSize = 10.sp, modifier = Modifier.padding(start = 6.dp))
                }
                Row {
                    QuietButton("调整") { activateKey(k) }
                    QuietButton("换图") {
                        if (activity == null) return@QuietButton
                        scope.launch {
                            val uri = BackgroundService.pick(activity)
                            if (uri.isEmpty()) return@launch
                            try {
                                val stamp = System.currentTimeMillis()
                                val cache = BackgroundService.cachePath(ctx, stamp)
                                BackgroundService.copyToCache(ctx, uri, cache)
                                UiState.setCropRequest(k, cache)
                            } catch (e: Exception) {
                                UiState.showToast("图片读取失败：" + (e.message ?: ""))
                            }
                        }
                    }
                }
            }
        }

        // 生效中的那一路的滑杆
        val s = styleOf(editKey)
        Spacer(Modifier.height(8.dp))
        Text("调整「${keys.find { it.first == editKey }?.second ?: ""}」", color = t.inkSoftColor,
            fontFamily = FontSans, fontSize = 11.sp)
        Text("亮度 ${"%.2f".format(s.brightness)}（>1 为提亮）", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
        Slider(value = s.brightness.toFloat(), onValueChange = {
            update(s) { s.brightness = (it * 100).toInt() / 100.0 }
        }, valueRange = 0.3f..1.5f, colors = bgSliderColors())
        Text("背景模糊 ${s.blur}", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
        Slider(value = s.blur.toFloat(), onValueChange = { update(s) { s.blur = it.toInt() } }, valueRange = 0f..100f, colors = bgSliderColors())
        Text("背景遮罩 ${(s.scrim * 100).toInt()}%", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
        Slider(value = (s.scrim * 100).toFloat(), onValueChange = {
            update(s) { s.scrim = ((it * 2).toInt() / 2.0) / 100.0 }
        }, valueRange = 0f..100f, colors = bgSliderColors())
        Text("氛围光 ${s.glowValue}", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
        Slider(value = s.glowValue.toFloat(), onValueChange = { update(s) { s.glowValue = it.toInt() } }, valueRange = 0f..100f, colors = bgSliderColors())
        Text("纸纹 ${s.grainValue}", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
        Slider(value = s.grainValue.toFloat(), onValueChange = { update(s) { s.grainValue = it.toInt() } }, valueRange = 0f..150f, colors = bgSliderColors())
        if (editKey == "dark" || editKey == "darkPlain") {
            Text("dither ${s.ditherValue}", color = t.inkSoftColor, fontFamily = FontSans, fontSize = 11.sp)
            Slider(value = s.ditherValue.toFloat(), onValueChange = { update(s) { s.ditherValue = it.toInt() } }, valueRange = 0f..100f, colors = bgSliderColors())
        }
        Spacer(Modifier.height(8.dp))
        QuietButton("恢复默认背景") { resetAsk = true }
    }

    if (resetAsk) {
        AlertDialog(
            onDismissRequest = { resetAsk = false },
            title = { Text("恢复默认背景？", fontFamily = FontSerif) },
            text = { Text("当前皮肤与主题的自定义背景会被移除，回到默认渐变。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    val s = styleOf(editKey)
                    s.path = ""
                    s.brightness = 1.0; s.blur = 0; s.scrim = 0.0
                    st.saveSettings()
                    UiState.applyBackground()
                    UiState.bumpBgSaved()
                    resetAsk = false
                }) { Text("恢复", color = t.sealColor) }
            },
            dismissButton = { TextButton(onClick = { resetAsk = false }) { Text("取消") } }
        )
    }
}
