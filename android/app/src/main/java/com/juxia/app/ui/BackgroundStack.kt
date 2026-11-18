package com.juxia.app.ui

import android.annotation.SuppressLint
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.juxia.app.state.UiState
import dev.chrisbanes.haze.hazeSource
import com.juxia.app.ui.theme.argb
import java.io.File

// 句栖 · 十层背景合成栈（翻译自 Index.ets 的 build()）
// 层序：底色 → 渐变 → 照片 → 提亮/压暗 → 遮罩 → 光晕 → dither → 纸纹 → 内容
@SuppressLint("ProduceStateDoesNotAssignValue")
@Composable
fun BackgroundStack(content: @Composable () -> Unit) {
    val hazeState = remember { dev.chrisbanes.haze.HazeState() }
    val dark by UiState.dark.collectAsState()
    val skin by UiState.skin.collectAsState()
    val t = com.juxia.app.ui.theme.getTokens(skin, dark)
    val brightness by UiState.bgBrightness.collectAsState()
    val blurV by UiState.bgBlur.collectAsState()
    val scrim by UiState.bgScrim.collectAsState()
    val glowV by UiState.bgGlow.collectAsState()
    val grainV by UiState.bgGrain.collectAsState()
    val ditherV by UiState.bgDither.collectAsState()
    val bgRev by UiState.bgRev.collectAsState()
    val ctx = LocalContext.current

    val style = UiState.bgStyleFor(skin, dark)
    val hasBg = style.path.isNotEmpty()
    val b = brightness
    val glowOpacity = glowV / 100f

    Box(Modifier.fillMaxSize()) {
        // haze source：背景九层包在同一个容器里，供卡片模糊采样
        Box(Modifier.fillMaxSize().hazeSource(hazeState)) {
        // 1) 最底层兜底（API 26 不设窗口底色，用页面底色覆盖系统默认色）
        Box(Modifier.fillMaxSize().background(if (dark) Color(0xFF14110B) else Color(0xFFF6F0E3)))

        // 2) 皮肤渐变
        if (skin != "plain") {
            val top = if (dark) "#201c15" else "#f3eddc"
            val bottom = if (dark) "#14110b" else "#e9e0cb"
            val stops = listOf(
                0.0f to argb(top),
                0.42f to t.bgColor,
                1.0f to argb(bottom)
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Brush.verticalGradient(*stops.toTypedArray()))
                    .then(if (!hasBg && blurV > 0) Modifier.blur((blurV * 0.5f).dp) else Modifier)
            )
        } else {
            if (dark) {
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(0f to argb("#211e19"), 0.55f to argb("#1b1a17"), 1f to argb("#171614"))
                    )
                )
            } else {
                Box(Modifier.fillMaxSize().background(t.bgColor))
            }
        }

        // 3) 照片层
        if (hasBg) {
            val bitmap by produceState<android.graphics.Bitmap?>(initialValue = null, bgRev, style.path) {
                value = try {
                    decodeSampled(style.path)
                } catch (e: Exception) {
                    null
                }
            }
            val bmp = bitmap
            if (bmp != null) {
                val bm = minOf(1.0, b).toFloat()
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxSize()
                        .then(if (blurV > 0) Modifier.blur((blurV * 0.5f).dp) else Modifier),
                    contentScale = ContentScale.Crop,
                    colorFilter = ColorFilter.colorMatrix(
                        ColorMatrix().apply { setToScale(bm, bm, bm, 1f) }
                    )
                )
            }
        }

        // 4) 提亮（亮度 > 1 用白色叠加层实现，与鸿蒙版一致）
        if (b > 1.0) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.White.copy(alpha = ((b - 1.0) * 0.55).toFloat()))
            )
        }

        // 5) 压暗
        if (b < 1.0) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = ((1.0 - b) * 0.85).toFloat()))
            )
        }

        // 6) 遮罩
        if (scrim > 0.0) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background((if (dark) Color.Black else Color(0xFFF6F0E3)).copy(alpha = scrim.toFloat()))
            )
        }

        // 7) 光晕（静态，opacity = bgGlow/100）
        if (glowOpacity > 0f) {
            if (skin != "plain") {
                val w = ctx.resources.displayMetrics.widthPixels.toFloat()
                val h = ctx.resources.displayMetrics.heightPixels.toFloat()
                Box(Modifier.fillMaxSize().alpha(glowOpacity).background(
                    Brush.radialGradient(
                        listOf(argb(if (dark) "#571e1834" else "#ccfff3c4"), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(w * 0.74f, h * 0.04f),
                        radius = w * 0.78f
                    )
                ))
                Box(Modifier.fillMaxSize().alpha(glowOpacity).background(
                    Brush.radialGradient(
                        listOf(argb(if (dark) "#5c36422e" else "#8ce4e9c5"), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(w * 0.08f, h * 0.92f),
                        radius = w * 0.70f
                    )
                ))
                Box(Modifier.fillMaxSize().alpha(glowOpacity).background(
                    Brush.radialGradient(
                        listOf(argb(if (dark) "#5754402e" else "#80d5c2ad"), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(w * 0.92f, h * 0.84f),
                        radius = w * 0.68f
                    )
                ))
            } else if (dark) {
                val w = ctx.resources.displayMetrics.widthPixels.toFloat()
                val h = ctx.resources.displayMetrics.heightPixels.toFloat()
                Box(Modifier.fillMaxSize().alpha(glowOpacity).background(
                    Brush.radialGradient(
                        listOf(argb("#22c98a5e"), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(w * 0.82f, h * 0.00f),
                        radius = w * 0.80f
                    )
                ))
                Box(Modifier.fillMaxSize().alpha(glowOpacity).background(
                    Brush.radialGradient(
                        listOf(argb("#107a9bb0"), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(w * 0.12f, h * 0.92f),
                        radius = w * 0.70f
                    )
                ))
            }
        }

        // 8) dither（仅深色）
        if (dark && ditherV > 0) {
            TextureTile(asset = "textures/dither.png", tilePx = 256, alpha = ditherV / 100f)
        }

        // 9) 纸纹
        val grainOpacity = run {
            val base = if (skin == "plain") 0.22f else 0.5f
            val v = grainV
            if (v <= 100) base * v / 100f else base * v / 400f
        }
        if (grainOpacity > 0f) {
            val visible = grainV > 100
            val asset = when {
                skin == "plain" && dark -> if (visible) "textures/grain_night_visible.png" else "textures/grain_night.png"
                skin == "plain" -> if (visible) "textures/grain_visible.png" else "textures/grain.png"
                dark -> if (visible) "textures/grain_night_visible.png" else "textures/grain_night.png"
                else -> if (visible) "textures/grain_visible.png" else "textures/grain.png"
            }
            // 鸿蒙：深色 NoRepeat 100%，浅色 tile 140；朴素皮浅色也平铺 140。
            val stretch = dark
            val tilePx = if (stretch) 0 else 140
            TextureTile(asset = asset, tilePx = tilePx, alpha = grainOpacity, stretch = stretch)
        }

        } // haze source 结束
        // 10) 内容（卡片经 LocalHazeState 采样上面的背景层）
        androidx.compose.runtime.CompositionLocalProvider(
            com.juxia.app.ui.LocalHazeState provides hazeState
        ) {
            content()
        }
    }
}

/** 后台解码 + 降采样（P1-10：大图防卡顿/OOM，上限 2048px） */
private suspend fun decodeSampled(path: String): android.graphics.Bitmap? =
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return@withContext null
        var sample = 1
        val maxDim = 2048
        // 修正：保证结果 <= maxDim，而非"减半后仍 >= maxDim"
        while (maxOf(opts.outWidth, opts.outHeight) / sample > maxDim) sample *= 2
        BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

/** 纹理平铺：tilePx=0 表示拉伸铺满 */
@SuppressLint("ProduceStateDoesNotAssignValue")
@Composable
private fun TextureTile(asset: String, tilePx: Int, alpha: Float, stretch: Boolean = false) {
    val ctx = LocalContext.current
    val bmp by produceState<android.graphics.Bitmap?>(initialValue = null, asset) {
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                ctx.assets.open(asset).use { BitmapFactory.decodeStream(it) }
            } catch (e: Exception) {
                null
            }
        }
    }
    val src = bmp ?: return
    if (stretch) {
        Image(
            bitmap = src.asImageBitmap(), contentDescription = null,
            modifier = Modifier.fillMaxSize().alpha(alpha),
            contentScale = ContentScale.FillBounds
        )
    } else {
        // 平铺：用画布绘制多份
        val w = if (tilePx > 0) tilePx else src.width
        val h = if (tilePx > 0) tilePx else src.height
        // P2：缩放结果记忆化，防 Canvas 每帧 createScaledBitmap 抖动
        val scaled = remember(src, w, h) {
            android.graphics.Bitmap.createScaledBitmap(src, w, h, true).asImageBitmap()
        }
        androidx.compose.foundation.Canvas(Modifier.fillMaxSize().alpha(alpha)) {
            val cols = (size.width / w).toInt() + 1
            val rows = (size.height / h).toInt() + 1
            for (i in 0..cols) for (j in 0..rows) {
                drawImage(scaled, topLeft = androidx.compose.ui.geometry.Offset(i * w.toFloat(), j * h.toFloat()))
            }
        }
    }
}
