package com.juxia.app.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.RitualCtx
import com.juxia.app.model.sealCN
import com.juxia.app.model.todayStr
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import com.juxia.app.ui.theme.argb
import kotlinx.coroutines.delay
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import androidx.compose.foundation.layout.Arrangement

// 句栖 · 抽签仪式（翻译自 RitualOverlay.ets：折纸四瓣 3D → 逐字揭示；朴素皮竖排签纸）
// 动作语义：收下/放回去=今日流程完成；收入句库/不喜欢/换一句=句库流。
private val FLAP_CMDS = arrayOf(
    "M0 0L220 0L110 110Z",   // top
    "M220 0L220 220L110 110Z",// right
    "M0 220L220 220L110 110Z",// bottom
    "M0 0L0 220L110 110Z"     // left
)

@Composable
fun RitualOverlay(
    ctx: RitualCtx,
    onClose: () -> Unit,
    onBind: (String) -> Unit,
    onArchive: (String) -> Unit
) {
    val st = Store.instance
    val t = appTokens()
    val skin by UiState.skin.collectAsState()
    val appName = st.data.settings.appName
    val density = LocalDensity.current

    var stage by remember { mutableStateOf("") } // packet / reveal
    var revealed by remember { mutableStateOf(false) }
    var packetOpen by remember { mutableStateOf(false) }
    var replyOpen by remember { mutableStateOf(false) }
    var replyText by remember { mutableStateOf("") }
    var showSource by remember { mutableStateOf(false) }

    val text: String = ctx.entry?.text ?: ctx.text
    val entry = ctx.entry
    val replyCount = entry?.let { st.repliesOf(it.id).size } ?: 0

    // 初始化：按仪式感档位决定起点
    LaunchedEffect(ctx) {
        when (st.data.settings.ritualMode) {
            "off" -> { stage = "reveal"; revealed = true }
            "short" -> { stage = "reveal"; delay(60); revealed = true }
            else -> stage = "packet"
        }
    }
    // 折纸展开 → 揭示
    LaunchedEffect(packetOpen) {
        if (packetOpen) {
            delay(1150)
            stage = "reveal"
            delay(40)
            revealed = true
        }
    }

    fun accept() {
        if (ctx.type != "lib" || ctx.todayFlow) st.markDrew()
        onClose()
    }
    fun saveLib() {
        val ok = st.addLib(text, ctx.source, ctx.origin.ifEmpty { "material" }, ctx.tag.ifEmpty { "原文" })
        UiState.showToast(if (ok) "已收入句库" else "句库里已有这句")
        accept()
    }
    fun dislike() {
        st.addDislike(text, ctx.source, ctx.origin)
        UiState.showToast("已加入排除名单，不会再出现")
        accept()
    }
    fun redraw() {
        // 同池重抽（排除当前句；与 Index.redrawRitual 对齐）
        if (ctx.type == "own" && entry != null) {
            val pool = st.ownActive(entry.kind).filter { it.text != text }
            if (pool.isEmpty()) { UiState.showToast("这一类只有这一句"); return }
            val e = pool.random()
            UiState.startRitual(ctx.copy(entry = e, text = e.text))
            return
        }
        val pool = st.libPool().filter { it.text != text }
        if (pool.isEmpty()) { UiState.showToast("句库里没有别的句子了"); return }
        val b = pool.random()
        UiState.startRitual(ctx.copy(
            type = "lib", entry = null, text = b.text, source = b.source,
            badge = "句库 · 收藏", tag = if (b.tag.isNotEmpty()) b.tag else "原文", origin = b.origin))
    }
    fun saveReply() {
        val body = replyText.trim()
        if (body.isEmpty()) { UiState.showToast("先写一句再回"); return }
        if (entry != null && st.addReply(entry.id, body, "draw")) {
            UiState.showToast("回好了，下次抽到会一起出现")
            replyOpen = false
            replyText = ""
        } else UiState.showToast("这句话没有保存成功，再试一次")
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(t.bgColor)
    ) {
        if (stage == "packet") {
            // 折纸信笺：四瓣 3D 展开
            Box(
                Modifier
                    .align(Alignment.Center)
                    .width(220.dp)
                    .height(220.dp)
                    .clickable(enabled = !packetOpen) { packetOpen = true }
            ) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(t.cardSolidColor, RoundedCornerShape(4.dp))
                )
                val origins = arrayOf(
                    TransformOrigin(0.5f, 0f), TransformOrigin(1f, 0.5f),
                    TransformOrigin(0.5f, 1f), TransformOrigin(0f, 0.5f)
                )
                val tints = arrayOf(0.03f, 0.05f, 0.07f, 0.04f)
                FLAP_CMDS.forEachIndexed { i, cmd ->
                    val rot by animateFloatAsState(
                        targetValue = if (packetOpen) 178f else 0f,
                        animationSpec = tween(850, delayMillis = i * 80, easing = FastOutSlowInEasing),
                        label = "flap$i"
                    )
                    Canvas(
                        Modifier
                            .fillMaxSize()
                            .graphicsLayer {
                                transformOrigin = origins[i]
                                cameraDistance = with(density) { 900.dp.toPx() }
                                if (i == 0 || i == 2) rotationX = rot else rotationY = if (i == 1) -rot else rot
                            }
                    ) {
                        val p = com.juxia.app.ui.SvgPath.parse(cmd, size.width / 220.0)
                        drawPath(p, color = t.cardSolidColor)
                        // 每瓣明暗微差
                        drawPath(p, color = Color.Black.copy(alpha = tints[i] * 0.6f))
                    }
                }
                if (!packetOpen) {
                    Text(
                        "展开",
                        color = t.inkSoftColor,
                        fontFamily = FontSerif,
                        fontSize = 14.sp,
                        letterSpacing = 18.sp,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
            }
        } else {
            RevealStage(
                ctx = ctx, text = text, revealed = revealed, showSource = showSource,
                skin = skin, appName = appName, t = t,
                onToggleSource = { showSource = !showSource },
                replyCount = replyCount,
                onAccept = ::accept, onSaveLib = ::saveLib, onDislike = ::dislike, onRedraw = ::redraw,
                onReply = { replyOpen = true },
                onBind = { entry?.let { onBind(it.id) } },
                onArchive = { entry?.let { onArchive(it.id) } }
            )
        }

        if (stage == "packet") {
            Text(
                "跳过 ›",
                color = t.inkSoftColor,
                fontFamily = FontSans,
                fontSize = 11.5.sp,
                letterSpacing = 2.sp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 54.dp, end = 20.dp)
                    .background(t.cardColor, RoundedCornerShape(999.dp))
                    .clickable { packetOpen = true }
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }

        if (replyOpen) {
            ReplySheet(
                text = text, value = replyText, onChange = { replyText = it },
                onCancel = { replyOpen = false },
                onSave = ::saveReply
            )
        }
    }
}

