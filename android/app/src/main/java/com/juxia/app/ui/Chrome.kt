package com.juxia.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import com.juxia.app.ui.theme.argb
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// 句栖 · 界面骨架（翻译自 Chrome.ets：TopBar 印章 / TabIcon / MoodIcon 手绘 Path）
// 2026-11-16 修正：图标路径更正为 ArkTS 原版（此前误用了 HTML 版 SVG，已向用户声明）。

// ---------- SVG 路径解析（仅绝对指令 M/L/Q/A/Z，与原版素材口径一致） ----------

object SvgPath {
    private val tokenRe = Regex("[MLAQZ]|-?\\d+(\\.\\d+)?")

    fun parse(cmd: String, scale: Double): Path {
        val tokens = tokenRe.findAll(cmd).map { it.value }.toList()
        val path = Path()
        var i = 0
        var cx = 0.0
        var cy = 0.0
        fun num(k: Int): Double = tokens[k].toDouble() * scale
        while (i < tokens.size) {
            when (tokens[i]) {
                "M" -> { cx = num(i + 1); cy = num(i + 2); path.moveTo(cx.toFloat(), cy.toFloat()); i += 3 }
                "L" -> { cx = num(i + 1); cy = num(i + 2); path.lineTo(cx.toFloat(), cy.toFloat()); i += 3 }
                "Q" -> {
                    val x1 = num(i + 1); val y1 = num(i + 2)
                    cx = num(i + 3); cy = num(i + 4)
                    path.quadraticBezierTo(x1.toFloat(), y1.toFloat(), cx.toFloat(), cy.toFloat())
                    i += 5
                }
                "A" -> {
                    val rx = num(i + 1); val ry = num(i + 2)
                    val phi = tokens[i + 3].toDouble()
                    val large = tokens[i + 4] != "0"
                    val sweep = tokens[i + 5] != "0"
                    val x2 = num(i + 6); val y2 = num(i + 7)
                    arcTo(path, rx, ry, phi, large, sweep, x2, y2, cx, cy)
                    cx = x2; cy = y2
                    i += 8
                }
                "Z" -> { path.close(); i += 1 }
                else -> i += 1
            }
        }
        return path
    }

    private fun arcTo(path: Path, rx0: Double, ry0: Double, phiDeg: Double,
                      largeArc: Boolean, sweep: Boolean,
                      x2: Double, y2: Double, x1: Double, y1: Double) {
        var rx = abs(rx0); var ry = abs(ry0)
        if (rx < 1e-6 || ry < 1e-6) { path.lineTo(x2.toFloat(), y2.toFloat()); return }
        val phi = Math.toRadians(phiDeg)
        val cosP = cos(phi); val sinP = sin(phi)
        val dx = (x1 - x2) / 2.0; val dy = (y1 - y2) / 2.0
        val x1p = cosP * dx + sinP * dy
        val y1p = -sinP * dx + cosP * dy
        val lam = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if (lam > 1.0) { val sc = sqrt(lam); rx *= sc; ry *= sc }
        val num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        val den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(maxOf(0.0, num / den))
        if (largeArc == sweep) coef = -coef
        val cxp = coef * rx * y1p / ry
        val cyp = -coef * ry * x1p / rx
        val cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2.0
        val cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2.0
        fun angle(ux: Double, uy: Double, vx: Double, vy: Double): Double {
            val dot = ux * vx + uy * vy
            var a = Math.toDegrees(atan2(ux * vy - uy * vx, dot))
            if (a < 0) a += 360.0
            return a
        }
        val theta1 = angle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        val delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        val sweepDeg = if (sweep) delta else -delta
        path.arcTo(
            Rect((cx - rx).toFloat(), (cy - ry).toFloat(), (cx + rx).toFloat(), (cy + ry).toFloat()),
            theta1.toFloat(), sweepDeg.toFloat(), forceMoveTo = false
        )
    }
}

@Composable
fun SvgIcon(cmd: String, grid: Int, sizeDp: Dp, color: Color, strokeDp: Float = 1.3f) {
    Canvas(Modifier.size(sizeDp)) {
        val scale = size.width / grid
        val path = SvgPath.parse(cmd, scale.toDouble())
        drawPath(path, color = color, style = Stroke(width = strokeDp.dp.toPx(), miter = 1f))
    }
}

// ---------- TopBar（印章竖排双字 + 33 框 + 字标 + 日期行） ----------

@Composable
fun TopBar() {
    val appName by UiState.appName.collectAsState()
    val dayCount by UiState.dayCount.collectAsState()
    val showDays by UiState.showDays.collectAsState()
    val showSeal by UiState.showSeal.collectAsState()
    val dark by UiState.dark.collectAsState()
    val skin by UiState.skin.collectAsState()
    val t = com.juxia.app.ui.theme.getTokens(skin, dark)
    val cal = java.util.Calendar.getInstance()
    val dateText = "${cal.get(java.util.Calendar.MONTH) + 1}月${cal.get(java.util.Calendar.DAY_OF_MONTH)}日 · 星期${
        com.juxia.app.model.weekdayCN(java.util.Date())
    }"

    Row(
        // 对齐鸿蒙 Chrome.ets：left/right 20、top 26、bottom 18
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 26.dp, bottom = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 对齐鸿蒙：朴素皮不显示印章
        if (skin != "plain" && showSeal) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .rotate(-1.2f)
                    .shadow(7.dp, RoundedCornerShape(10.dp))
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        Brush.linearGradient(
                            0f to argb("#c45155"),
                            0.58f to argb("#b8434a"),
                            1f to argb("#a83b42"),
                            start = Offset(0f, 0f),
                            end = Offset(34f, 20f)
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // getOrNull：单字应用名不崩（JS slice 对越界宽容，Kotlin slice 会抛）
                    Text(appName.getOrNull(0)?.toString() ?: "", color = t.sealInkColor, fontFamily = FontSerif,
                        fontSize = 15.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium)
                    Text(appName.getOrNull(1)?.toString() ?: "", color = t.sealInkColor, fontFamily = FontSerif,
                        fontSize = 15.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium)
                }
                Box(
                    Modifier
                        .size(33.dp)
                        .border(1.2.dp, argb("#8cfdf6ea"), RoundedCornerShape(6.5.dp))
                )
            }
            Spacer(Modifier.width(12.dp))
        }
        Text(
            text = appName,
            color = t.inkStrongColor,
            fontFamily = FontSerif,
            fontSize = if (skin == "plain") 22.sp else 24.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = if (skin == "plain") 10.sp else 7.sp
        )
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = dateText,
                color = t.inkSoftColor,
                fontFamily = FontSans,
                fontSize = 10.5.sp,
                letterSpacing = 2.4.sp
            )
            if (showDays) {
                Text(
                    text = "相伴第 $dayCount 天",
                    color = t.inkSoftColor,
                    fontFamily = FontSans,
                    fontSize = 10.5.sp,
                    letterSpacing = 2.4.sp
                )
            }
        }
    }
}

