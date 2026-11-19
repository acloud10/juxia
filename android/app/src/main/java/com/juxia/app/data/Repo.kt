package com.juxia.app.data

import android.content.Context
import android.util.Log
import com.juxia.app.model.AppData
import com.juxia.app.model.DislikeEntry
import com.juxia.app.model.LibEntry
import com.juxia.app.model.MaterialEntry
import com.juxia.app.model.NoteItem
import com.juxia.app.model.OwnEntry
import com.juxia.app.services.AppError
import net.zetetic.database.sqlcipher.SQLiteDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

private typealias ContentValues = android.content.ContentValues

// 句栖 · RDB 持久层（翻译自 Repo.ets）
// 表结构、写队列、事务快照、FTS5 trigram 索引与鸿蒙版一一对应。
// 加密：SQLCipher 4.5.6 全库加密，密钥由 Android Keystore 托管（见 DbKey）。
// 打开数据库收敛在 openDb() 单点。
class Repo {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    private var store: SQLiteDatabase? = null
    private var ftsReady = false
    private val rowTasks = ArrayDeque<suspend () -> Unit>()
    private var rowBusy = false
    private val queueMutex = Mutex()
    private var restoreTokenValue = ""

    private data class Snapshot(
        var own: List<ContentValues> = emptyList(),
        var lib: List<ContentValues> = emptyList(),
        var dislikes: List<ContentValues> = emptyList(),
        var materials: List<ContentValues> = emptyList(),
        var kv: List<ContentValues> = emptyList(),
        var kvOnly: Boolean = false,
    )

    // SQLCipher 的 ContentValues 与 android.content.ContentValues 同名，用别名避免歧义
    // ---------- 生命周期 ----------

    suspend fun init(context: Context, legacy: AppData?): AppData {
        try {
            openDb(context)
            createTables()
            restoreTokenValue = getKv("restore_token") ?: ""
            val schema = getKv("schema")
            if (schema == "1") return loadAll()
            // schema 为空 = 新装（或极老库）：写入初始快照，建立 schema=1
            // （此前误抛 KV_READ_FAILED 导致新装用户永远落 prefs 缓存模式——二轮#7）
            val d = legacy ?: AppData()
            if (d.meta.firstUse == 0L) d.meta.firstUse = System.currentTimeMillis()
            writeSnapshot(makeSnapshot(d))
            return d
        } catch (e: Exception) {
            val msg = e.message ?: ""
            // 事务性失败原样穿透，调用方（Store.resetAll/replaceAll）依赖精确消息做回滚
            if (msg.contains("DATA_READ_FAILED") || msg.contains("WRITE_SNAPSHOT_FAILED") ||
                msg.contains("REPLACE_ALL_FAILED")) {
                throw e
            }
            // #23：其余异常（含 openDb 失败）如实上抛——Store 的降级链会切 prefs 模式；
            // 不能再"返回 legacy 却任由 Store 标 useDb=true"（store==null 时写入静默丢失）
            AppError.report("本地数据打开失败。", "重启应用后再试。若仍失败，不要清空数据；如能进入设置，先尝试导出备份。", true)
            Log.e("juxia", "repo init fail", e)
            throw IllegalStateException("DB_OPEN_FAILED")
        }
    }

    // D2-A（2026-11-16）：SQLCipher 全库加密，密钥 Keystore 托管（见 DbKey）。
    // 检测到明文旧库（SQLite format 3 头）→ sqlcipher_export 迁进加密库，旧库删除前留备份。
    private fun openDb(context: Context) {
        // sqlcipher-android 不会自动 loadLibrary；必须先加载 native，否则 nativeOpen 直接崩。
        try {
            System.loadLibrary("sqlcipher")
        } catch (e: UnsatisfiedLinkError) {
            throw IllegalStateException("SQLCIPHER_LOAD_FAILED")
        }
        val dbFile = File(context.filesDir, "juxia.db")
        // 迁移中断恢复：宁可恢复旧库/临时库，也不要新建空库掩盖旧数据
        val legacyFile = File(context.filesDir, "juxia_legacy_backup.db")
        val tmpFile = File(context.filesDir, "juxia_enc_tmp.db")
        if (!dbFile.exists()) {
            if (tmpFile.exists() && !isPlaintextDb(tmpFile)) {
                if (!tmpFile.renameTo(dbFile)) Log.e("juxia", "recover tmp db rename failed")
            } else if (legacyFile.exists()) {
                if (!legacyFile.renameTo(dbFile)) Log.e("juxia", "recover legacy db rename failed")
            }
        }
        // 新包 sqlcipher-android 4.5.6：AAR 字节级验证——openOrCreateDatabase(File, 密语, Factory, ErrorHandler)
        // 四参重载存在；loadLibs 不存在（native 库自加载），故不调用
        val pass = try {
            com.juxia.app.services.DbKey.getPassphrase(context)
        } catch (e: Exception) {
            throw IllegalStateException("DB_KEY_LOST")
        }
        if (dbFile.exists() && isPlaintextDb(dbFile)) {
            migratePlaintextDb(context, dbFile, pass)
        }
        store = SQLiteDatabase.openOrCreateDatabase(dbFile, pass, null, null)
    }

