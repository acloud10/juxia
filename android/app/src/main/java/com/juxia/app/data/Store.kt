package com.juxia.app.data

import android.content.Context
import android.content.SharedPreferences
import com.juxia.app.model.AppData
import com.juxia.app.model.DAY_MS
import com.juxia.app.model.DislikeEntry
import com.juxia.app.model.LibEntry
import com.juxia.app.model.MaterialEntry
import com.juxia.app.model.NoteItem
import com.juxia.app.model.OwnEntry
import com.juxia.app.model.Settings
import com.juxia.app.model.todayStr
import com.juxia.app.model.fmtMD
import com.juxia.app.utils.splitSentences
import com.juxia.app.model.revisitAtFromDays
import com.juxia.app.services.AppError
import com.juxia.app.services.LegacyKeyCleanup
import com.juxia.app.services.MaterialIndexer
import com.juxia.app.state.UiState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// 句栖 · 业务中枢（翻译自 Store.ets）
// 内存态 AppData + 统一写队列入口；所有修改先落内存、再经 writeOwn/writeLib 走增量，
// 或由 persist() 走全量快照；两条路径都最终汇入 Repo 的同一条串行队列。
class Store {
    var data: AppData = AppData()
        private set

    private var repo: Repo? = null
    private var prefs: SharedPreferences? = null
    private var fallbackToken: String = ""
    private var useDb = false
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready
    private val _initError = MutableStateFlow("")
    val initError: StateFlow<String> = _initError
    private val initMutex = Mutex()

    private var idSeq = 0
    private var prefsJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    @Serializable
    private data class PrefsEnvelope(var d: AppData = AppData(), var t: String = "")

    // ---------- id 与初始化 ----------

    private fun idExists(id: String): Boolean =
        data.own.any { it.id == id } || data.lib.any { it.id == id } || data.materials.any { it.id == id }

    fun newId(): String {
        // 对齐鸿蒙：序列号 + 时间戳，并与现有 id 比对直到不冲突
        var id: String
        do {
            val t = System.currentTimeMillis().toString(36)
            idSeq = (idSeq + 1) % 46656
            id = t + idSeq.toString(36).padStart(3, '0')
        } while (idExists(id))
        return id
    }

    @Volatile private var initializing = false

    suspend fun init(context: Context, legacy: AppData? = null) = initMutex.withLock {
        try {
            initOnce(context, legacy)
            _initError.value = ""
        } catch (e: Exception) {
            _initError.value = e.message ?: "启动失败"
            throw e
        } finally {
            initializing = false
        }
    }

    private suspend fun initOnce(context: Context, legacy: AppData?) {
        // 原子守卫：BOOT 接收器与 Application 可能并发进入，check-then-act 会双初始化
        if (_ready.value || initializing) return
        initializing = true
        prefs = context.getSharedPreferences("juxia_prefs", Context.MODE_PRIVATE)
        var legacyData = legacy
        if (legacyData == null) {
            try {
                val env = prefs!!.getString("appdata_v2", "") ?: ""
                if (env.isNotEmpty()) legacyData = json.decodeFromString(PrefsEnvelope.serializer(), env).d
            } catch (e: Exception) {
                AppError.report("本地缓存读取失败。", "重启应用后再试；如能进入应用，请先导出备份。", true)
            }
        }
        try {
            val r = Repo()
            data = r.init(context, legacyData)
            repo = r
            useDb = true
        } catch (e: Exception) {
            val msg = e.message ?: ""
            if (msg.contains("WRITE_SNAPSHOT_FAILED") || msg.contains("REPLACE_ALL_FAILED") || msg.contains("DATA_READ_FAILED")) throw e
            repo = null
            useDb = false
            if (msg.contains("DB_KEY_LOST")) {
                AppError.report("数据库密钥无法恢复。", "本机 Keystore 已重置，旧数据库无法解开；已切换缓存模式。如有加密备份，可恢复数据。", true)
            }
            if (legacyData != null) data = legacyData
            AppError.report(
                "本地数据库不可用。",
                "已临时改用本地缓存继续，功能可用，但建议尽快重启应用或导出备份。",
                true
            )
        }
        normalize()
        LegacyKeyCleanup.clear(context)
        try {
            rollDay()
            persist()
            _ready.value = true
        } finally {
            initializing = false
        }
    }

