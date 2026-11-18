package com.juxia.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.argb
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.hazeEffect
import kotlinx.coroutines.delay
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.wrapContentHeight

// 底部导航（翻译自 Index.ets 的 BottomBar：玻璃胶囊 + 选中反色）
@Composable
fun BottomBar(modifier: Modifier = Modifier) {
    val tab by UiState.tab.collectAsState()
    val t = appTokens()
    val dark by UiState.dark.collectAsState()
    val skin by UiState.skin.collectAsState()
    val haze = LocalHazeState.current
    // 对齐鸿蒙 Index.ets BottomBar：经典皮是玻璃胶囊（999 圆角 + 模糊 + 描边 + 投影），朴素皮是素纸条（12 圆角）
    val shape = RoundedCornerShape(if (skin == "plain") 12.dp else 999.dp)
    val bg = when {
        skin == "plain" -> t.cardSolidColor
        dark -> argb("#a62b271e")
        else -> argb("#a6fffdf6")
    }
    Box(modifier.fillMaxWidth().wrapContentHeight(), contentAlignment = Alignment.BottomCenter) {
        Row(
            Modifier
                .widthIn(max = 440.dp)
                .fillMaxWidth(0.92f)
                .navigationBarsPadding()
                .padding(bottom = 14.dp)
                .shadow(if (skin == "plain") 0.dp else 40.dp, shape)
                .clip(shape)
                .background(bg)
                .then(
                    if (skin != "plain" && haze != null) {
                        Modifier.hazeEffect(
                            haze,
                            style = HazeStyle(
                                backgroundColor = bg,
                                tints = emptyList(),
                                blurRadius = 18.dp,
                                noiseFactor = 0f
                            )
                        )
                    } else Modifier
                )
                .clip(shape)
                .border(
                    width = 1.dp,
                    color = if (skin == "plain") t.lineColor else if (dark) argb("#30ffffff") else argb("#8cffffff"),
                    shape = shape
                )
                .padding(7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            listOf(
                "today" to "今日", "mine" to "我的", "library" to "句库",
                "archive" to "回忆", "settings" to "设置"
            ).forEach { (k, n) ->
                val on = tab == k
                Column(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .clip(RoundedCornerShape(999.dp))
                        // 深色用印章色底线标记选中，浅色用反色胶囊（与鸿蒙一致）
                        .background(if (on && !dark) t.inkColor else Color.Transparent)
                        .then(
                            if (on && dark) Modifier.drawBehind {
                                val y = size.height - 0.5f.dp.toPx()
                                drawLine(t.sealColor, Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                            } else Modifier
                        )
                        .clickable { UiState.setTab(k) }
                        .padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    com.juxia.app.ui.TabIcons.TabIcon(
                        name = k,
                        grid = 24,
                        sizeDp = 19.dp,
                        color = if (on && !dark) Color.White else t.inkSoftColor
                    )
                    Text(
                        n,
                        color = if (on && !dark) Color.White else t.inkSoftColor,
                        fontFamily = FontSans, fontSize = 10.sp, letterSpacing = 2.sp
                    )
                }
            }
        }
    }
}

// 轻提示宿主（consume toast 流）
@Composable
fun ToastHost() {
    val t = appTokens()
    var msg by remember { mutableStateOf("") }
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        UiState.toast.collect { m ->
            msg = m
            show = true
            delay(2600)
            show = false
        }
    }
    if (show && msg.isNotEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Text(
                msg,
                color = t.bgColor,
                fontFamily = FontSans,
                fontSize = 13.sp,
                modifier = Modifier
                    .offset { IntOffset(0, -(110.dp.toPx() + UiState.safeBottom.value.dp.toPx()).toInt()) }
                    .clip(RoundedCornerShape(999.dp))
                    .background(t.inkColor)
                    .padding(horizontal = 24.dp, vertical = 12.dp)
            )
        }
    }
}
