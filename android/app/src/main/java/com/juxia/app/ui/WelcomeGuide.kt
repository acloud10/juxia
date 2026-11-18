package com.juxia.app.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import com.juxia.app.ui.theme.argb
import kotlinx.coroutines.delay
import androidx.compose.foundation.layout.Arrangement

// 句栖 · 新手指引（逐字翻译自 WelcomeGuide.ets：折纸展开 → 使用说明）
private val FLAP_CMDS = arrayOf(
    "M 0 0 L 220 0 L 110 110 Z",
    "M 220 0 L 220 220 L 110 110 Z",
    "M 0 220 L 220 220 L 110 110 Z",
    "M 0 0 L 0 220 L 110 110 Z"
)

private const val GUIDE_TEXT = """这是一个越用越好用（复利效应）的栖息空间。你可以向树洞（完全本地，无云端）倾诉烦恼，也可以把积极的能量储蓄在里面，在能量不足时提取使用；还可以尝试反省自身（板块主体设置可关闭），从而在栖息中获得成长。

晴（写一句）：建议写"对自己说的一句鼓励"，储蓄自我能量
晴（抽一句）：可以抽"一件旧事"，完善心境
雨（写一句）：建议写"让自己难过的事"，倾诉树洞
雨（抽一句）：可以抽"让自己感觉好些的话"，汲取能量

省身（设置中可以关闭）：建议写"我发现了什么 + 下次怎么做"，反思进步
材料：建议只放让自己舒服的文字，详细格式见材料区的"？"，借力外界能量
关联与备注：鼓励、旧事、句库三者可以互相关联，或者各自备注，留下注脚。
回忆与回访：收纳已经归档的文字；旧事按"已解决 / 已放下"分类，鼓励按"看起来很蠢 / 听腻了"分类；而且旧事可以设置回访，继续打磨心境。

个性化：可调整界面（包括印章是否显示、字体大小）、外观（两套UI）、仪式感、抽签来源、应用名（应用内部显示的名字，也就是你给你的App起的名字）、称呼（应用对你的称呼）、启动（可设置启动显示自己喜欢的话，额外的能量）、省身和回访设置等
备份：记得定期备份；恢复会覆盖当前全部数据；没有云同步

隐私：数据只在本机加密保存，材料在应用私有目录；无账号、无广告、无云端统计，不申请网络权限；回访通知是本地提醒；备份由你主动导出！

很棒！接下来你可以写下第一句，也可以给空间起个名字（设置中），还可以告诉空间你的称呼（设置中）。相信这个栖息的空间，你会越用越顺手的。加油！"""

@Composable
fun WelcomeGuide(onDone: () -> Unit) {
    val dark by UiState.dark.collectAsState()
    val skin by UiState.skin.collectAsState()
    val t = appTokens()
    var stage by remember { mutableStateOf("fold") }
    var open by remember { mutableStateOf(false) }
    var entered by remember { mutableStateOf(false) }
    val density = LocalDensity.current

    LaunchedEffect(Unit) { delay(40); entered = true }
    LaunchedEffect(open) { if (open) { delay(1100); stage = "guide" } }

    fun flapFill(i: Int): String = when {
        skin == "plain" && dark -> arrayOf("#332E26", "#2B261F", "#373229", "#302B23")[i]
        skin == "plain" -> t.cardSolid
        dark -> arrayOf("#2E2E29", "#272722", "#31312B", "#2A2A25")[i]
        else -> arrayOf("#fdf9ee", "#f9f5ea", "#f7f2e6", "#fbf6ec")[i]
    }
    val packetFill = when {
        dark && skin == "plain" -> "#2F2A22"
        dark -> "#2B2B26"
        skin == "plain" -> t.cardSolid
        else -> "#fdf9ee"
    }

    val guideScrim = when {
        skin == "plain" && dark -> "#F21B1A17"
        skin == "plain" -> "#F2F5EFE2"
        dark -> "#F21C1915"
        else -> "#F2F6F0E3"
    }
    Box(Modifier.fillMaxSize().background(argb(guideScrim))) {
        if (stage == "fold") {
            Column(
                Modifier.fillMaxSize()
                    .alpha(if (entered) 1f else 0f)
                    .graphicsLayer { scaleX = if (entered) 1f else 0.88f; scaleY = if (entered) 1f else 0.88f },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center
            ) {
                Box(
                    Modifier
                        .size(220.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(argb(packetFill))
                        .clickable { open = true }
                ) {
                    FLAP_CMDS.forEachIndexed { i, cmd ->
                        val rot by animateFloatAsState(
                            targetValue = if (open) (if (i == 1 || i == 2) -178f else 178f) else 0f,
                            animationSpec = tween(850, delayMillis = i * 80, easing = FastOutSlowInEasing),
                            label = "g$i"
                        )
                        val origins = arrayOf(
                            TransformOrigin(0.5f, 0f), TransformOrigin(1f, 0.5f),
                            TransformOrigin(0.5f, 1f), TransformOrigin(0f, 0.5f)
                        )
                        Canvas(
                            Modifier
                                .fillMaxSize()
                                .graphicsLayer {
                                    transformOrigin = origins[i]
                                    cameraDistance = with(density) { 900.dp.toPx() }
                                    if (i == 0 || i == 2) rotationX = rot else rotationY = rot
                                }
                        ) {
                            drawPath(
                                com.juxia.app.ui.SvgPath.parse(cmd, size.width / 220.0),
                                color = argb(flapFill(i))
                            )
                        }
                    }
                    if (!open) {
                        Text("展开", fontFamily = FontSerif, fontSize = 14.sp, letterSpacing = 8.sp,
                            color = if (dark) t.inkSoftColor else if (skin == "plain") t.inkSoftColor else argb("#6b5a5032"),
                            modifier = Modifier.align(Alignment.Center))
                    }
                }
                if (!open) {
                    Text("点一下，展开", fontFamily = FontSans, fontSize = 12.sp, letterSpacing = 3.sp,
                        color = t.inkSoftColor, modifier = Modifier.padding(top = 22.dp))
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
                Column(Modifier.fillMaxWidth().padding(top = 30.dp, bottom = 14.dp),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("新手指引", fontFamily = FontSerif, fontSize = 32.sp, letterSpacing = 6.sp,
                        color = t.inkStrongColor)
                    Text("（建议耐心看完，对于日后大有助益哦！也可以稍后在设置-关于查看）",
                        fontFamily = FontSans, fontSize = 13.sp, lineHeight = 22.sp,
                        color = t.inkSoftColor, textAlign = TextAlign.Center)
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    Text(GUIDE_TEXT, fontFamily = FontSans, fontSize = 13.5.sp, lineHeight = 25.sp,
                        color = t.inkColor, modifier = Modifier.fillMaxWidth())
                }
                Text("开始使用", fontFamily = FontSans, fontSize = 14.sp, letterSpacing = 2.sp,
                    color = t.bgColor, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                        .padding(top = 14.dp, bottom = 22.dp)
                        .clip(RoundedCornerShape(t.radiusBtn.dp))
                        .background(t.inkColor)
                        .clickable(onClick = onDone)
                        .padding(vertical = 14.dp))
            }
        }
    }
}