    // ---------- 通知权限询问（只问一次） ----------
    fun notifAsked(): Boolean = prefs?.getBoolean("notif_asked", false) == true
    fun markNotifAsked() { prefs?.edit()?.putBoolean("notif_asked", true)?.apply() }

    /** 改回访时刻后，把所有已约回访平移到新时刻（P1-7：对齐鸿蒙版行为） */
    fun shiftRevisitTimes(hour: Int, minute: Int) {
        val now = System.currentTimeMillis()
        var changed = false
        for (e in data.own) {
            if (!e.isArchived() || e.revisitAt <= 0) continue
            val cal = java.util.Calendar.getInstance().apply { timeInMillis = e.revisitAt }
            cal.set(java.util.Calendar.HOUR_OF_DAY, hour)
            cal.set(java.util.Calendar.MINUTE, minute)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            var t = cal.timeInMillis
            if (t < now) t += DAY_MS // 当天时刻已过 → 顺延一天
            if (t != e.revisitAt) {
                e.revisitAt = t
                if (e.snoozeUntil in 1 until now) e.snoozeUntil = 0
                writeOwn(e)
                changed = true
            }
        }
        if (changed) {
            persist()
            bump()
        }
    }

    fun storageMode(): String = if (useDb) "本地加密存储" else "本地存储"
    fun usesDb(): Boolean = useDb

    // ---------- 归一化（旧字段钳制 + footIds 对齐） ----------

    fun normalize() {
        val s = data.settings
        // 钳制范围对齐鸿蒙 Store.normalize：字号 0.85–1.4、开机字号 0.8–2.5、停留 300–5000
        if (s.fontScale < 0.85) s.fontScale = 0.85
        if (s.fontScale > 1.4) s.fontScale = 1.4
        if (s.bootFontScale < 0.8) s.bootFontScale = 0.8
        if (s.bootFontScale > 2.5) s.bootFontScale = 2.5
        if (s.bootHoldMs < 300) s.bootHoldMs = 300
        if (s.bootHoldMs > 5000) s.bootHoldMs = 5000
        if (s.ritualMode != "full" && s.ritualMode != "short" && s.ritualMode != "off") s.ritualMode = "full"
        if (s.theme != "system" && s.theme != "light" && s.theme != "dark") s.theme = "system"
        if (s.skin != "classic" && s.skin != "plain") s.skin = "classic"
        s.background = com.juxia.app.model.BackgroundStyle.from(s.background)
        // 对齐鸿蒙：只保留实际使用的四张（经典明/暗、朴素明/暗），两个 classic 兼容字段清空
        s.background.lightClassic.path = ""
        s.background.darkClassic.path = ""
        data.meta.openDays.sort()
        if (data.meta.firstUse == 0L) data.meta.firstUse = System.currentTimeMillis()
        // 对齐鸿蒙：内置句库已移除，旧版本收藏/排除的内置句一并清掉
        data.lib.removeAll { it.origin == "builtin" }
        data.dislikes.removeAll { it.origin == "builtin" }
        autoFillFootIds()
    }

    private fun autoFillFootIds() {
        for (e in data.own) {
            if (e.kind != "encourage") continue
            e.footIds.clear() // 幂等：normalize 可能被 replaceAll/resetAll 重入，先清空再重建
            if (e.foot.isEmpty()) continue
            val lines = footLineMap(e)
            for (i in e.foot.indices) {
                val line = e.foot[i]
                val close = line.indexOf('」')
                if (close < 0) {
                    e.footIds.add(FOOT_UNKNOWN); continue
                }
                val prefix = line.substring(0, close + 1)
                val found = lines[prefix]
                if (found != null) e.footIds.add(found) else e.footIds.add(FOOT_UNKNOWN)
            }
        }
    }

    // ---------- 持久化 ----------

    fun persist() {
        val r = repo
        if (useDb && r != null) r.saveAll(data) else persistPrefs()
    }

    fun persistPrefs() {
        prefsJob?.cancel()
        prefsJob = scope.launch {
            delay(150)
            persistPrefsNow(fallbackToken)
        }
    }

    fun persistPrefsNow(token: String) {
        val p = prefs ?: return
        try {
            p.edit().putString("appdata_v2", json.encodeToString(PrefsEnvelope.serializer(), PrefsEnvelope(data, token))).apply()
        } catch (e: Exception) {
            AppError.report("本地缓存写入失败。", "存储空间可能不足，请导出备份后重启应用。", true)
        }
    }

