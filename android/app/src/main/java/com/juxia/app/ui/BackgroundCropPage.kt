package com.juxia.app.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.services.BackgroundService
import com.juxia.app.state.UiState
import com.juxia.app.ui.theme.FontSans
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.Arrangement

// 句栖 · 背景裁剪页（翻译自 BackgroundCropPage.ets：全屏预览，可见区域即最终背景）
// 单指拖动 + 双指捏合（1x–4x），平移钳制在"恰好铺满屏幕"范围内；保存走裁剪→缩放→JPEG。
@Composable
fun BackgroundCropPage(srcPath: String, cropKey: String, onClose: () -> Unit) {
    val t = appTokens()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    var zoom by remember { mutableFloatStateOf(1f) }
    var tx by remember { mutableFloatStateOf(0f) }   // px
    var ty by remember { mutableFloatStateOf(0f) }
    var saving by remember { mutableStateOf(false) }

    var bmp by remember(srcPath) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(srcPath) {
        bmp = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            runCatching {
                val dm = ctx.resources.displayMetrics
                val maxW = dm.widthPixels * 2
                val maxH = dm.heightPixels * 2
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(srcPath, bounds)
                var sample = 1
                while (bounds.outWidth / sample > maxW || bounds.outHeight / sample > maxH) sample *= 2
                val opts = BitmapFactory.Options().apply { inSampleSize = sample }
                BitmapFactory.decodeFile(srcPath, opts)
            }.getOrNull()
        }
    }
    val bmpNow = bmp
    if (bmpNow == null) {
        Box(Modifier.fillMaxSize().background(t.bgColor), contentAlignment = Alignment.Center) {
            Text("无法读取图片", color = t.inkColor, fontFamily = FontSans, fontSize = 14.sp)
        }
        return
    }
    val imgW = bmpNow.width.toFloat()
    val imgH = bmpNow.height.toFloat()
    val vw = with(density) { ctx.resources.displayMetrics.widthPixels.toFloat() }
    val vh = with(density) { ctx.resources.displayMetrics.heightPixels.toFloat() }
    val base = max(vw / imgW, vh / imgH)

    fun clamp() {
        val sw = imgW * base * zoom
        val sh = imgH * base * zoom
        val mx = max(0f, (sw - vw) / 2f)
        val my = max(0f, (sh - vh) / 2f)
        tx = max(-mx, min(mx, tx))
        ty = max(-my, min(my, ty))
    }

    fun confirm() {
        if (saving) return
        saving = true
        scope.launch {
            try {
                val scale = base * zoom
                val cw = min(imgW, vw / scale)
                val ch = min(imgH, vh / scale)
                val cx = imgW / 2f - tx / scale
                val cy = imgH / 2f - ty / scale
                val left = max(0f, min(imgW - cw, cx - cw / 2f)).roundToInt()
                val top = max(0f, min(imgH - ch, cy - ch / 2f)).roundToInt()
                val w = cw.roundToInt().coerceAtLeast(1)
                val h = ch.roundToInt().coerceAtLeast(1)
                val out = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    val cropped = Bitmap.createBitmap(bmpNow, left, top, w, h)
                    Bitmap.createScaledBitmap(cropped, vw.roundToInt(), vh.roundToInt(), true)
                }
                val path = BackgroundService.saveBitmap(ctx, out, cropKey)
                Store.instance.setBackgroundPath(cropKey, path)
                Store.instance.flush()
                try { java.io.File(srcPath).delete() } catch (_: Exception) {} // 裁剪缓存 .img 用完即删
                val b = Store.instance.data.settings.background
                val keep = listOf(b.light.path, b.dark.path, b.lightClassic.path,
                        b.lightPlain.path, b.darkClassic.path, b.darkPlain.path)
                    .filter { it.isNotEmpty() }
                BackgroundService.cleanup(ctx, keep)
                UiState.applyBackground()
                UiState.bumpBgSaved()
                onClose()
            } catch (e: Exception) {
                // 裁剪失败兜底：全图直存（对应鸿蒙版 fallback full image）
                try {
                    val path = BackgroundService.saveBitmap(ctx, bmpNow, cropKey)
                    Store.instance.setBackgroundPath(cropKey, path)
                    Store.instance.flush()
                    UiState.applyBackground()
                    UiState.bumpBgSaved()
                    onClose()
                } catch (e2: Exception) {
                    saving = false
                    UiState.showToast("保存背景失败")
                }
            }
        }
    }

    Box(Modifier.fillMaxSize().background(t.bgColor)) {
        // 图片层（铺满 + 平移 + 缩放）
        Box(
            Modifier
                .fillMaxSize()
                .clip(androidx.compose.ui.graphics.RectangleShape)
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoomChange, _ ->
                        zoom = max(1f, min(4f, zoom * zoomChange))
                        tx += pan.x
                        ty += pan.y
                        clamp()
                    }
                }
        ) {
            Image(
                bitmap = bmpNow.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .width(with(density) { (imgW * base * zoom).toDp() })
                    .height(with(density) { (imgH * base * zoom).toDp() })
                    .offset { IntOffset(tx.roundToInt(), ty.roundToInt()) }
                    .align(Alignment.Center)
            )
        }

        Text(
            "背景预览",
            color = t.inkColor,
            fontFamily = FontSans,
            fontSize = 13.sp,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 120.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(t.cardColor)
                .padding(horizontal = 14.dp, vertical = 8.dp)
        )

        if (saving) {
            Column(
                Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0x66000000)),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("正在应用…", color = t.inkColor, fontSize = 13.sp, fontFamily = FontSans)
            }
        }

        Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth(0.88f)
                .padding(bottom = 42.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "取消",
                color = t.inkColor, fontFamily = FontSans, fontSize = 14.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(t.cardColor)
                    .clickable(onClick = onClose)
                    .padding(top = 12.dp)
            )
            Text(
                if (saving) "保存中…" else "使用这张",
                color = t.bgColor, fontFamily = FontSans, fontSize = 14.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(t.inkColor)
                    .clickable(onClick = ::confirm)
                    .padding(top = 12.dp)
            )
        }
    }
}