    private fun isPlaintextDb(f: File): Boolean {
        return try {
            val head = ByteArray(15)
            f.inputStream().use { it.read(head) }
            String(head, Charsets.US_ASCII) == "SQLite format 3"
        } catch (e: Exception) {
            false
        }
    }

    private fun migratePlaintextDb(ctx: Context, dbFile: File, pass: String) {
        val tmp = File(ctx.filesDir, "juxia_enc_tmp.db")
        if (tmp.exists()) tmp.delete()
        val enc = SQLiteDatabase.openOrCreateDatabase(tmp, pass, null, null)
        try {
            enc.rawQuery("ATTACH DATABASE ? AS plain KEY ''", arrayOf(dbFile.absolutePath)).use { it.moveToFirst() }
            // sqlcipher_export(target, source)：新的加密库是 main，旧明文库是 plain。
            enc.rawQuery("SELECT sqlcipher_export('main', 'plain')", null).use { it.moveToFirst() }
            enc.rawQuery("DETACH DATABASE plain", null).use { it.moveToFirst() }
        } finally {
            enc.close()
        }
        val legacy = File(ctx.filesDir, "juxia_legacy_backup.db")
        if (legacy.exists()) legacy.delete()
        if (!dbFile.renameTo(legacy)) throw IllegalStateException("DB_MIGRATE_RENAME_FAIL")
        if (!tmp.renameTo(dbFile)) {
            legacy.renameTo(dbFile)
            throw IllegalStateException("DB_MIGRATE_SWAP_FAIL")
        }
        // 新库就位且确认为密文后，才删除明文备份
        if (!isPlaintextDb(dbFile)) legacy.delete()
        else AppError.report("数据库迁移未完全确认。", "旧库已备份为 juxia_legacy_backup.db，不要手动删除。")
    }

    fun saveAll(d: AppData) {
        val snap = makeSnapshot(d)
        pushRow { writeSnapshot(snap) }
    }

    // 全量替换：等当前写入结束，再在一个事务里清空并写入；失败向上抛
    suspend fun replaceAll(d: AppData, restoreToken: String) {
        flushRows()
        val previousToken = restoreTokenValue
        restoreTokenValue = restoreToken
        try {
            writeSnapshot(makeSnapshot(d, restoreToken), clearIndex = true)
        } catch (e: Exception) {
            restoreTokenValue = previousToken
            throw Exception(e.message ?: "替换失败")
        }
    }

    suspend fun restoreToken(): String {
        if (restoreTokenValue.isNotEmpty()) return restoreTokenValue
        return getKv("restore_token") ?: ""
    }

    suspend fun flush() {
        if (store == null) return
        flushRows()
    }

    private suspend fun flushRows() {
        while (true) {
            val (busy, pending) = queueMutex.withLock { rowBusy to rowTasks.isNotEmpty() }
            if (!busy && !pending) return
            delay(10)
        }
    }

    fun saveKv(d: AppData) {
        val rows = kvRows(d)
        pushRow {
            writeSnapshot(Snapshot(kv = rows, kvOnly = true))
        }
    }

    // ---------- 快照 ----------

