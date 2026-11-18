package com.juxia.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.state.UiState
import dev.chrisbanes.haze.hazeEffect
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import com.juxia.app.ui.theme.Tokens
import com.juxia.app.ui.theme.argb
import com.juxia.app.ui.theme.getTokens

// 句栖 · 页面公共件

// 经典皮卡片毛玻璃：BackgroundStack 提供 HazeState（背景层作 source），Card 消费做 effect。
// plain 皮肤传 null → 不模糊（朴素皮本就是素纸）。
val LocalHazeState = androidx.compose.runtime.compositionLocalOf<dev.chrisbanes.haze.HazeState?> { null }
// 字号随 settings.fontScale × systemFontScale 缩放（fontScaleFollow 时）。
// 字号随 settings.fontScale × systemFontScale 缩放（fontScaleFollow 时）。

@Composable
fun appTokens(): Tokens = getTokens(
    UiState.skin.collectAsState().value,
    UiState.dark.collectAsState().value
)

@Composable
fun fontScale(): Double {
    val st = com.juxia.app.data.Store.instance
    // Compose sp 已应用系统字号；这里不再叠加 systemFontScale。
    UiState.dataVersion.collectAsState() // settings.fontScale 变更实时生效
    return st.data.settings.fontScale
}

@Composable
fun scaledSp(base: Number): TextUnit {
    // JuxiaRoot 已通过 LocalDensity 全局应用 fontScale；这里只保留基准字号。
    UiState.dataVersion.collectAsState()
    return base.toDouble().sp
}

@Composable
fun Label(text: String) {
    val t = appTokens()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 26.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = text,
            color = t.inkSoftColor,
            fontSize = scaledSp(10.5),
            letterSpacing = 3.sp,
            fontFamily = FontSans
        )
        Spacer(Modifier.padding(6.dp))
        Box(
            Modifier
                .weight(1f)
                .height(1.dp)
                .background(t.lineColor)
        )
    }
}

@Composable
fun Card(
    modifier: Modifier = Modifier,
    dashed: Boolean = false,
    padded: Dp = 20.dp,
    content: @Composable () -> Unit
) {
    val t = appTokens()
    val dark by UiState.dark.collectAsState()
    val shape = RoundedCornerShape(t.radiusCard.dp)
    val haze = LocalHazeState.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = if (t.plain) 0.dp else 24.dp,
                shape = shape,
                ambientColor = argb(t.shadowColor),
                spotColor = argb(t.shadowLift)
            )
            .clip(shape)
            .background(t.cardColor)
            .border(
                width = 1.dp,
                color = t.lineColor,
                shape = shape
            )
            .then(
                // 对齐鸿蒙 47 处卡片：backdropBlur(this.dark ? 0 : 10) —— 暗色不做毛玻璃
                if (t.blurCard > 0 && haze != null && !dark) {
                    // HazeStyle 1.5.4 主构造（源码验证）：tints: List<HazeTint>，tint 是次构造的 HazeTint? 参数，不能传 Color
                    Modifier.hazeEffect(haze, style = dev.chrisbanes.haze.HazeStyle(
                        backgroundColor = t.cardSolidColor,
                        tints = emptyList(),
                        blurRadius = t.blurCard.dp,
                        noiseFactor = 0f
                    ))
                } else Modifier
            )
            .clip(shape) // effect 之后再次裁形，圆角不被模糊半径吃掉
            .padding(padded),
        content = { content() }
    )
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit) = PrimaryButton(text, Modifier, onClick)

@Composable
fun PrimaryButton(text: String, modifier: Modifier, onClick: () -> Unit) {
    val t = appTokens()
    Text(
        text = text,
        fontSize = scaledSp(14),
        color = t.bgColor,
        fontFamily = FontSans,
        letterSpacing = 1.4.sp,
        modifier = modifier
            .clip(RoundedCornerShape(t.radiusBtn.dp))
            .background(t.inkColor)
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 12.dp)
    )
}