@Composable
private fun RevealStage(
    ctx: RitualCtx, text: String, revealed: Boolean, showSource: Boolean,
    skin: String, appName: String, t: com.juxia.app.ui.theme.Tokens,
    onToggleSource: () -> Unit, replyCount: Int,
    onAccept: () -> Unit, onSaveLib: () -> Unit, onDislike: () -> Unit, onRedraw: () -> Unit,
    onReply: () -> Unit, onBind: () -> Unit, onArchive: () -> Unit
) {
    Box(Modifier.fillMaxSize()) {
        when {
            text.length > 80 -> LongReveal(ctx, text, revealed, showSource, t)
            skin == "plain" -> PlainPaper(text, revealed, appName, t)
            else -> ClassicReveal(ctx, text, revealed, showSource, t)
        }

        // 出处角标（透明命中区不影响下层）
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(top = 54.dp, end = 20.dp), horizontalArrangement = Arrangement.End) {
                Text(
                    "出处 · ${ctx.tag}",
                    color = t.inkSoftColor,
                    fontFamily = FontSans,
                    fontSize = 10.5.sp,
                    letterSpacing = 1.6.sp,
                    modifier = Modifier
                        .background(t.cardColor, RoundedCornerShape(999.dp))
                        .clickable(onClick = onToggleSource)
                        .padding(horizontal = 14.dp, vertical = 6.dp)
                )
            }
            if (showSource) {
                Text(
                    ctx.source,
                    color = t.inkColor,
                    fontFamily = FontSans,
                    fontSize = 12.sp,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp, end = 20.dp),
                    textAlign = TextAlign.End
                )
            }
        }

        // 动作区
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (ctx.type == "own" && replyCount > 0) {
                Text("你回过它 $replyCount 句", color = t.inkSoftColor, fontSize = 11.sp,
                    fontFamily = FontSans, letterSpacing = 1.sp)
            }
            when {
                ctx.type == "own" && ctx.entry?.kind == "encourage" -> {
                    ActionPrimary("收下", t, onAccept)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        ActionQuiet("回一句话", t, onReply)
                        ActionQuiet("为它选一件旧事", t, onBind)
                        ActionQuiet("不再参与抽签", t, onArchive)
                    }
                }
                ctx.type == "own" && ctx.entry?.kind == "wound" -> {
                    Text("还没准备好就放回去，完全没关系。", color = t.inkSoftColor, fontSize = 12.sp,
                        fontFamily = FontSans, modifier = Modifier.padding(bottom = 4.dp))
                    ActionPrimary("先放回去", t, onAccept)
                    ActionQuiet("回一句话", t, onReply)
                    ActionQuiet("标记已解决 / 已放下", t, onArchive)
                }
                else -> {
                    ActionPrimary("收入句库", t, onSaveLib)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        ActionQuiet("先收下，不入库", t, onAccept)
                        ActionQuiet("不喜欢", t, onDislike)
                        ActionQuiet("换一句", t, onRedraw)
                    }
                }
            }
        }
    }
}