// ---------- TabIcon（ArkTS 原版：index 0-4，统一 24 网格 19vp） ----------

object TabIcons {
    private const val TODAY = "M 16.2 12 A 4.2 4.2 0 1 1 7.8 12 A 4.2 4.2 0 1 1 16.2 12 Z " +
        "M 12 3 L 12 5.4 M 12 18.6 L 12 21 M 3 12 L 5.4 12 M 18.6 12 L 21 12 " +
        "M 5.8 5.8 L 7.5 7.5 M 16.5 16.5 L 18.2 18.2 M 18.2 5.8 L 16.5 7.5 M 7.5 16.5 L 5.8 18.2"
    private const val MINE = "M 5 5.5 L 19 5.5 M 5 12 L 19 12 M 5 18.5 L 14 18.5"
    private const val LIB = "M 4.5 19 L 4.5 6.8 A 1.8 1.8 0 0 1 6.3 5 L 19.5 5 L 19.5 17.6 " +
        "L 6.3 17.6 A 1.8 1.8 0 0 0 4.5 19 Z M 4.5 19 A 1.8 1.8 0 0 0 6.3 20.6 L 19.5 20.6"
    private const val ARCHIVE = "M 4 8.5 L 20 8.5 L 20 18.5 A 1.5 1.5 0 0 1 18.5 20 L 5.5 20 " +
        "A 1.5 1.5 0 0 1 4 18.5 Z M 3 4.5 L 21 4.5 L 21 8.5 L 3 8.5 Z M 10 12 L 14 12"
    private const val SETTINGS = "M 4 7 L 14 7 M 18 7 L 20 7 M 4 17 L 8 17 M 12 17 L 20 17 " +
        "M 18.2 7 A 2.2 2.2 0 1 1 13.8 7 A 2.2 2.2 0 1 1 18.2 7 Z " +
        "M 12.2 17 A 2.2 2.2 0 1 1 7.8 17 A 2.2 2.2 0 1 1 12.2 17 Z"

    @Composable
    fun TabIcon(name: String, grid: Int, sizeDp: Dp, color: Color) {
        val cmd = when (name) {
            "today" -> TODAY
            "mine" -> MINE
            "library" -> LIB
            "archive" -> ARCHIVE
            else -> SETTINGS
        }
        SvgIcon(cmd, 24, sizeDp, color, 1.3f)
    }
}

// ---------- MoodIcon（ArkTS 原版：经典 22vp/24 网格，朴素 26vp/48 网格粗线） ----------

object MoodIcons {
    private const val GOOD_PLAIN = "M 16 24 A 8 8 0 1 1 32 24 A 8 8 0 1 1 16 24 Z " +
        "M 37 24 L 42 24 M 33.2 14.8 L 36.7 11.3 M 24 11 L 24 6 M 14.8 14.8 L 11.3 11.3 " +
        "M 11 24 L 6 24 M 14.8 33.2 L 11.3 36.7 M 24 37 L 24 42 M 33.2 33.2 L 36.7 36.7"
    private const val BAD_PLAIN = "M 9 15 Q 13 9 21 10 Q 24 3 33 6 Q 41 8 39 15 " +
        "M 15 24 L 12 32 M 25 24 L 22 32 M 35 24 L 32 32"
    private const val GOOD_CLASSIC = "M 8 13 A 4 4 0 1 1 16 13 A 4 4 0 1 1 8 13 Z " +
        "M 12 4 L 12 6.5 M 5 13 L 2.5 13 M 21.5 13 L 19 13 " +
        "M 6.3 7.3 L 4.5 5.5 M 17.7 7.3 L 19.5 5.5 M 4 20 L 20 20"
    private const val BAD_CLASSIC = "M 18 10 A 6 6 0 0 0 6.5 8.5 A 4.5 4.5 0 0 0 7 17.5 L 18 17.5 " +
        "A 3.5 3.5 0 0 0 18 10 Z M 8 20 L 9 22 M 12 20 L 13 22 M 16 20 L 17 22"

    @Composable
    fun MoodIcon(good: Boolean, plain: Boolean, sizeDp: Dp, color: Color) {
        val cmd = when {
            plain && good -> GOOD_PLAIN
            plain && !good -> BAD_PLAIN
            !plain && good -> GOOD_CLASSIC
            else -> BAD_CLASSIC
        }
        SvgIcon(cmd, if (plain) 48 else 24, sizeDp, color, if (plain) 1.6f else 1.3f)
    }
}
