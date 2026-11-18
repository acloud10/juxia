package com.juxia.app.services

import android.content.Context
import android.util.Log
import java.io.File
import java.io.RandomAccessFile

// 句栖 · 恢复 journal（翻译自 RestoreJournal.ets：跨文件系统/数据库的恢复阶段记录）
@kotlinx.serialization.Serializable
data class RestoreJournalData(
    var format: String = "juxia-restore-journal",
    var version: Int = 1,
    var token: String = "",
    var phase: String = "prepared",
    var newDir: String = "",
    var createdAt: Long = 0,
)

object RestoreJournal {
    fun path(ctx: Context): String = File(ctx.filesDir, "restore-journal.json").absolutePath
    fun tmpPath(ctx: Context): String = File(ctx.filesDir, "restore-journal.tmp").absolutePath

    /** 读：无正式文件但存在 tmp（写完未 rename）→ 视为未提交，清掉半成品 */
    fun read(ctx: Context): RestoreJournalData? {
        val p = File(path(ctx))
        val tmp = File(tmpPath(ctx))
        try {
            if (!p.exists()) {
                if (tmp.exists()) tmp.delete()
                return null
            }
            val text = p.readText(Charsets.UTF_8)
            val d = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                .decodeFromString(RestoreJournalData.serializer(), text)
            if (d.format != "juxia-restore-journal" || d.version != 1 ||
                d.token.isEmpty() || d.newDir.isEmpty()) {
                throw IllegalStateException("JOURNAL_SHAPE")
            }
            val root = File(ctx.filesDir, "materials").absolutePath + "/"
            if (!d.newDir.startsWith(root)) throw IllegalStateException("JOURNAL_PATH")
            return d
        } catch (e: Exception) {
            Log.e("juxia", "restore journal read fail" + "：" + (e.message ?: ""))
            throw Exception("JOURNAL_CORRUPT")
        }
    }

    /** 原子写：tmp → fsync → rename；失败抛 JOURNAL_WRITE_FAILED */
    fun write(ctx: Context, d: RestoreJournalData) {
        val p = File(path(ctx))
        val tmp = File(tmpPath(ctx))
        var raf: RandomAccessFile? = null
        try {
            raf = RandomAccessFile(tmp, "rw")
            raf.setLength(0)
            raf.write(kotlinx.serialization.json.Json { encodeDefaults = true }
                .encodeToString(RestoreJournalData.serializer(), d).toByteArray(Charsets.UTF_8))
            raf.fd.sync()
            try { raf.close() } catch (_: Exception) {}
            raf = null
            if (!tmp.renameTo(p)) throw IllegalStateException("rename fail")
        } catch (e: Exception) {
            throw Exception("JOURNAL_WRITE_FAILED")
        } finally {
            try { raf?.close() } catch (_: Exception) {}
            try { if (tmp.exists()) tmp.delete() } catch (_: Exception) {}
        }
    }

    fun remove(ctx: Context) {
        try { File(path(ctx)).delete() } catch (e: Exception) { Log.e("juxia", "journal remove fail" + "：" + (e.message ?: "")) }
        try { File(tmpPath(ctx)).delete() } catch (_: Exception) {}
    }

    fun removeDir(dir: String) {
        try {
            val f = File(dir)
            f.listFiles()?.forEach { child ->
                try {
                    if (child.isDirectory) removeDir(child.absolutePath) else child.delete()
                } catch (_: Exception) {}
            }
            f.delete()
        } catch (_: Exception) {}
    }

    /** 只保留当前 generation，清掉旧目录/旧平铺文件 */
    fun cleanupOldMaterials(ctx: Context, keepDir: String) {
        val root = File(ctx.filesDir, "materials")
        try {
            if (!root.exists()) return
            root.listFiles()?.forEach { f ->
                if (f.absolutePath == keepDir) return@forEach
                try {
                    if (f.isDirectory) removeDir(f.absolutePath) else f.delete()
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            Log.e("juxia", "cleanup old materials fail" + "：" + (e.message ?: ""))
        }
    }
}