    private fun makeSnapshot(d: AppData, restoreToken: String = ""): Snapshot {
        val snap = Snapshot()
        snap.own = d.own.map { ownBucket(it) }
        snap.lib = d.lib.map { libBucket(it) }
        snap.dislikes = d.dislikes.map {
            ContentValues().apply {
                put("text", it.text); put("source", it.source)
                put("origin", it.origin); put("at", it.at)
            }
        }
        snap.materials = d.materials.map {
            ContentValues().apply {
                put("id", it.id); put("name", it.name); put("text", it.text)
                put("path", it.path); put("size", it.size); put("createdAt", it.createdAt)
            }
        }
        snap.kv = kvRows(d).toMutableList()
        val token = if (restoreToken.isNotEmpty()) restoreToken else restoreTokenValue
        if (token.isNotEmpty()) {
            snap.kv = snap.kv + ContentValues().apply { put("k", "restore_token"); put("v", token) }
        }
        return snap
    }

    private fun kvRows(d: AppData): List<ContentValues> = listOf(
        ContentValues().apply { put("k", "schema"); put("v", "1") },
        ContentValues().apply { put("k", "settings"); put("v", json.encodeToString(d.settings)) },
        ContentValues().apply { put("k", "day"); put("v", json.encodeToString(d.day)) },
        ContentValues().apply { put("k", "meta"); put("v", json.encodeToString(d.meta)) },
    )

    private suspend fun writeSnapshot(snap: Snapshot, clearIndex: Boolean = false) {
        val s = store ?: throw IllegalStateException("数据库未就绪")
        try {
            s.beginTransaction()
            if (snap.kvOnly) {
                s.execSQL("DELETE FROM kv")
                for (b in snap.kv) s.insertWithOnConflict("kv", null, b, SQLiteDatabase.CONFLICT_REPLACE)
            } else {
                if (clearIndex) {
                    s.execSQL("DELETE FROM material_sentences")
                    if (ftsReady) {
                        try { s.execSQL("DELETE FROM material_fts") }
                        catch (e: Exception) { Log.e("juxia", "fts clear in replace fail", e) }
                    }
                }
                s.execSQL("DELETE FROM own")
                s.execSQL("DELETE FROM lib")
                s.execSQL("DELETE FROM dislikes")
                s.execSQL("DELETE FROM materials")
                s.execSQL("DELETE FROM kv")
                for (b in snap.own) s.insertWithOnConflict("own", null, b, SQLiteDatabase.CONFLICT_REPLACE)
                for (b in snap.lib) s.insertWithOnConflict("lib", null, b, SQLiteDatabase.CONFLICT_REPLACE)
                for (b in snap.dislikes) s.insertWithOnConflict("dislikes", null, b, SQLiteDatabase.CONFLICT_REPLACE)
                for (b in snap.materials) s.insertWithOnConflict("materials", null, b, SQLiteDatabase.CONFLICT_REPLACE)
                for (b in snap.kv) s.insertWithOnConflict("kv", null, b, SQLiteDatabase.CONFLICT_REPLACE)
            }
            s.setTransactionSuccessful()
        } catch (e: Exception) {
            AppError.report("保存失败。", "检查手机存储空间后重试；如反复失败，先尝试导出备份，并避免继续修改。", true)
            Log.e("juxia", "write snapshot fail", e)
            throw IllegalStateException("WRITE_SNAPSHOT_FAILED")
        } finally {
            try { s.endTransaction() } catch (e2: Exception) { Log.e("juxia", "endTransaction fail", e2) }
        }
    }

    // ---------- 建表（含旧列补齐，与鸿蒙版一致） ----------

