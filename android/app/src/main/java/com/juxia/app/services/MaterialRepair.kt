package com.juxia.app.services

import android.content.Context
import android.util.Log
import com.juxia.app.data.Store
import java.io.File

// 句栖 · 材料索引自愈（翻译自 MaterialRepair.ets：启动时只处理中断的导入，避免每次全量扫描）
object MaterialRepair {
    private const val LEGACY_MARKER = "/.material-repair-v1"
    @Volatile private var running = false

    fun marker(path: String): String = path + ".indexing"

    fun mark(path: String) {
        if (path.isEmpty()) return
        try {
            File(marker(path)).writeBytes(ByteArray(0))
        } catch (e: Exception) {
            Log.e("juxia", "repair mark fail", e)
        }
    }

    fun clear(path: String) {
        if (path.isEmpty()) return
        try {
            File(marker(path)).delete()
        } catch (e: Exception) {
        }
    }

    private fun pending(path: String): Boolean = File(marker(path)).exists()

    private fun legacyDone(ctx: Context): Boolean = File(ctx.filesDir.path + LEGACY_MARKER).exists()

    private fun markLegacyDone(ctx: Context) {
        try {
            File(ctx.filesDir.path + LEGACY_MARKER).writeBytes(ByteArray(0))
        } catch (e: Exception) {
        }
    }

    suspend fun run(ctx: Context): Int {
        if (running) return 0
        running = true
        var repaired = 0
        try {
            val st = Store.instance
            val legacy = !legacyDone(ctx)
            for (m in st.data.materials) {
                if (m.path.isEmpty()) continue
                if (!File(m.path).exists()) {
                    clear(m.path)
                    continue
                }
                val must = pending(m.path)
                if (!legacy && !must) continue
                var need = must
                if (legacy && !need) {
                    val rows = st.materialSentences(m.id)
                    need = rows.isEmpty()
                }
                if (!need) continue
                st.clearMaterialIndex(m.id)
                val r = MaterialIndexer.indexFile(m.id, m.path, false, true)
                if (r.ok) {
                    repaired++
                    clear(m.path)
                } else if (legacy && !must) {
                    // 旧数据修复失败：留下标记，下次只重试这一份
                    mark(m.path)
                }
            }
            if (legacy) markLegacyDone(ctx)
        } catch (e: Exception) {
            Log.e("juxia", "material repair fail", e)
        } finally {
            running = false
        }
        return repaired
    }
}
