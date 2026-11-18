package com.juxia.app.services

import android.content.Context
import android.util.Log
import java.io.File
import com.juxia.app.data.Store

// 句栖 · 启动恢复检查（翻译自 RestoreRecovery.ets）
// journal 损坏 → 报错；phase=done → 清理收尾；token 不符 → 回滚；token 相符 → 补索引后清理。
object RestoreRecovery {
    private fun exists(path: String): Boolean = try { File(path).exists() } catch (e: Exception) { false }

    suspend fun recover(ctx: Context) {
        val journal: RestoreJournalData = try {
            RestoreJournal.read(ctx) ?: return
        } catch (e: Exception) {
            AppError.report("恢复日志损坏。", "请重新恢复备份；不要继续修改当前数据。")
            return
        }
        if (journal.phase == "done") {
            if (exists(journal.newDir)) RestoreJournal.cleanupOldMaterials(ctx, journal.newDir)
            RestoreJournal.remove(ctx)
            return
        }
        val store = Store.instance
        val dbToken: String = try {
            store.restoreToken()
        } catch (e: Exception) {
            Log.e("juxia", "restore recovery token fail" + "：" + (e.message ?: ""))
            return
        }
        if (dbToken != journal.token) {
            // DB 没有提交：新材料目录作废，旧数据保持原样
            RestoreJournal.removeDir(journal.newDir)
            RestoreJournal.remove(ctx)
            return
        }
        // DB 已提交：确认新材料目录还在，再补索引和清理
        if (!exists(journal.newDir)) {
            AppError.report("上次恢复未完成。", "材料目录缺失；请重新恢复备份，不要继续修改当前数据。")
            return
        }
        var failed = 0
        for (m in store.data.materials) {
            try {
                store.clearMaterialIndex(m.id)
                if (m.path.isEmpty()) {
                    // 纯文本材料：path 为空不能喂 indexFile（File("").inputStream() 必崩）
                    store.reindexMaterial(m.id, m.text)
                } else {
                    val r = MaterialIndexer.indexFile(m.id, m.path, markdown = false, quiet = true)
                    if (!r.ok) failed++
                }
            } catch (e: Exception) {
                failed++
            }
        }
        if (failed > 0) {
            AppError.report("上次恢复未完成。", "材料索引还没建完；重启应用后会继续重试。")
            return
        }
        RestoreJournal.cleanupOldMaterials(ctx, journal.newDir)
        journal.phase = "done"
        RestoreJournal.write(ctx, journal)
        RestoreJournal.remove(ctx)
    }
}