    private fun createTables() {
        val s = store ?: return
        try {
            s.execSQL("CREATE TABLE IF NOT EXISTS own (" +
                "id TEXT PRIMARY KEY, kind TEXT, text TEXT, note TEXT, bindIds TEXT, " +
                "createdAt INTEGER, archCat TEXT, archNote TEXT, archAt INTEGER, " +
                "revisitAt INTEGER, snoozeUntil INTEGER, foot TEXT, footIds TEXT, notes TEXT, replyToId TEXT, replyFrom TEXT)")
            s.execSQL("CREATE TABLE IF NOT EXISTS lib (" +
                "id TEXT PRIMARY KEY, text TEXT, source TEXT, origin TEXT, tag TEXT, createdAt INTEGER, bindIds TEXT)")
            try { s.execSQL("ALTER TABLE lib ADD COLUMN bindIds TEXT") } catch (_: Exception) { /* 列已存在 */ }
            try { s.execSQL("ALTER TABLE own ADD COLUMN replyToId TEXT") } catch (_: Exception) { /* 列已存在 */ }
            try { s.execSQL("ALTER TABLE own ADD COLUMN replyFrom TEXT") } catch (_: Exception) { /* 列已存在 */ }
            try { s.execSQL("ALTER TABLE own ADD COLUMN footIds TEXT") } catch (_: Exception) { /* 列已存在 */ }
            s.execSQL("CREATE TABLE IF NOT EXISTS dislikes (text TEXT PRIMARY KEY, source TEXT, origin TEXT, at INTEGER)")
            s.execSQL("CREATE TABLE IF NOT EXISTS materials (id TEXT PRIMARY KEY, name TEXT, text TEXT, path TEXT, size INTEGER, createdAt INTEGER)")
            s.execSQL("CREATE TABLE IF NOT EXISTS material_sentences (material_id TEXT, ord INTEGER, text TEXT, PRIMARY KEY(material_id, ord))")
            try {
                s.execSQL("CREATE VIRTUAL TABLE IF NOT EXISTS material_fts USING fts5(text, material_id UNINDEXED, ord UNINDEXED, tokenize=trigram)")
                ftsReady = true
            } catch (e: Exception) {
                ftsReady = false
                Log.e("juxia", "fts create fail", e)
            }
            if (ftsReady) rebuildFtsIfNeeded()
            s.execSQL("CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT)")
        } catch (e: Exception) {
            AppError.report("本地数据库初始化失败。", "重启应用后再试；不要清空数据。如仍失败，联系开发者。", true)
            Log.e("juxia", "create tables fail", e)
        }
    }

    private fun rebuildFtsIfNeeded() {
        val s = store ?: return
        try {
            val sentenceCount = s.rawQuery("SELECT COUNT(*) AS c FROM material_sentences", null).use { c ->
                if (c.moveToFirst()) c.getLong(0) else 0
            }
            val ftsCount = s.rawQuery("SELECT COUNT(*) AS c FROM material_fts", null).use { c ->
                if (c.moveToFirst()) c.getLong(0) else 0
            }
            if (sentenceCount != ftsCount) {
                s.execSQL("DELETE FROM material_fts")
                s.execSQL("INSERT INTO material_fts(material_id, ord, text) SELECT material_id, ord, text FROM material_sentences")
            }
        } catch (e: Exception) {
            Log.e("juxia", "fts rebuild fail", e)
            AppError.report("材料搜索索引修复失败。", "材料仍可打开，但搜索可能不完整；重启应用后再试。")
        }
    }

    // ---------- 材料句子 ----------

    suspend fun replaceSentences(materialId: String, sentences: List<String>): Boolean {
        if (store == null) return false
        clearSentences(materialId)
        if (sentences.isEmpty()) return true
        return appendSentences(materialId, 0, sentences) >= sentences.size
    }

    suspend fun appendSentences(materialId: String, startOrd: Int, sentences: List<String>): Int {
        val s = store ?: return 0
        if (sentences.isEmpty()) return 0
        var written = 0
        try {
            var i = 0
            while (i < sentences.size) {
                val chunk = sentences.subList(i, minOf(i + 200, sentences.size))
                s.beginTransaction()
                try {
                    val st = s.compileStatement("INSERT OR REPLACE INTO material_sentences(material_id, ord, text) VALUES (?, ?, ?)")
                    chunk.forEachIndexed { j, text ->
                        st.bindString(1, materialId)
                        st.bindLong(2, (startOrd + i + j).toLong())
                        st.bindString(3, text)
                        st.executeInsert()
                    }
                    if (ftsReady) {
                        try {
                            val ft = s.compileStatement("INSERT INTO material_fts(material_id, ord, text) VALUES (?, ?, ?)")
                            chunk.forEachIndexed { j, text ->
                                ft.bindString(1, materialId)
                                ft.bindLong(2, (startOrd + i + j).toLong())
                                ft.bindString(3, text)
                                ft.executeInsert()
                            }
                        } catch (e: Exception) {
                            Log.e("juxia", "fts append fail", e)
                        }
                    }
                    s.setTransactionSuccessful()
                } finally {
                    s.endTransaction()
                }
                written += chunk.size
                i += 200
            }
        } catch (e: Exception) {
            AppError.report("材料索引保存失败。", "回到材料库重试导入；原文件不会被删除。")
            Log.e("juxia", "sentence append fail", e)
        }
        return written
    }

