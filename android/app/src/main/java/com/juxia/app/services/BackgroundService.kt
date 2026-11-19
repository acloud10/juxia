package com.juxia.app.services

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume

// 句栖 · 自定义背景（翻译自 BackgroundService.ets）
// pick 走 Photo Picker（API 33+ ACTION_PICK_IMAGES / 回退 GET_CONTENT），copyToCache 双保险复制，
// saveBitmap 以 JPEG q85 写 tmp+rename。
object BackgroundService {
    class PickImageFailed : Exception("PICK_IMAGE_FAILED")
    class CopyImageFailed : Exception("COPY_IMAGE_FAILED")
    class SaveImageFailed : Exception("SAVE_IMAGE_FAILED")

    /** 挂起式选图：在当前 Activity 上注册 Photo Picker 并等待结果，返回 content Uri 字符串 */
    suspend fun pick(activity: ComponentActivity): String = suspendCancellableCoroutine { cont ->
        val key = "juxia_bg_pick_" + System.currentTimeMillis()
        val contract = ActivityResultContracts.PickVisualMedia()
        var launcher: ActivityResultLauncher<PickVisualMediaRequest>? = null
        launcher = activity.activityResultRegistry.register(key, contract) { uri ->
            launcher?.unregister() // P2：回调后注销，防 Registry 泄漏
            cont.resume(uri?.toString() ?: "")
        }
        cont.invokeOnCancellation { launcher?.unregister() }
        try {
            launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        } catch (e: Exception) {
            launcher.unregister()
            if (cont.isActive) cont.resumeWith(Result.failure(PickImageFailed()))
        }
    }

    fun cachePath(ctx: Context, stamp: Long): String =
        File(ctx.cacheDir, "bg_pick_$stamp.img").absolutePath

    fun imagePath(ctx: Context, key: String): String =
        File(ctx.filesDir, "backgrounds/$key.jpg").absolutePath

    /** content:// Uri → 缓存文件；复制双保险 + 空文件兜底，失败抛 COPY_IMAGE_FAILED */
    fun copyToCache(ctx: Context, uri: String, dest: String) {
        var copied = false
        try {
            ctx.contentResolver.openInputStream(Uri.parse(uri))?.use { input ->
                File(dest).outputStream().buffered(64 * 1024).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                    }
                }
            }
            copied = File(dest).length() > 0
        } catch (e: Exception) {
            copied = false
        }
        if (!copied) throw CopyImageFailed()
    }

    /** Bitmap → JPEG q85，写临时文件后 rename，返回最终路径 */
    suspend fun saveBitmap(ctx: Context, bitmap: Bitmap, key: String): String =
        withContext(Dispatchers.IO) {
            val dir = File(ctx.filesDir, "backgrounds")
            try { dir.mkdirs() } catch (_: Exception) {}
            val dest = File(dir, key + "_" + System.currentTimeMillis() + ".jpg")
            val tmp = File(dest.absolutePath + ".tmp")
            try {
                tmp.outputStream().buffered().use { out ->
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)) throw SaveImageFailed()
                }
                if (!tmp.renameTo(dest)) throw SaveImageFailed()
                dest.absolutePath
            } catch (e: SaveImageFailed) {
                throw e
            } catch (e: Exception) {
                Log.e("juxia", "bg save fail" + "：" + (e.message ?: ""))
                throw SaveImageFailed()
            } finally {
                try { if (tmp.exists()) tmp.delete() } catch (_: Exception) {}
            }
        }

    /** 只保留 keep 列表里的 .jpg，清孤儿 */
    fun cleanup(ctx: Context, keep: List<String>) {
        try {
            val dir = File(ctx.filesDir, "backgrounds")
            dir.listFiles()?.forEach { f ->
                if (!f.name.endsWith(".jpg")) return@forEach
                if (!keep.contains(f.absolutePath)) {
                    try { f.delete() } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }

    fun remove(ctx: Context, path: String) {
        if (path.isEmpty()) return
        try { File(path).delete() } catch (_: Exception) {}
    }
}