    private fun writeOwn(e: OwnEntry) {
        val r = repo
        if (useDb && r != null) r.saveOwnRow(e) else persistPrefs()
    }

    private fun writeLib(e: LibEntry) {
        val r = repo
        if (useDb && r != null) r.saveLibRow(e) else persistPrefs()
    }

    fun saveAll() {
        persist()
        bump()
    }

    /** 清掉材料目录内容、草稿与 prefs 旧快照（#14：清空要清干净） */
    private fun wipeLocalArtifacts(context: Context?) {
        try {
            context?.let { ctx ->
                val dir = java.io.File(ctx.filesDir, "materials")
                dir.listFiles()?.forEach { child ->
                    try { if (child.isDirectory) com.juxia.app.services.RestoreJournal.removeDir(child.absolutePath) else child.delete() } catch (_: Exception) {}
                }
                java.io.File(ctx.filesDir, "juxia_legacy_backup.db").delete()
                java.io.File(ctx.filesDir, ".material-repair-v1").delete()
            }
        } catch (e: Exception) {}
        prefs?.let { p ->
            val ed = p.edit()
            p.all.keys.filter { it.startsWith("draft_") }.forEach { ed.remove(it) }
            // 清空/恢复后不能让旧 appdata_v2 在数据库故障时复活旧数据。
            ed.remove("appdata_v2")
            ed.apply()
        }
    }

    /** 全量重置（清空/恢复后用）：内存先切，写库失败回滚内存 */
    suspend fun resetAll(next: AppData) {
        val r = repo
        if (!useDb || r == null) {
            data = next
            normalize()
            wipeLocalArtifacts(null)
            persistPrefsNow(fallbackToken)
            bump()
            return
        }
        r.flush()
        val previous = data
        val token = fallbackToken
        data = next
        normalize()
        try {
            r.replaceAll(next, token)
        } catch (e: Exception) {
            data = previous
            throw e
        }
        bump()
    }

    /** 清空全部：公开入口（UI 用），附带本机痕迹清理 */
    suspend fun wipeAll(context: Context?, next: AppData = AppData()) {
        // 先提交空数据；数据库失败时不能先删材料文件
        resetAll(next)
        // 无数据库模式由 resetAll 自己清理 prefs；有数据库时才在这里清旧文件
        if (useDb) wipeLocalArtifacts(context)
    }

    /** 恢复路径：换数据 + 换新 restore token */
    suspend fun replaceAll(d: AppData, restoreToken: String) {
        fallbackToken = restoreToken
        val r = repo
        if (useDb && r != null) {
            r.replaceAll(d, restoreToken)
            data = d
        } else {
            data = d
            persistPrefsNow(restoreToken)
        }
        normalize()
        bump()
    }

    suspend fun restoreToken(): String {
        val r = repo
        return if (useDb && r != null) r.restoreToken() else fallbackToken
    }

    suspend fun flush() {
        repo?.flush()
        val p = prefs
        if (p != null) {
            try {
                // SharedPreferences apply() 本身异步落盘，这里只保证 prefsJob 已发出
                prefsJob?.join()
            } catch (_: Exception) {}
        }
    }

    // ---------- 通用状态 ----------

    fun bump() {
        UiState.bump()
    }

    fun recordOpen() {
        val t = todayStr()
        if (!data.meta.openDays.contains(t)) {
            data.meta.openDays.add(t)
            data.meta.openDays.sort()
            saveKv()
        }
    }

    fun rollDay() {
        recordOpen()
        if (data.day.date != todayStr()) {
            data.day = com.juxia.app.model.DayState(date = todayStr())
            saveKv()
        }
    }

    fun dayCount(): Int = maxOf(1, data.meta.openDays.size)

    fun markDrew() {
        data.day.drew = true
        saveKv()
        bump()
    }

    fun ownActive(kind: String): List<OwnEntry> =
        data.own.filter { it.kind == kind && !it.isArchived() }

    fun archived(): List<OwnEntry> =
        data.own.filter { it.isArchived() }.sortedByDescending { it.archAt }