    suspend fun clearSentences(materialId: String) {
        val s = store ?: return
        try {
            s.execSQL("DELETE FROM material_sentences WHERE material_id = ?", arrayOf(materialId))
            if (ftsReady) {
                try {
                    s.execSQL("DELETE FROM material_fts WHERE material_id = ?", arrayOf(materialId))
                } catch (e: Exception) {
                    Log.e("juxia", "fts clear one fail", e)
                    AppError.report("材料索引清理失败。", "材料已删除，但搜索索引可能未完全清理；重启应用后可重试。")
                }
            }
        } catch (e: Exception) {
            Log.e("juxia", "sentence clear one fail", e)
            AppError.report("材料内容清理失败。", "删除可能未完成；请重启应用后重试，不要继续大量修改。")
        }
    }

    suspend fun clearAllSentences() {
        val s = store ?: return
        try {
            s.execSQL("DELETE FROM material_sentences")
            if (ftsReady) {
                try { s.execSQL("DELETE FROM material_fts") }
                catch (e: Exception) { Log.e("juxia", "fts clear fail", e) }
            }
        } catch (e: Exception) {
            AppError.report("材料索引清理失败。", "回到材料库重试删除或重新导入；不要清空全部数据。")
            Log.e("juxia", "sentences clear fail", e)
        }
    }