@Composable
private fun CharReveal(text: String, revealed: Boolean, t: com.juxia.app.ui.theme.Tokens) {
    Row {
        text.toList().forEachIndexed { i, ch ->
            val alpha by animateFloatAsState(
                targetValue = if (revealed) 1f else 0f,
                animationSpec = tween(500, delayMillis = min(i * 26, 1050)),
                label = "ch$i"
            )
            val ty by animateFloatAsState(
                targetValue = if (revealed) 0f else 8f,
                animationSpec = tween(500, delayMillis = min(i * 26, 1050)),
                label = "ty$i"
            )
            Text(
                text = ch.toString(),
                color = t.inkStrongColor,
                fontFamily = FontSerif,
                fontSize = 18.sp,
                lineHeight = 32.sp,
                modifier = Modifier
                    .alpha(alpha)
                    .graphicsLayer { translationY = ty }
            )
        }
    }
}

@Composable
private fun ClassicReveal(ctx: RitualCtx, text: String, revealed: Boolean, showSource: Boolean, t: com.juxia.app.ui.theme.Tokens) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 30.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(ctx.badge, color = t.sealColor, fontFamily = FontSans, fontSize = 10.sp,
            letterSpacing = 3.4.sp, modifier = Modifier.padding(bottom = 30.dp))
        CharReveal(text, revealed, t)
        if (showSource) {
            Text(ctx.source, color = t.inkColor, fontFamily = FontSans, fontSize = 12.sp,
                modifier = Modifier.padding(top = 12.dp), textAlign = TextAlign.Center)
        }
    }
    Text("「", color = t.sealColor.copy(alpha = 0.1f), fontFamily = FontSerif, fontSize = 96.sp,
        modifier = Modifier.offset(x = 24.dp, y = 120.dp))
    Text("」", color = t.sealColor.copy(alpha = 0.1f), fontFamily = FontSerif, fontSize = 96.sp,
        modifier = Modifier.offset(x = 270.dp, y = 560.dp))
}

@Composable
private fun LongReveal(ctx: RitualCtx, text: String, revealed: Boolean, showSource: Boolean, t: com.juxia.app.ui.theme.Tokens) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(ctx.badge, color = t.sealColor, fontFamily = FontSans, fontSize = 10.sp, letterSpacing = 3.4.sp)
        Spacer(Modifier.height(14.dp))
        Column(Modifier.fillMaxWidth(0.88f).heightIn(max = 360.dp).verticalScroll(rememberScrollState())) {
            Text(text, color = t.inkStrongColor, fontFamily = FontSerif, fontSize = 18.sp, lineHeight = 32.sp)
        }
        if (showSource) {
            Text(ctx.source, color = t.inkColor, fontFamily = FontSans, fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth(0.88f).padding(top = 12.dp), textAlign = TextAlign.Center)
        }
    }
}

// ---------- 朴素皮：竖排签纸（列右起、标点不置列首） ----------

private fun vColumns(text: String, fontPx: Double): List<List<Char>> {
    val maxRows = max(1, floor(300.0 / (fontPx * 1.85)).toInt())
    val cols = mutableListOf<List<Char>>()
    var cur = mutableListOf<Char>()
    for (ch in text) {
        if (cur.size >= maxRows) { cols.add(cur); cur = mutableListOf() }
        cur.add(ch)
        if ("，。！？；：、」』）】…—".contains(ch)) {
            cols.add(cur); cur = mutableListOf()
        }
    }
    if (cur.isNotEmpty()) cols.add(cur)
    return cols.reversed()  // 右起第一列
}

private fun plainFontSize(n: Int): Double = max(13.0, min(21.0, 22.0 - n * 0.055))

private fun plainWidth(n: Int, fontPx: Double): Double {
    var f = fontPx
    var width = 320.0
    val maxW = 330.0
    for (i in 0 until 5) {
        val maxRows = max(1, floor(300.0 / (f * 1.85)).toInt())
        val cols = max(1, kotlin.math.ceil(n.toDouble() / maxRows).toInt())
        width = cols * f * 1.18 + 40.0
        if (width < maxW) break
        f *= 0.92
    }
    return min(maxW, max(width, 196.0))
}