@Composable
fun GhostButton(text: String, onClick: () -> Unit) = GhostButton(text, Modifier, onClick)

@Composable
fun GhostButton(text: String, modifier: Modifier, onClick: () -> Unit) {
    val t = appTokens()
    Text(
        text = text,
        fontSize = scaledSp(13),
        color = t.inkColor,
        fontFamily = FontSans,
        letterSpacing = 1.2.sp,
        modifier = modifier
            .clip(RoundedCornerShape(t.radiusBtn.dp))
            .background(t.cardColor)
            .border(1.dp, t.lineColor, RoundedCornerShape(t.radiusBtn.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 11.dp)
    )
}

@Composable
fun QuietButton(text: String, onClick: () -> Unit) {
    val t = appTokens()
    Text(
        text = text,
        fontSize = scaledSp(12.5),
        color = t.inkSoftColor,
        fontFamily = FontSans,
        letterSpacing = 1.sp,
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 10.dp)
    )
}

@Composable
fun Blank() {
    Spacer(Modifier.height(120.dp))
}

/** 注脚行：左侧印章色竖线（对应 .note-line） */
@Composable
fun NoteLine(text: String) {
    val t = appTokens()
    Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Box(
            Modifier
                .padding(top = 3.dp)
                .width2dp()
                .height2(14.dp)
                .background(t.sealColor)
        )
        Text(
            text = text,
            color = t.inkColor,
            fontFamily = com.juxia.app.ui.theme.FontSans,
            fontSize = scaledSp(13),
            lineHeight = scaledSp(24),
            modifier = Modifier.padding(start = 12.dp, top = 3.dp, bottom = 3.dp)
        )
    }
}

/** 页面底部留白 = 安全区 + 悬浮导航高度 */
@Composable
fun padBottom(): Dp {
    val safe by UiState.safeBottom.collectAsState()
    return 120.dp + safe.dp
}


/** 底部单（对应 ArkUI bindSheet：下滑关闭、圆角、纯色底） */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AppSheet(onClose: () -> Unit, content: @Composable () -> Unit) {
    val dark by UiState.dark.collectAsState()
    val skin by UiState.skin.collectAsState()
    val t = appTokens()
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onClose,
        containerColor = t.cardSolidColor,
        scrimColor = Color(0x66000000),
        tonalElevation = 0.dp,
        dragHandle = null,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(
            Modifier
                .padding(horizontal = 20.dp)
                .padding(top = 6.dp, bottom = 20.dp)
        ) {
            content()
        }
    }
}

/** 纸槽输入（对应 .paper-input：内凹、衬线、聚焦描边） */
@Composable
fun PaperInput(
    value: String, onChange: (String) -> Unit, placeholder: String,
    multiLine: Boolean = true,
    password: Boolean = false
) {
    val t = appTokens()
    val dark by UiState.dark.collectAsState()
    androidx.compose.material3.OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth(),
        placeholder = {
            Text(placeholder, color = t.inkSoftColor, fontFamily = FontSerif, fontSize = scaledSp(14.5))
        },
        textStyle = TextStyle(
            color = t.inkColor,
            fontFamily = FontSerif,
            fontSize = scaledSp(15),
            lineHeight = scaledSp(26)
        ),
        shape = RoundedCornerShape(t.radiusInput.dp),
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            focusedContainerColor = t.inputBgColor,
            unfocusedContainerColor = t.inputBgColor,
            focusedBorderColor = t.inkSoftColor,
            unfocusedBorderColor = t.lineColor,
            cursorColor = t.sealColor
        ),
        minLines = if (multiLine) 2 else 1,
        visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else KeyboardType.Text)
    )
}


private fun Modifier.width2dp(): Modifier = this.width(2.dp)
private fun Modifier.height2(h: Dp): Modifier = this.height(h)

@Composable
fun OutlineButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) =
    GhostButton(text, modifier, onClick)