    private fun ftsQuery(keywords: List<String>): String =
        keywords.joinToString(" AND ") { kw -> "\"${kw.replace("\"", "\"\"")}\"" }

    suspend fun allSentences(materialId: String, limit: Int = 0): List<String> {
        val s = store ?: return emptyList()
        val out = mutableListOf<String>()
        try {
            val sql = if (limit > 0)
                "SELECT text FROM material_sentences WHERE material_id = ? ORDER BY ord LIMIT ?"
            else
                "SELECT text FROM material_sentences WHERE material_id = ? ORDER BY ord"
            val args = if (limit > 0) arrayOf(materialId, limit.toString()) else arrayOf(materialId)
            s.rawQuery(sql, args).use { c ->
                while (c.moveToNext()) out.add(c.getString(0))
            }
        } catch (e: Exception) {
            AppError.report("材料内容读取失败。", "重启应用后再试；不要清空材料。")
            Log.e("juxia", "sentences read fail", e)
        }
        return out
    }

    suspend fun searchSentences(keywords: List<String>, materialId: String): List<String> {
        val s = store ?: return emptyList()
        try {
            if (ftsReady && keywords.isNotEmpty()) {
                try {
                    val fsql = StringBuilder("SELECT text FROM material_fts WHERE material_fts MATCH ?")
                    val fargs = mutableListOf(ftsQuery(keywords))
                    if (materialId.isNotEmpty()) {
                        fsql.append(" AND material_id = ?")
                        fargs.add(materialId)
                    }
                    fsql.append(" LIMIT 120")
                    val fout = mutableListOf<String>()
                    s.rawQuery(fsql.toString(), fargs.toTypedArray()).use { c ->
                        while (c.moveToNext()) fout.add(c.getString(0))
                    }
                    if (fout.isNotEmpty()) return fout
                } catch (e: Exception) {
                    Log.e("juxia", "fts search fail", e)
                }
            }
            val sql = StringBuilder("SELECT text FROM material_sentences WHERE 1=1")
            val args = mutableListOf<String>()
            keywords.forEach { kw ->
                sql.append(" AND text LIKE ?")
                args.add("%$kw%")
            }
            if (materialId.isNotEmpty()) {
                sql.append(" AND material_id = ?")
                args.add(materialId)
            }
            sql.append(" LIMIT 120")
            val out = mutableListOf<String>()
            s.rawQuery(sql.toString(), args.toTypedArray()).use { c ->
                while (c.moveToNext()) out.add(c.getString(0))
            }
            return out
        } catch (e: Exception) {
            AppError.report("材料检索失败。", "重试；如仍失败，重启应用后再试。")
            Log.e("juxia", "sentence search fail", e)
            return emptyList()
        }
    }

    // ---------- 读取 ----------

    private fun getKv(key: String): String? {
        val s = store ?: return null
        try {
            s.rawQuery("SELECT v FROM kv WHERE k = ?", arrayOf(key)).use { c ->
                return if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (e: Exception) {
            Log.e("juxia", "kv read fail: $key", e)
            return null
        }
    }

    private fun parseStrings(raw: String?): MutableList<String> = try {
        raw?.let { json.decodeFromString<MutableList<String>>(it) } ?: mutableListOf()
    } catch (e: Exception) { mutableListOf() }

    private fun parseNotes(raw: String?): MutableList<NoteItem> = try {
        raw?.let { json.decodeFromString<MutableList<NoteItem>>(it) } ?: mutableListOf()
    } catch (e: Exception) { mutableListOf() }

    private suspend fun loadAll(): AppData {
        val d = AppData()
        val s = store ?: return d
        try {
            s.rawQuery("SELECT * FROM own ORDER BY createdAt DESC", null).use { c ->
                while (c.moveToNext()) {
                    val e = OwnEntry(
                        id = c.getString(c.getColumnIndexOrThrow("id")),
                        kind = c.getString(c.getColumnIndexOrThrow("kind")),
                        text = c.getString(c.getColumnIndexOrThrow("text")),
                        note = c.getString(c.getColumnIndexOrThrow("note")),
                        createdAt = c.getLong(c.getColumnIndexOrThrow("createdAt")),
                        archCat = c.getString(c.getColumnIndexOrThrow("archCat")),
                        archNote = c.getString(c.getColumnIndexOrThrow("archNote")),
                        archAt = c.getLong(c.getColumnIndexOrThrow("archAt")),
                        revisitAt = c.getLong(c.getColumnIndexOrThrow("revisitAt")),
                        snoozeUntil = c.getLong(c.getColumnIndexOrThrow("snoozeUntil")),
                    )
                    e.bindIds = parseStrings(c.getString(c.getColumnIndexOrThrow("bindIds")))
                    e.foot = parseStrings(c.getString(c.getColumnIndexOrThrow("foot")))
                    val fi = c.getColumnIndex("footIds")
                    if (fi >= 0) e.footIds = parseStrings(c.getString(fi))
                    while (e.footIds.size < e.foot.size) e.footIds.add("")
                    if (e.footIds.size > e.foot.size) e.footIds = e.footIds.subList(0, e.foot.size).toMutableList()
                    e.notes = parseNotes(c.getString(c.getColumnIndexOrThrow("notes")))
                    val rti = c.getColumnIndex("replyToId")
                    if (rti >= 0) e.replyToId = c.getString(rti)
                    val rfi = c.getColumnIndex("replyFrom")
                    if (rfi >= 0) e.replyFrom = c.getString(rfi)
                    d.own.add(e)
                }
            }
            s.rawQuery("SELECT * FROM lib ORDER BY createdAt DESC", null).use { c ->
                while (c.moveToNext()) {
                    val e = LibEntry(
                        id = c.getString(c.getColumnIndexOrThrow("id")),
                        text = c.getString(c.getColumnIndexOrThrow("text")),
                        source = c.getString(c.getColumnIndexOrThrow("source")),
                        origin = c.getString(c.getColumnIndexOrThrow("origin")),
                        tag = c.getString(c.getColumnIndexOrThrow("tag")),
                        createdAt = c.getLong(c.getColumnIndexOrThrow("createdAt")),
                    )
                    val bi = c.getColumnIndex("bindIds")
                    if (bi >= 0) e.bindIds = parseStrings(c.getString(bi))
                    d.lib.add(e)
                }
            }
            s.rawQuery("SELECT * FROM dislikes ORDER BY at DESC", null).use { c ->
                while (c.moveToNext()) {
                    d.dislikes.add(DislikeEntry(
                        text = c.getString(c.getColumnIndexOrThrow("text")),
                        source = c.getString(c.getColumnIndexOrThrow("source")),
                        origin = c.getString(c.getColumnIndexOrThrow("origin")),
                        at = c.getLong(c.getColumnIndexOrThrow("at")),
                    ))
                }
            }
            s.rawQuery("SELECT * FROM materials ORDER BY createdAt ASC", null).use { c ->
                while (c.moveToNext()) {
                    d.materials.add(MaterialEntry(
                        id = c.getString(c.getColumnIndexOrThrow("id")),
                        name = c.getString(c.getColumnIndexOrThrow("name")),
                        text = c.getString(c.getColumnIndexOrThrow("text")),
                        path = c.getString(c.getColumnIndexOrThrow("path")),
                        size = c.getLong(c.getColumnIndexOrThrow("size")),
                        createdAt = c.getLong(c.getColumnIndexOrThrow("createdAt")),
                    ))
                }
            }
            s.rawQuery("SELECT * FROM kv", null).use { c ->
                while (c.moveToNext()) {
                    val k = c.getString(c.getColumnIndexOrThrow("k"))
                    val v = c.getString(c.getColumnIndexOrThrow("v"))
                    try {
                        when (k) {
                            "settings" -> d.settings = json.decodeFromString(v)
                            "day" -> d.day = json.decodeFromString(v)
                            "meta" -> d.meta = json.decodeFromString(v)
                        }
                    } catch (e: Exception) {
                        Log.e("juxia", "kv row parse fail: $k", e)
                    }
                }
            }
        } catch (e: Exception) {
            AppError.report("读取本地数据失败。", "重启应用后再试；不要清空数据。", true)
            Log.e("juxia", "load all fail", e)
            throw IllegalStateException("DATA_READ_FAILED")
        }
        return d
    }

    // ---------- 单行增量写入 ----------

    private fun ownBucket(e: OwnEntry) = ContentValues().apply {
        put("id", e.id); put("kind", e.kind); put("text", e.text); put("note", e.note)
        put("bindIds", json.encodeToString(e.bindIds))
        put("createdAt", e.createdAt)
        put("archCat", e.archCat); put("archNote", e.archNote); put("archAt", e.archAt)
        put("revisitAt", e.revisitAt); put("snoozeUntil", e.snoozeUntil)
        put("foot", json.encodeToString(e.foot))
        put("footIds", json.encodeToString(e.footIds))
        put("notes", json.encodeToString(e.notes))
        put("replyToId", e.replyToId); put("replyFrom", e.replyFrom)
    }

    private fun libBucket(e: LibEntry) = ContentValues().apply {
        put("id", e.id); put("text", e.text); put("source", e.source)
        put("origin", e.origin); put("tag", e.tag); put("createdAt", e.createdAt)
        put("bindIds", json.encodeToString(e.bindIds))
    }

    private fun pushRow(task: suspend () -> Unit) {
        scope.launch {
            queueMutex.withLock { rowTasks.addLast(task) }
            drainRows()
        }
    }

    private suspend fun drainRows() {
        queueMutex.withLock { if (rowBusy) return; rowBusy = true }
        try {
            while (true) {
                val t = queueMutex.withLock { rowTasks.removeFirstOrNull() } ?: break
                try {
                    t()
                } catch (e: Exception) {
                    Log.e("juxia", "row task fail", e)
                }
            }
        } finally {
            val hasMore = queueMutex.withLock {
                rowBusy = false
                rowTasks.isNotEmpty()
            }
            if (hasMore) drainRows()
        }
    }

    private fun upsert(table: String, b: ContentValues) {
        if (store == null) return
        pushRow {
            try {
                store!!.insertWithOnConflict(table, null, b, SQLiteDatabase.CONFLICT_REPLACE)
            } catch (e: Exception) {
                AppError.report("保存失败。", "检查存储空间后重试；若仍失败，重启应用。")
                Log.e("juxia", "upsert fail: $table", e)
            }
        }
    }

    private fun deleteById(table: String, id: String) {
        if (store == null) return
        pushRow {
            try {
                store!!.delete(table, "id = ?", arrayOf(id))
            } catch (e: Exception) {
                AppError.report("删除失败。", "重试；若仍失败，重启应用。")
                Log.e("juxia", "delete fail: $table", e)
            }
        }
    }

    fun saveOwnRow(e: OwnEntry) = upsert("own", ownBucket(e))
    fun saveLibRow(e: LibEntry) = upsert("lib", libBucket(e))
    fun deleteLibRow(id: String) = deleteById("lib", id)
    fun deleteOwnRow(id: String) = deleteById("own", id)
    fun deleteMaterialRow(id: String) = deleteById("materials", id)

    fun saveDislikeRow(e: DislikeEntry) {
        upsert("dislikes", ContentValues().apply {
            put("text", e.text); put("source", e.source); put("origin", e.origin); put("at", e.at)
        })
    }

    fun deleteDislikeRow(text: String) {
        if (store == null) return
        pushRow {
            try {
                store!!.delete("dislikes", "text = ?", arrayOf(text))
            } catch (e: Exception) {
                AppError.report("删除排除项失败。", "重试；若仍失败，重启应用。")
                Log.e("juxia", "dislike delete fail", e)
            }
        }
    }
}