@Composable
private fun PlainPaper(text: String, revealed: Boolean, appName: String, t: com.juxia.app.ui.theme.Tokens) {
    val n = text.length
    var f = plainFontSize(n)
    var width = plainWidth(n, f)
    // 宽度反推字号（与 ArkTS 迭代一致）
    for (i in 0 until 5) {
        val maxRows = max(1, floor(300.0 / (f * 1.85)).toInt())
        val cols = max(1, kotlin.math.ceil(n.toDouble() / maxRows).toInt())
        width = cols * f * 1.18 + 40.0
        if (width < 330.0) break
        f *= 0.92
    }
    val cols = vColumns(text, f)

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .width(width.dp)
                .height(420.dp)
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(listOf(t.cardSolidColor, t.bgColor)),
                        RoundedCornerShape(8.dp)
                    )
            )
            // 签头红条
            Box(
                Modifier
                    .offset(x = (width * 0.21).dp, y = 12.dp)
                    .width((width * 0.58).dp)
                    .height(10.dp)
                    .background(Brush.verticalGradient(listOf(argb("#c14e33"), t.sealColor)),
                        RoundedCornerShape(3.dp))
            )
            // 竖排列
            Row(
                Modifier
                    .offset(x = 20.dp, y = 50.dp)
                    .width((width - 40).dp)
                    .height(300.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                cols.forEachIndexed { ci, col ->
                    Column(Modifier.width((f * 1.18).dp)) {
                        col.forEachIndexed { i, ch ->
                            val alpha by animateFloatAsState(
                                targetValue = if (revealed) 1f else 0f,
                                animationSpec = tween(500, delayMillis = min((ci * 6 + i) * 26, 1050)),
                                label = "p${ci}_$i"
                            )
                            val ty by animateFloatAsState(
                                targetValue = if (revealed) 0f else 8f,
                                animationSpec = tween(500, delayMillis = min((ci * 6 + i) * 26, 1050)),
                                label = "pt${ci}_$i"
                            )
                            Text(
                                ch.toString(),
                                color = t.inkColor,
                                fontFamily = FontSerif,
                                fontSize = f.sp,
                                lineHeight = (f * 1.85).sp,
                                modifier = Modifier.alpha(alpha).graphicsLayer { translationY = ty }
                            )
                        }
                    }
                }
            }
            // 印章
            Column(
                Modifier
                    .offset(x = 12.dp, y = 356.dp)
                    .background(Color.Transparent)
                    .padding(horizontal = 5.dp, vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(appName.take(2), color = t.sealColor, fontFamily = FontSans, fontSize = 10.sp,
                    letterSpacing = 1.sp)
                Text(sealCN(todayStr()), color = t.sealColor.copy(alpha = 0.9f), fontFamily = FontSans,
                    fontSize = 5.5.sp)
            }
        }
    }
}

@Composable
private fun ReplySheet(text: String, value: String, onChange: (String) -> Unit, onCancel: () -> Unit, onSave: () -> Unit) {
    val t = appTokens()
    Box(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(onClick = onCancel)) {
        Column(
            Modifier
                .align(Alignment.Center)
                .fillMaxWidth(0.86f)
                .background(t.cardSolidColor, RoundedCornerShape(t.radiusCard.dp))
                .padding(18.dp)
        ) {
            Text("回一句话", color = t.inkStrongColor, fontFamily = FontSerif, fontSize = 17.sp, letterSpacing = 2.sp)
            Text(text, color = t.inkSoftColor, fontFamily = FontSans, fontSize = 12.sp,
                lineHeight = 22.sp, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            com.juxia.app.ui.PaperInput(value = value, onChange = onChange, placeholder = "不用写完整，回一句话就好")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                QuietButton("取消", onCancel)
                Spacer(Modifier.padding(4.dp))
                PrimaryButton("回一句话") { onSave() }
            }
        }
    }
}

@Composable
private fun ActionPrimary(label: String, t: com.juxia.app.ui.theme.Tokens, action: () -> Unit) {
    Text(
        label,
        color = t.bgColor,
        fontFamily = FontSans,
        fontSize = 13.5.sp,
        letterSpacing = 1.5.sp,
        modifier = Modifier
            .background(t.inkColor, RoundedCornerShape(999.dp))
            .clickable(onClick = action)
            .padding(horizontal = 26.dp, vertical = 12.dp)
    )
}

@Composable
private fun ActionQuiet(label: String, t: com.juxia.app.ui.theme.Tokens, action: () -> Unit) {
    Text(
        label,
        color = t.inkSoftColor,
        fontFamily = FontSans,
        fontSize = 12.5.sp,
        letterSpacing = 1.2.sp,
        modifier = Modifier
            .clickable(onClick = action)
            .padding(horizontal = 12.dp, vertical = 10.dp)
    )
}