    // 对齐鸿蒙：只顺延"到期日早于今天"的回访——移到今天（或明天的同一回访时刻）
    fun postponeMissedRevisits(now: Long): Int {
        val today = todayStr()
        var moved = 0
        for (e in data.own) {
            if (!e.isArchived()) continue   // 对齐鸿蒙：只顺延已归档的回访
            if (e.revisitAt <= 0 || e.revisitAt > now) continue
            if (e.snoozeUntil > now) continue
            if (todayStr(java.util.Date(e.revisitAt)) >= today) continue
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.HOUR_OF_DAY, data.settings.revisitHour)
            cal.set(java.util.Calendar.MINUTE, data.settings.revisitMinute)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            if (cal.timeInMillis <= now) cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
            e.revisitAt = cal.timeInMillis
            e.snoozeUntil = 0
            writeOwn(e)
            moved++
        }
        if (moved > 0) {
            persist()
            bump()
        }
        return moved
    }

    fun revisitDue(now: Long): List<OwnEntry> =
        data.own.filter {
            it.isArchived() && it.revisitAt > 0 && it.revisitAt <= now &&
                (it.snoozeUntil == 0L || it.snoozeUntil <= now)
        }.sortedBy { it.revisitAt }

    fun dislikedSet(): Set<String> = data.dislikes.map { it.text }.toSet()

    fun libPool(): List<LibEntry> {
        val dis = dislikedSet()
        return data.lib.filter { !dis.contains(it.text) }
    }

    // ---------- 增删改 ----------

    fun addOwn(kind: String, text: String): OwnEntry {
        val e = OwnEntry(id = newId(), kind = kind, text = text, createdAt = System.currentTimeMillis())
        data.own.add(0, e)
        // 对齐鸿蒙 addOwn：写入即标记今天写过
        data.day.wrote = true
        writeOwn(e)
        persist()
        bump()
        return e
    }

    fun addReply(sourceId: String, text: String, from: String = ""): Boolean {
        val body = text.trim()
        if (body.isEmpty()) return false
        val e = OwnEntry(
            id = newId(), kind = "reply", text = body,
            createdAt = System.currentTimeMillis(), replyToId = sourceId, replyFrom = from
        )
        data.own.add(0, e)
        writeOwn(e)
        bump()
        return true
    }

    fun repliesOf(ownId: String): List<OwnEntry> =
        data.own.filter { it.replyToId == ownId }.sortedBy { it.createdAt }

    fun addReflect(text: String): OwnEntry? {
        val body = text.trim()
        if (body.isEmpty()) return null
        val e = OwnEntry(id = newId(), kind = "reflect", text = body, createdAt = System.currentTimeMillis())
        data.own.add(0, e)
        writeOwn(e)
        persist()
        bump()
        return e
    }

    fun reflects(): List<OwnEntry> =
        data.own.filter { it.kind == "reflect" }.sortedByDescending { it.createdAt }

    fun updateOwnText(id: String, text: String): Boolean {
        val body = text.trim()
        if (body.isEmpty()) return false
        val e = data.own.find { it.id == id } ?: return false
        e.text = body
        writeOwn(e)
        bump()
        return true
    }

    fun addLib(text: String, source: String, origin: String = "material", tag: String = "原文"): Boolean {
        if (data.lib.any { it.text == text }) return false
        val e = LibEntry(id = newId(), text = text, source = source, origin = origin, tag = tag, createdAt = System.currentTimeMillis())
        data.lib.add(0, e)
        writeLib(e)
        bump()
        return true
    }

    fun addDislike(text: String, source: String, origin: String) {
        val body = text.trim()
        if (body.isEmpty()) return
        if (data.dislikes.any { it.text == body }) return
        val d = DislikeEntry(text = body, source = source, origin = origin, at = System.currentTimeMillis())
        data.dislikes.add(0, d)
        repo?.saveDislikeRow(d)
        // 同文句库条目一并移出，避免"不喜欢了却还在句库"
        val removed = data.lib.filter { it.text == body }
        data.lib.removeAll { it.text == body }
        removed.forEach { repo?.deleteLibRow(it.id) }
        persist()
        bump()
    }

    fun removeDislike(text: String) {
        data.dislikes.removeAll { it.text == text }
        repo?.deleteDislikeRow(text)
        persist()
        bump()
    }

    fun addMaterial(name: String, text: String): MaterialEntry {
        val m = MaterialEntry(id = newId(), name = name, text = text, size = text.length.toLong(), createdAt = System.currentTimeMillis())
        data.materials.add(m)
        persist()
        bump()
        return m
    }

    fun addMaterialFile(name: String, path: String, size: Long): MaterialEntry {
        val m = MaterialEntry(id = newId(), name = name, path = path, size = size, createdAt = System.currentTimeMillis())
        data.materials.add(m)
        persist()
        bump()
        return m
    }

    // ---------- 材料 ----------

    suspend fun reindexMaterial(id: String, text: String): Boolean {
        val r = repo ?: return false
        val sents = splitSentences(text)
        if (sents.isEmpty()) return false
        return r.replaceSentences(id, sents)
    }

    suspend fun reindexFile(id: String): Boolean {
        clearMaterialIndex(id)
        return indexMaterial(id)
    }

    suspend fun indexMaterial(id: String): Boolean {
        val m = data.materials.find { it.id == id } ?: return false
        return try {
            val sents = if (m.path.isEmpty()) {
                com.juxia.app.utils.splitSentences(m.text)
            } else {
                com.juxia.app.utils.splitSentences(MaterialIndexer.readText(m.path))
            }
            if (sents.isEmpty()) return false
            val written = appendMaterialSentences(id, 0, sents)
            // 二轮#9：写入数不足即失败（Repo 内部 catch 会吞底层异常，只看结果）
            written >= sents.size
        } catch (e: Exception) {
            AppError.report("材料读取失败。", "该文件可能已不存在；原记录已保留。")
            false
        }
    }

    suspend fun materialSentences(id: String): List<String> = repo?.allSentences(id) ?: emptyList()

    suspend fun searchMaterial(keywords: List<String>, materialId: String = ""): List<String> =
        repo?.searchSentences(keywords, materialId) ?: emptyList()

    suspend fun appendMaterialSentences(id: String, startOrd: Int, sents: List<String>): Int {
        val written = repo?.appendSentences(id, startOrd, sents) ?: 0
        bump()
        return written
    }

    suspend fun clearMaterialIndex(id: String) {
        repo?.clearSentences(id)
    }

    fun updateMaterial(id: String, name: String, text: String) {
        val m = data.materials.find { it.id == id } ?: return
        m.name = name
        m.text = text
        // 编辑后正文以内嵌 text 为准，旧 path 不能再优先
        m.path = ""
        m.size = text.length.toLong()
        persist()
        bump()
    }

    fun attachMaterialFile(id: String, name: String, path: String, size: Long) {
        val m = data.materials.find { it.id == id } ?: return
        m.name = name
        m.path = path
        m.size = size
        persist()
        bump()
    }

    suspend fun deleteMaterial(id: String) {
        data.materials.removeAll { it.id == id }
        clearMaterialIndex(id)
        repo?.deleteMaterialRow(id)
        persist()
        bump()
    }

    // ---------- 背景 ----------

    fun setBackgroundPath(key: String, path: String) {
        val b = data.settings.background
        // 二轮#8：经典读写都走 b.light/b.dark（与 UiState.bgStyleFor 一致）；
        // lightClassic/darkClassic 为模型兼容字段，不参与主链路
        val target = when (key) {
            "light" -> b.light
            "dark" -> b.dark
            "lightClassic" -> b.lightClassic
            "lightPlain" -> b.lightPlain
            "darkClassic" -> b.darkClassic
            else -> b.darkPlain
        }
        target.path = path
        persist()
        bump()
    }

    // ---------- 归档 / 备注 / 关联 ----------

    fun catLabel(cat: String): String = when (cat) {
        "resolved" -> "已解决"
        "letgo" -> "已放下"
        "silly" -> "看起来很蠢"
        "tired" -> "听腻了"
        else -> cat
    }

    private fun footPrefix(w: OwnEntry): String = "它曾陪我度过「" + w.text + "」"

    private fun footLine(w: OwnEntry): String =
        footPrefix(w) + "，那件事于 " + fmtMD(w.archAt) + " 标记为「" + catLabel(w.archCat) + "」。"

    /** 页面展示用：foot 即冻结的历史行 */
    fun footLines(e: OwnEntry): List<String> = e.foot

    // 前缀 → 伤口条目 id（只对已归档的绑定）
    private fun footLineMap(e: OwnEntry): Map<String, String> {
        val map = HashMap<String, String>()
        for (bid in e.bindIds) {
            val w = data.own.find { it.id == bid } ?: continue
            if (w.isArchived()) map[footPrefix(w)] = w.id
        }
        return map
    }

    private fun buildFoot(e: OwnEntry): List<String> =
        e.bindIds.mapNotNull { bid ->
            data.own.find { it.id == bid && it.isArchived() }
        }.map { footLine(it) }

    private fun addOrUpdateFootForWound(w: OwnEntry) {
        val line = footLine(w)
        for (e in data.own) {
            if (e.kind != "encourage" || !e.bindIds.contains(w.id)) continue
            val prefix = footPrefix(w)
            val idx = e.foot.indexOfFirst { it.startsWith(prefix) }
            if (idx >= 0) {
                if (e.foot[idx] != line) {
                    e.foot[idx] = line
                    if (idx < e.footIds.size) e.footIds[idx] = w.id else e.footIds.add(w.id)
                    writeOwn(e)
                }
            } else {
                e.foot.add(line)
                e.footIds.add(w.id)
                writeOwn(e)
            }
        }
    }

    // 取消关联 / 复活：foot 文本保留（历史不改写），id 标记为未知
    private fun removeFootForWound(w: OwnEntry, deleteLine: Boolean = false) {
        val prefix = footPrefix(w)
        for (e in data.own) {
            if (e.kind != "encourage") continue
            var changed = false
            if (deleteLine) {
                val idx = e.foot.indexOfFirst { it.startsWith(prefix) }
                if (idx >= 0 && idx < e.footIds.size && e.footIds[idx] == w.id) {
                    e.foot.removeAt(idx)
                    e.footIds.removeAt(idx)
                    changed = true
                }
            } else {
                for (i in e.foot.indices) {
                    if (e.foot[i].startsWith(prefix) && i < e.footIds.size && e.footIds[i] == w.id) {
                        e.footIds[i] = FOOT_UNKNOWN
                        changed = true
                    }
                }
            }
            if (changed) writeOwn(e)
        }
    }

    fun archiveOwn(id: String, cat: String, note: String, revisit: Boolean) {
        val e = data.own.find { it.id == id } ?: return
        e.archCat = cat
        e.archNote = note
        e.archAt = System.currentTimeMillis()
        if (e.kind == "wound" && revisit) {
            e.revisitAt = revisitAtFromDays(data.settings.revisitDays, data.settings.revisitHour, data.settings.revisitMinute)
        } else {
            e.revisitAt = 0
            e.snoozeUntil = 0
        }
        if (e.kind == "wound") addOrUpdateFootForWound(e)
        writeOwn(e)
        persist()
        bump()
    }

    fun addNote(id: String, text: String) {
        val e = data.own.find { it.id == id } ?: return
        e.notes.add(NoteItem(at = System.currentTimeMillis(), text = text))
        writeOwn(e)
        bump()
    }

    fun setNote(id: String, text: String): Boolean {
        val e = data.own.find { it.id == id } ?: return false
        // 对齐鸿蒙：备注是一条条追加的历史，不是覆盖一个字段。
        if (e.notes.isNotEmpty()) {
            e.notes[e.notes.size - 1].text = text
            e.notes[e.notes.size - 1].at = System.currentTimeMillis()
        } else {
            e.notes.add(NoteItem(at = System.currentTimeMillis(), text = text))
        }
        e.note = ""
        writeOwn(e)
        bump()
        return true
    }

    fun toggleBind(ownId: String, woundId: String): Boolean {
        val e = data.own.find { it.id == ownId } ?: return false
        e.bindIds = e.bindIds ?: mutableListOf()
        val i = e.bindIds.indexOf(woundId)
        return if (i >= 0) {
            e.bindIds.removeAt(i)
            data.own.find { it.id == woundId }?.let { removeFootForWound(it) }
            writeOwn(e); bump()
            false
        } else {
            e.bindIds.add(woundId)
            data.own.find { it.id == woundId }?.let { if (it.isArchived()) addOrUpdateFootForWound(it) }
            writeOwn(e); bump()
            true
        }
    }

    fun toggleLibBind(libId: String, ownId: String): Boolean {
        val e = data.lib.find { it.id == libId } ?: return false
        val i = e.bindIds.indexOf(ownId)
        return if (i >= 0) {
            e.bindIds.removeAt(i)
            writeLib(e); bump()
            false
        } else {
            e.bindIds.add(ownId)
            writeLib(e); bump()
            true
        }
    }

    fun libBoundTo(libId: String): List<String> =
        data.lib.find { it.id == libId }?.bindIds ?: emptyList()

    fun removeLib(id: String) {
        data.lib.removeAll { it.id == id }
        repo?.deleteLibRow(id)
        persist()
        bump()
    }

    fun removeOwn(id: String) {
        val e = data.own.find { it.id == id } ?: return
        // 他人 bindIds 清理
        for (o in data.own) {
            if (o.bindIds.remove(id)) writeOwn(o)
        }
        // lib.bindIds 清理
        for (l in data.lib) {
            if (l.bindIds.remove(id)) writeLib(l)
        }
        // 回信改为"原句已删除"兜底显示
        for (r in data.own) {
            if (r.replyToId == id) {
                r.replyToId = ""
                writeOwn(r)
            }
        }
        if (e.isArchived() && e.kind == "wound") removeFootForWound(e)
        data.own.removeAll { it.id == id }
        repo?.deleteOwnRow(id)
        clearDraft("note_$id")
        persist()
        bump()
    }

    fun removeLatestNote(id: String) {
        val e = data.own.find { it.id == id } ?: return
        if (e.notes.isNotEmpty()) {
            e.notes.removeAt(e.notes.size - 1)
            e.note = ""
            writeOwn(e)
            bump()
        }
    }

    fun revive(id: String) {
        val e = data.own.find { it.id == id } ?: return
        e.archCat = ""
        e.archNote = ""
        e.archAt = 0
        e.revisitAt = 0
        e.snoozeUntil = 0
        if (e.kind == "wound") removeFootForWound(e, deleteLine = true)
        writeOwn(e)
        persist()
        bump()
    }

    fun setRevisit(id: String, days: Int) {
        val e = data.own.find { it.id == id } ?: return
        e.revisitAt = if (days > 0) revisitAtFromDays(days, data.settings.revisitHour, data.settings.revisitMinute) else 0
        if (days <= 0) e.snoozeUntil = 0
        writeOwn(e)
        bump()
    }

    fun setRevisitAt(id: String, ts: Long) {
        val e = data.own.find { it.id == id } ?: return
        e.revisitAt = ts
        writeOwn(e)
        bump()
    }

    fun clearRevisit(id: String) {
        val e = data.own.find { it.id == id } ?: return
        e.revisitAt = 0
        e.snoozeUntil = 0
        writeOwn(e)
        bump()
    }

    fun snoozeRevisit(id: String, days: Int) {
        val e = data.own.find { it.id == id } ?: return
        // 与鸿蒙版 wait() 一致：两个字段一起后移，归档区倒计时显示正确
        val until = System.currentTimeMillis() + days.toLong() * DAY_MS
        e.revisitAt = until
        e.snoozeUntil = until
        writeOwn(e)
        bump()
    }

    // ---------- 草稿与引导 ----------

    fun saveKv() {
        val r = repo
        if (useDb && r != null) r.saveKv(data) else persistPrefs()
    }

    fun saveSettings() {
        persist()
        bump()
    }

    fun guideDone(): Boolean {
        val p = prefs ?: return false
        return try {
            p.getBoolean("guide_done", false)
        } catch (e: Exception) {
            false
        }
    }

    fun markGuideDone() {
        prefs?.edit()?.putBoolean("guide_done", true)?.apply()
    }

    fun saveDraft(key: String, text: String) {
        prefs?.edit()
            ?.putString("draft_" + key, text)
            ?.putString("draft_date_" + key, todayStr())
            ?.apply()
    }

    fun loadDraft(key: String): String {
        val p = prefs ?: return ""
        return try {
            val day = p.getString("draft_date_" + key, "") ?: ""
            if (day != todayStr()) {
                clearDraft(key)
                ""
            } else {
                p.getString("draft_" + key, "") ?: ""
            }
        } catch (e: Exception) {
            ""
        }
    }

    fun clearDraft(key: String) {
        prefs?.edit()
            ?.remove("draft_" + key)
            ?.remove("draft_date_" + key)
            ?.apply()
    }

    companion object {
        const val FOOT_UNKNOWN = "__foot_unknown__"
        /** 全局唯一实例（对应鸿蒙版 Store.get() 单例） */
        val instance = Store()
    }
}
