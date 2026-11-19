package com.juxia.app.services

import android.content.Context
import com.juxia.app.data.Store
import com.juxia.app.model.AppData
import com.juxia.app.model.MaterialEntry
import com.juxia.app.utils.splitSentences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

// 句栖 · 备份引擎（翻译自 SettingsPage.ets 的备份/恢复段，拆分为独立服务）
// 页面只留 UI；这里是 manifest 校验、暂存、两阶段恢复、材料包与孤儿清理的全部逻辑。
object BackupOps {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    class BackupException(message: String) : Exception(message)

    // 与鸿蒙版逐字对齐的引擎错误族
    object Err {
        const val LIST_CORRUPT = "备份清单损坏"
        const val LIST_VERSION = "备份清单版本不兼容"
        const val CHECK_SIZE = "备份校验失败：数据大小不一致"
        const val CHECK_DATA = "备份校验失败：数据校验不一致"
        const val CHECK_DATA_READ = "备份校验失败：无法读取数据"
        const val CHECK_MAT_COUNT = "备份校验失败：材料数量不一致"
        const val CHECK_MAT = "备份校验失败：材料校验不一致"
        const val CHECK_MAT_MISSING = "备份校验失败：材料缺失"
        const val CHECK_BG_MISSING = "备份校验失败：背景图缺失"
        const val CHECK_BG = "备份校验失败：背景图校验不一致"
        const val MK_MAT_DIR = "创建材料目录失败"
        const val MK_BG_DIR = "创建背景目录失败"
        const val COPY_FILE = "复制文件失败"
        const val WRITE_LIST = "写入备份清单失败"
        const val NOT_SJ4 = "不是 SJ4"
    }

    // ---------- 数据类 ----------

    @Serializable
    data class ManifestEntry(var name: String = "", var size: Long = 0, var sha256: String = "")

    /** 鸿蒙 juxia-full 清单里的材料条目：materials[{id,bytes,sha256}] */
    @Serializable
    data class HfMaterial(var id: String = "", var bytes: Long = 0, var sha256: String = "")

    /** 鸿蒙 juxia-full 清单里的背景条目：backgrounds[{key,bytes,sha256}]，文件名为 <key>.jpg */
    @Serializable
    data class HfBackground(var key: String = "", var bytes: Long = 0, var sha256: String = "")

    /** 完整备份清单。
     *  写出：按鸿蒙 `juxia-full` v3 布局（dataBytes/dataSha256/materialCount/materials/backgrounds，
     *       背景用六槽位名 <key>.jpg），鸿蒙端可直接导入安卓产物；
     *       同时保留 entries[] 供本端逐文件校验。
     *  读取：`juxia-full` v1..v3 与旧的 `juxia-backup-manifest` v1..v3 都接受。 */
    @Serializable
    data class FullManifest(
        var format: String = FORMAT_FULL,
        var version: Int = 3,
        var createdAt: Long = 0,
        var dataBytes: Long = 0,
        var dataSha256: String = "",
        var materialCount: Int = 0,
        var materials: MutableList<HfMaterial> = mutableListOf(),
        var backgrounds: MutableList<HfBackground> = mutableListOf(),
        var includeMaterials: Boolean = false,
        var entries: MutableList<ManifestEntry> = mutableListOf(),
        var note: String = ""
    )

    @Serializable
    private data class MaterialsPayload(var materials: MutableList<MaterialEntry> = mutableListOf())

    /** 校验后的备份载荷（#16：文件载荷走临时目录，不进内存） */
    data class BackupPayload(
        var data: AppData = AppData(),
        var materials: MutableList<MaterialEntry> = mutableListOf(),
        var backgrounds: MutableList<String> = mutableListOf(),
        var hasMaterials: Boolean = false,
        var materialsFiles: MutableMap<String, File> = mutableMapOf(),
        /** 旧格式（backgrounds.json + bg_* 文件名）：暂存名 → 临时文件 */
        var backgroundFiles: MutableMap<String, File> = mutableMapOf(),
        /** 鸿蒙格式（backgrounds/<key>.jpg）：槽位 key → 临时文件 */
        var bgKeyFiles: MutableMap<String, File> = mutableMapOf(),
        /** 本次载荷是否来自鸿蒙 juxia-full 清单（决定背景路径要不要整体重映射） */
        var hfFormat: Boolean = false,
        var tempDir: File? = null,
    ) {
        fun cleanup() {
            tempDir?.let { RestoreJournal.removeDir(it.absolutePath) }
            tempDir = null
            materialsFiles = mutableMapOf()
            backgroundFiles = mutableMapOf()
            bgKeyFiles = mutableMapOf()
        }
    }

    /** 单条目体积上限（zip bomb 防线；中央目录即给出解压后大小，不解压即可预检） */
    private const val MAX_ENTRY_BYTES = 64L * 1024 * 1024
    private const val MAX_BACKUP_BYTES = 256L * 1024 * 1024

    /** 鸿蒙版清单标识（1.0.4 起本端也写成这个，保证跨端可导入） */
    const val FORMAT_FULL = "juxia-full"

    /** 本端 1.0.4 之前用的清单标识，仍要能读 */
    const val FORMAT_LEGACY = "juxia-backup-manifest"

    /** 背景六槽位与鸿蒙 backgrounds/<key>.jpg 的 key 一一对应 */
    private val BG_KEYS = listOf("light", "dark", "lightClassic", "lightPlain", "darkClassic", "darkPlain")

    // ---------- 工具 ----------

    /** 与鸿蒙 assertFreeSpace 对齐：磁盘余量动态预检（不设固定天花板，按实际剩余判断） */
    private const val MIN_FREE_RESERVE_BYTES = 64L * 1024 * 1024

    fun freeBytes(dir: java.io.File): Long = try {
        val stat = android.os.StatFs(dir.absolutePath)
        stat.availableBytes
    } catch (e: Exception) {
        -1L
    }

    /** 余量不足抛 NOT_ENOUGH_SPACE（UI 已有人话文案："恢复/导出需要…临时空间"） */
    fun assertFreeSpace(dir: java.io.File, needBytes: Long) {
        val free = freeBytes(dir)
        if (free >= 0 && free < needBytes + MIN_FREE_RESERVE_BYTES) {
            throw BackupException("NOT_ENOUGH_SPACE")
        }
    }

    /** zip 解压后总大小（读中央目录，不解压——对齐鸿蒙 zlib.getOriginalSize） */
    fun zipDecompressedSize(zipFile: java.io.File): Long = try {
        val zip = java.util.zip.ZipFile(zipFile)
        var total = 0L
        val en = zip.entries()
        while (en.hasMoreElements()) {
            val e = en.nextElement()
            if (!e.isDirectory) total += e.size
        }
        zip.close()
        total
    } catch (e: Exception) {
        0L
    }

    // 弱密语黑名单（移植自 HTML 版；#17：密语强度最低防线）
    private val PW_BLACKLIST = setOf(
        "123456","1234567","12345678","123456789","1234567890","000000","00000000",
        "111111","11111111","666666","66666666","888888","88888888","password","password1",
        "qwerty","qwerty123","abc123","abcd1234","iloveyou","admin123","letmein","welcome",
        "monkey","dragon","5201314","woaini","woaini520","1314520","a123456","123123",
        "112233","qwe123","1q2w3e","1qaz2wsx","zxcvbnm","我爱你","密码"
    )
    fun pwTooWeak(p: String): Boolean {
        val norm = java.text.Normalizer.normalize(p, java.text.Normalizer.Form.NFKC)
        return norm in PW_BLACKLIST || norm.lowercase() in PW_BLACKLIST
    }

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun newRestoreToken(): String =
        System.currentTimeMillis().toString(36) + "-" +
            (1000000000L..9999999999L).random().toString(36)

    fun sameMaterialExists(name: String, size: Long, firstLine: String?): Boolean {
        val st = Store.instance
        for (m in st.data.materials) {
            if (m.name == name && m.size == size) {
                // 首行为空不能直接判重：必须比较首个非空行
                if (firstLine.isNullOrEmpty()) return false
                val head = runCatching {
                    MaterialIndexer.readText(m.path).lines().firstOrNull { it.isNotBlank() }
                }.getOrNull()
                if (head == firstLine) return true
                if (m.text.isNotEmpty()) {
                    val mh = m.text.lines().firstOrNull { it.isNotBlank() }
                    if (mh == firstLine) return true
                }
            }
        }
        return false
    }

    fun newMaterialId(): String = Store.instance.newId()

    // ---------- manifest ----------

    /** 在 zip 里按逻辑名找条目：根目录、"./" 前缀、以及鸿蒙 zlib.compressFile 可能带的一层目录前缀都认。 */
    fun findEntry(zip: ZipFile, name: String): java.util.zip.ZipEntry? {
        zip.getEntry(name)?.let { return it }
        zip.getEntry("./$name")?.let { return it }
        val en = zip.entries()
        while (en.hasMoreElements()) {
            val e = en.nextElement()
            if (e.isDirectory) continue
            val n = e.name.replace('\\', '/')
            if (n.endsWith("/$name")) return e
        }
        return null
    }

    private fun readManifest(entry: java.util.zip.ZipEntry, zip: ZipFile): FullManifest {
        val text = try {
            zip.getInputStream(entry).use { it.readBytes() }.toString(Charsets.UTF_8)
        } catch (e: Exception) {
            throw BackupException(Err.LIST_CORRUPT)
        }
        return try {
            json.decodeFromString(FullManifest.serializer(), text)
        } catch (e: Exception) {
            throw BackupException(Err.LIST_CORRUPT)
        }
    }

    private fun hashEntry(zip: ZipFile, ze: java.util.zip.ZipEntry): Pair<Long, String> {
        val digest = MessageDigest.getInstance("SHA-256")
        var size = 0L
        zip.getInputStream(ze).use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
                size += n
            }
        }
        return size to digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun verifyFullManifest(zip: ZipFile): FullManifest {
        val entry = findEntry(zip, "manifest.json") ?: throw BackupException(Err.LIST_CORRUPT)
        val manifest = readManifest(entry, zip)
        if (manifest.format != FORMAT_FULL && manifest.format != FORMAT_LEGACY) {
            throw BackupException(Err.LIST_CORRUPT)
        }
        // v1 无背景图；v2 材料+背景；v3 新增背景图 —— 三种都要能读。更高版本拒识。
        if (manifest.version < 1 || manifest.version > 3) throw BackupException(Err.LIST_VERSION)

        // 1) 本端 entries[]：逐文件 size + sha256
        for (me in manifest.entries) {
            val ze = findEntry(zip, me.name) ?: throw BackupException(Err.CHECK_MAT_MISSING)
            val (size, sha) = try {
                hashEntry(zip, ze)
            } catch (e: Exception) {
                throw BackupException(Err.CHECK_DATA_READ)
            }
            if (size != me.size) throw BackupException(Err.CHECK_SIZE)
            if (sha != me.sha256) throw BackupException(Err.CHECK_DATA)
        }

        // 2) 鸿蒙 juxia-full：data.json 与每个材料/背景文件逐个核对
        if (manifest.format == FORMAT_FULL) {
            fun check(name: String, expectBytes: Long, expectSha: String) {
                val ze = findEntry(zip, name) ?: throw BackupException(Err.CHECK_MAT_MISSING)
                val (size, sha) = try {
                    hashEntry(zip, ze)
                } catch (e: Exception) {
                    throw BackupException(Err.CHECK_DATA_READ)
                }
                if (expectBytes > 0 && size != expectBytes) throw BackupException(Err.CHECK_SIZE)
                if (expectSha.isNotEmpty() && sha != expectSha) throw BackupException(Err.CHECK_DATA)
            }
            check("data.json", manifest.dataBytes, manifest.dataSha256)
            manifest.materials.forEach { check("materials/${it.id}.txt", it.bytes, it.sha256) }
            manifest.backgrounds.forEach { check("backgrounds/${it.key}.jpg", it.bytes, it.sha256) }
        }
        return manifest
    }

    // ---------- 暂存背景 ----------

    /** 把六个背景槽位分别复制进暂存目录，命名 <key>.jpg —— 与鸿蒙 backgrounds/<key>.jpg 完全一致。
     *  返回 槽位 key → 暂存文件名 映射。 */
    suspend fun stageBackgrounds(ctx: Context, stagingDir: File): Map<String, String> =
        withContext(Dispatchers.IO) {
            val map = LinkedHashMap<String, String>()
            stagingDir.mkdirs()
            val b = Store.instance.data.settings.background
            val slots = mapOf(
                "light" to b.light, "dark" to b.dark,
                "lightClassic" to b.lightClassic, "lightPlain" to b.lightPlain,
                "darkClassic" to b.darkClassic, "darkPlain" to b.darkPlain
            )
            BG_KEYS.forEach { key ->
                val style = slots[key]
                if (style == null || style.path.isEmpty()) return@forEach
                val src = File(style.path)
                if (!src.exists()) return@forEach
                val stagedName = "$key.jpg"
                try {
                    src.inputStream().use { input ->
                        File(stagingDir, stagedName).outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    map[key] = stagedName
                } catch (e: Exception) {
                    // 单张失败不阻塞整体备份
                }
            }
            map
        }

    // ---------- 导出 ----------

    /** 完整备份（#16 流式化）：写到临时 zip 返回文件，调用方用完自行删除。
     *  两遍法：第一遍流式算各条目 size+sha256，manifest 居首写，第二遍流式拷贝。 */
    suspend fun buildFullZip(ctx: Context, includeMaterials: Boolean): Pair<File, Boolean> =
        try {
            buildFullZipOnce(ctx, includeMaterials)
        } finally {
            val staging = File(ctx.cacheDir, "bg_staging")
            if (staging.exists()) runCatching { RestoreJournal.removeDir(staging.absolutePath) }
        }

    private suspend fun buildFullZipOnce(ctx: Context, includeMaterials: Boolean): Pair<File, Boolean> =
        withContext(Dispatchers.IO) {
            val st = Store.instance
            data class Entry(val name: String, val source: () -> java.io.InputStream)

            val mats = if (includeMaterials) st.data.materials else mutableListOf()
            val staging = File(ctx.cacheDir, "bg_staging")
            val staged = stageBackgrounds(ctx, staging)   // key → "<key>.jpg"

            // data.json 的内容要自洽：
            //  · 不含材料时清空 materials（鸿蒙端按 materialCount 校验数量）
            //  · 背景只保留"确实打进去了"的槽位，否则鸿蒙端会因找不到 backgrounds/<key>.jpg 而整包失败
            // 一律拷贝一份再改，避免动到内存里的真实数据（settings 是共享引用，随后会整体替换）
            val exportData = st.data.copy(
                materials = if (includeMaterials) st.data.materials else mutableListOf()
            )
            val bgCopy = com.juxia.app.model.BackgroundStyle.from(exportData.settings.background)
            if (staged["light"] == null) bgCopy.light.path = ""
            if (staged["dark"] == null) bgCopy.dark.path = ""
            if (staged["lightClassic"] == null) bgCopy.lightClassic.path = ""
            if (staged["lightPlain"] == null) bgCopy.lightPlain.path = ""
            if (staged["darkClassic"] == null) bgCopy.darkClassic.path = ""
            if (staged["darkPlain"] == null) bgCopy.darkPlain.path = ""
            exportData.settings = exportData.settings.copy(background = bgCopy)

            val entries = mutableListOf<Entry>()
            entries.add(Entry("data.json") {
                json.encodeToString(AppData.serializer(), exportData).toByteArray(Charsets.UTF_8).inputStream()
            })
            staged.forEach { (key, stagedName) ->
                val f = File(staging, stagedName)
                if (f.exists()) entries.add(Entry("backgrounds/$key.jpg") { f.inputStream() })
            }
            if (includeMaterials) {
                // 对齐鸿蒙：任何一份材料复制不出来就整包不成，避免产出鸿蒙端会拒收的半成品
                // 粘贴型材料没有文件，正文在 m.text；不能只看 path。
                val missing = mats.count {
                    (it.path.isEmpty() || !File(it.path).exists()) && it.text.isEmpty()
                }
                if (missing > 0) throw BackupException("材料复制失败，完整备份未生成。")
                mats.forEach { m ->
                    val file = if (m.path.isNotEmpty() && File(m.path).exists()) File(m.path) else null
                    val textBytes = if (file == null) m.text.toByteArray(Charsets.UTF_8) else null
                    entries.add(Entry("materials/${m.id}.txt") {
                        if (file != null) file.inputStream()
                        else java.io.ByteArrayInputStream(textBytes ?: ByteArray(0))
                    })
                }
            }

            // 第一遍：size + sha256（流式），同时填鸿蒙 juxia-full 需要的字段
            val manifest = FullManifest()
            manifest.createdAt = System.currentTimeMillis()
            manifest.includeMaterials = includeMaterials
            entries.forEach { e ->
                e.source().buffered(64 * 1024).use { input ->
                    val digest = java.security.MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        digest.update(buf, 0, n)
                        size += n
                    }
                    val sha = digest.digest().joinToString("") { "%02x".format(it) }
                    if (size > MAX_ENTRY_BYTES) throw BackupException("备份单条目超过 64MB，未生成。")
                    manifest.entries.add(ManifestEntry(e.name, size, sha))
                    when {
                        e.name == "data.json" -> {
                            manifest.dataBytes = size
                            manifest.dataSha256 = sha
                        }
                        e.name.startsWith("materials/") -> {
                            val id = e.name.removePrefix("materials/").removeSuffix(".txt")
                            manifest.materials.add(HfMaterial(id, size, sha))
                        }
                        e.name.startsWith("backgrounds/") -> {
                            val key = e.name.removePrefix("backgrounds/").removeSuffix(".jpg")
                            manifest.backgrounds.add(HfBackground(key, size, sha))
                        }
                    }
                }
            }
            manifest.materialCount = if (includeMaterials) manifest.materials.size else 0

            val tmp = File.createTempFile("juxia_full", ".zip")
            ZipOutputStream(tmp.outputStream().buffered(64 * 1024)).use { zos ->
                zos.putNextEntry(ZipEntry("manifest.json"))
                zos.write(json.encodeToString(FullManifest.serializer(), manifest).toByteArray(Charsets.UTF_8))
                zos.closeEntry()
                entries.forEach { e ->
                    zos.putNextEntry(ZipEntry(e.name))
                    e.source().buffered(64 * 1024).use { it.copyTo(zos) }
                    zos.closeEntry()
                }
            }
            if (staging.exists()) RestoreJournal.removeDir(staging.absolutePath)
            if (tmp.length() > MAX_BACKUP_BYTES) {
                tmp.delete()
                throw BackupException("备份文件超过 256MB，未生成。")
            }
            tmp to includeMaterials
        }

    /** 兼容旧调用：全量字节（内部走 buildFullZip + 读回；新代码请用 buildFullZip） */
    /** 兼容旧调用：全量字节（内部走 buildFullZip + 读回） */
    suspend fun buildFullPayload(ctx: Context, includeMaterials: Boolean): Pair<ByteArray, Boolean> =
        withContext(Dispatchers.IO) {
            val (f, inc) = buildFullZip(ctx, includeMaterials)
            try { f.readBytes() to inc } finally { f.delete() }
        }

    /** 材料包（不加密，仅材料）。
     *  写出鸿蒙版 juxia-materials 格式：manifest.json({format,version:1,createdAt,items:[{id,name,size}]})
     *  + 平铺 {id}.txt —— 鸿蒙端可直接导入安卓产出的材料包（跨端互通）。
     *  zipPath 用文件写入后再读字节，保持调用方接口不变。 */
    @Serializable
    private data class MatPackItem(var id: String = "", var name: String = "", var size: Long = 0)

    @Serializable
    private data class MatPackManifest(
        var format: String = "juxia-materials",
        var version: Int = 1,
        var createdAt: Long = 0,
        var items: MutableList<MatPackItem> = mutableListOf()
    )

    suspend fun buildMaterialsPayload(ctx: Context): ByteArray =
        withContext(Dispatchers.IO) {
            val st = Store.instance
            val tmp = File.createTempFile("juxia_mats", ".zip")
            try {
                ZipOutputStream(tmp.outputStream().buffered()).use { zos ->
                    val items = mutableListOf<MatPackItem>()
                    st.data.materials.forEach { m ->
                        val srcText: String = if (m.path.isNotEmpty() && File(m.path).exists()) {
                            MaterialIndexer.readText(m.path)
                        } else m.text
                        if (srcText.isEmpty()) return@forEach
                        val bytes = srcText.toByteArray(Charsets.UTF_8)
                        zos.putNextEntry(ZipEntry(m.id + ".txt"))
                        zos.write(bytes)
                        zos.closeEntry()
                        items.add(MatPackItem(m.id, m.name, bytes.size.toLong()))
                    }
                    val manifest = MatPackManifest(createdAt = System.currentTimeMillis(), items = items)
                    zos.putNextEntry(ZipEntry("manifest.json"))
                    zos.write(json.encodeToString(MatPackManifest.serializer(), manifest).toByteArray(Charsets.UTF_8))
                    zos.closeEntry()
                }
                if (tmp.length() > MAX_BACKUP_BYTES) throw BackupException("材料包超过 256MB，未生成。")
                tmp.readBytes()
            } finally {
                tmp.delete()
            }
        }

    /** 材料包导入：去重落盘 + 索引。
     *  返回 Triple(新增, 跳过重复, 失败)——索引失败整份回滚（删记录+删文件），
     *  绝不留下"列表可见但搜不到"的半成品。 */
    /** 材料包载荷（文件引用 + 临时目录） */
    data class MaterialsPack(var materials: MutableList<MaterialEntry> = mutableListOf(),
                             val files: MutableMap<String, File> = mutableMapOf(),
                             var tempDir: File? = null) {
        fun cleanup() { tempDir?.let { RestoreJournal.removeDir(it.absolutePath) }; tempDir = null; files.clear() }
    }

    /** 材料包解析：兼容三种形态（安卓旧 / 鸿蒙 manifest / 鸿蒙裸数组），文件落临时目录 */
    suspend fun parseMaterialsPack(zipFile: File): MaterialsPack =
        withContext(Dispatchers.IO) {
            val zip = ZipFile(zipFile)
            try {
                val pack = MaterialsPack()
                val packDir = File.createTempFile("juxia_packdir", "_d")
                packDir.delete(); packDir.mkdirs()
                pack.tempDir = packDir

                fun extractFor(id: String): File? {
                    val ze = (zip.getEntry("$id.txt") ?: zip.getEntry("./$id.txt")
                        ?: zip.getEntry("materials/$id.txt") ?: zip.getEntry("./materials/$id.txt"))
                        ?: return null
                    if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_MAT)
                    val dest = File(packDir, "pk_$id.txt")
                    zip.getInputStream(ze).use { input ->
                        dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                    }
                    return dest
                }
                fun entryBytes(name: String): ByteArray? =
                    (zip.getEntry(name) ?: zip.getEntry("./$name"))?.let { ze ->
                        if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_MAT)
                        zip.getInputStream(ze).use { it.readBytes() }
                    }

                val mfBytes = entryBytes("manifest.json")
                if (mfBytes != null) {
                    val text = mfBytes.toString(Charsets.UTF_8)
                    if (text.trim().startsWith("[")) {
                        json.decodeFromString(
                            kotlinx.serialization.builtins.ListSerializer(MatPackItem.serializer()), text)
                            .forEach { it2 ->
                                extractFor(it2.id)?.let { f ->
                                    pack.materials.add(MaterialEntry(id = it2.id, name = it2.name,
                                        text = "", path = "", size = it2.size, createdAt = 0))
                                    pack.files[it2.id] = f
                                }
                            }
                    } else {
                        val mf = json.decodeFromString(MatPackManifest.serializer(), text)
                        if (mf.format != "juxia-materials" || mf.version != 1)
                            throw BackupException("材料包版本不兼容")
                        mf.items.forEach { it2 ->
                            extractFor(it2.id)?.let { f ->
                                pack.materials.add(MaterialEntry(id = it2.id, name = it2.name,
                                    text = "", path = "", size = it2.size, createdAt = 0))
                                pack.files[it2.id] = f
                            }
                        }
                    }
                } else {
                    val mp = zip.getEntry("materials.json") ?: zip.getEntry("./materials.json")
                        ?: throw BackupException("材料包格式不正确（缺少 manifest.json / materials.json）")
                    if (mp.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_MAT)
                    pack.materials = json.decodeFromString(MaterialsPayload.serializer(),
                        zip.getInputStream(mp).use { it.readBytes() }.toString(Charsets.UTF_8)).materials
                    for (m in pack.materials) {
                        extractFor(m.id)?.let { pack.files[m.id] = it }
                    }
                }
                zip.close()
                if (pack.materials.isEmpty()) {
                    pack.cleanup()
                    throw BackupException("材料包格式不正确（没有可用条目）")
                }
                pack
            } finally {
                try { zip.close() } catch (_: Exception) {}
                zipFile.delete()
            }
        }

    suspend fun importMaterialsPack(ctx: Context, pack: MaterialsPack): Triple<Int, Int, Int> =
        withContext(Dispatchers.IO) {
            val st = Store.instance
            val dir = File(ctx.filesDir, "materials")
            dir.mkdirs()
            var added = 0
            var skipped = 0
            var failed = 0
            for (m in pack.materials) {
                val src = pack.files[m.id]
                if (src == null || !src.exists()) { skipped++; continue }
                val firstLine = src.inputStream().buffered().use { input ->
                    java.io.BufferedReader(java.io.InputStreamReader(input, Charsets.UTF_8))
                        .lineSequence().firstOrNull { it.isNotBlank() } ?: ""
                }
                if (sameMaterialExists(m.name, src.length(), firstLine)) { skipped++; continue }
                val id = newMaterialId()
                val dest = File(dir, "$id.txt")
                try {
                    src.inputStream().buffered(64 * 1024).use { input ->
                        dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                    }
                } catch (e: Exception) {
                    skipped++
                    continue
                }
                val entry = MaterialEntry(id = id, name = m.name, text = "", path = dest.absolutePath,
                    size = src.length(), createdAt = System.currentTimeMillis())
                // 二轮#13：persist 前先打 .indexing——persist 后、索引前被杀也能被 MaterialRepair 收拾
                MaterialRepair.mark(dest.absolutePath)
                st.data.materials.add(entry)
                st.persist()
                if (!st.indexMaterial(id)) {
                    // 索引失败：整份回滚
                    st.data.materials.removeAll { it.id == id }
                    st.persist()
                    MaterialRepair.clear(dest.absolutePath)
                    try { dest.delete() } catch (_: Exception) {}
                    failed++
                    continue
                }
                MaterialRepair.clear(dest.absolutePath)
                added++
            }
            Triple(added, skipped, failed)
        }

    // ---------- 导入与两阶段恢复 ----------

    /** 解析完整备份（#16：从文件懒读；小 JSON 进内存，文件载荷落临时目录） */
    suspend fun parseBackup(zipFile: File): BackupPayload =
        withContext(Dispatchers.IO) {
            val zip = ZipFile(zipFile)
            val payload = BackupPayload()
            val tmpDir = File.createTempFile("juxia_in", "_dir")
            tmpDir.delete(); tmpDir.mkdirs()
            payload.tempDir = tmpDir
            try {
                val manifest = if (findEntry(zip, "manifest.json") != null) verifyFullManifest(zip) else null

                fun entryBytes(name: String): ByteArray? =
                    findEntry(zip, name)?.let { ze ->
                        if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_SIZE)
                        zip.getInputStream(ze).use { it.readBytes() }
                    }

                payload.data = entryBytes("data.json")?.let {
                    json.decodeFromString(AppData.serializer(), it.toString(Charsets.UTF_8))
                } ?: throw BackupException(Err.CHECK_MAT_MISSING)

                if (manifest != null && manifest.format == FORMAT_FULL && manifest.version >= 3) {
                    val dataMats = payload.data.materials
                    if (!manifest.includeMaterials && dataMats.isNotEmpty()) {
                        throw BackupException(Err.CHECK_MAT_COUNT)
                    }
                    if (manifest.includeMaterials) {
                        if (manifest.materialCount != dataMats.size) throw BackupException(Err.CHECK_MAT_COUNT)
                        val dataIds = dataMats.map { it.id }.toSet()
                        val fileIds = manifest.materials.map { it.id }.toSet()
                        if (dataIds != fileIds) throw BackupException(Err.CHECK_MAT_COUNT)
                    }
                }

                if (manifest != null && manifest.format == FORMAT_FULL) {
                    payload.hfFormat = true
                    // 鸿蒙布局：材料清单在 data.json 的 materials 里，文件是 materials/<id>.txt；
                    // 背景按六槽位文件名 backgrounds/<key>.jpg，靠 manifest.backgrounds 定位。
                    if (manifest.includeMaterials && manifest.materialCount > 0) {
                        payload.materials = payload.data.materials
                        payload.hasMaterials = payload.materials.isNotEmpty()
                    }
                    if (payload.hasMaterials) {
                        for (m in payload.materials) {
                            val ze = findEntry(zip, "materials/${m.id}.txt")
                                ?: throw BackupException(Err.CHECK_MAT_MISSING)
                            if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_MAT)
                            val dest = File(tmpDir, "mat_${m.id}.txt")
                            zip.getInputStream(ze).use { input ->
                                dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                            }
                            payload.materialsFiles[m.id] = dest
                        }
                    }
                    for (bg in manifest.backgrounds) {
                        val ze = findEntry(zip, "backgrounds/${bg.key}.jpg")
                            ?: throw BackupException(Err.CHECK_MAT_MISSING)
                        if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_BG)
                        val dest = File(tmpDir, "bgkey_${bg.key}")
                        zip.getInputStream(ze).use { input ->
                            dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                        }
                        payload.bgKeyFiles[bg.key] = dest
                    }
                } else {
                    // 旧布局（本端 1.0.4 之前）：materials.json / backgrounds.json + bg_* 文件名
                    entryBytes("materials.json")?.let {
                        payload.materials = json.decodeFromString(MaterialsPayload.serializer(),
                            it.toString(Charsets.UTF_8)).materials
                        payload.hasMaterials = true
                    }
                    entryBytes("backgrounds.json")?.let {
                        payload.backgrounds = json.decodeFromString(
                            kotlinx.serialization.builtins.ListSerializer(kotlinx.serialization.serializer<String>()),
                            it.toString(Charsets.UTF_8)).toMutableList()
                    }
                    if (payload.hasMaterials) {
                        for (m in payload.materials) {
                            val ze = findEntry(zip, "materials/${m.id}.txt") ?: continue
                            if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_MAT)
                            val dest = File(tmpDir, "mat_${m.id}.txt")
                            zip.getInputStream(ze).use { input ->
                                dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                            }
                            payload.materialsFiles[m.id] = dest
                        }
                    }
                    for (name in payload.backgrounds) {
                        val ze = findEntry(zip, "backgrounds/$name") ?: continue
                        if (ze.size > MAX_ENTRY_BYTES) throw BackupException(Err.CHECK_BG)
                        val dest = File(tmpDir, "bg_$name")
                        zip.getInputStream(ze).use { input ->
                            dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                        }
                        payload.backgroundFiles[name] = dest
                    }
                }
                payload
            } catch (e: Exception) {
                payload.cleanup()
                throw e
            } finally {
                zip.close()
            }
        }

    /**
     * 两阶段恢复：prepared → staged → db_committed → done。
     * 返回 null 表示成功；失败时恢复工作已完成回滚或留给 RestoreRecovery，返回错误信息。
     */
    suspend fun doRestore(ctx: Context, payload: BackupPayload): String? =
        withContext(Dispatchers.IO) {
            val st = Store.instance
            val token = newRestoreToken()
            val newDir = File(ctx.filesDir, "materials/restore_" + System.currentTimeMillis()).absolutePath
            try {
                // phase: prepared
                RestoreJournal.write(ctx, RestoreJournalData(token = token, phase = "prepared", newDir = newDir))

                // 写材料文件（去重：同名同尺寸同首行 → 沿用现有 id 与文件）
                val finalMaterials = mutableListOf<MaterialEntry>()
                if (!File(newDir).mkdirs()) throw BackupException(Err.MK_MAT_DIR)
                for (m in payload.materials) {
                    val src = payload.materialsFiles[m.id]
                    var entry = m
                    if (src != null) {
                        // 不因"同名同尺寸"跳过：恢复是整库替换，跳过等于把这份材料丢掉
                        val id = newMaterialId()
                        val dest = File(newDir, "$id.txt")
                        try {
                            src.inputStream().buffered(64 * 1024).use { input ->
                                dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                            }
                        } catch (e: Exception) { throw BackupException(Err.COPY_FILE) }
                        entry = MaterialEntry(id = id, name = m.name, text = "", path = dest.absolutePath,
                            size = src.length(), createdAt = m.createdAt)
                    }
                    finalMaterials.add(entry)
                }

                // 背景文件还原
                val bgDir = File(ctx.filesDir, "backgrounds")
                if (!bgDir.mkdirs() && !bgDir.exists()) throw BackupException(Err.MK_BG_DIR)
                // 鸿蒙格式：按六槽位 key 落盘，恢复后直接指向新文件
                val bgKeyPath = mutableMapOf<String, String>()
                for ((key, srcF) in payload.bgKeyFiles) {
                    val dest = File(bgDir, "${key}_" + System.currentTimeMillis() + ".jpg")
                    try {
                        srcF.inputStream().buffered(64 * 1024).use { input ->
                            dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                        }
                    } catch (e: Exception) { continue }
                    bgKeyPath[key] = dest.absolutePath
                }
                // 旧格式：stagedName（bg_*）→ 本地路径
                val bgMap = mutableMapOf<String, String>()
                for ((stagedName, srcF) in payload.backgroundFiles) {
                    val dest = File(bgDir, stagedName.removePrefix("bg_"))
                    try {
                        srcF.inputStream().buffered(64 * 1024).use { input ->
                            dest.outputStream().buffered(64 * 1024).use { output -> input.copyTo(output) }
                        }
                    } catch (e: Exception) { continue }
                    bgMap[stagedName] = dest.absolutePath
                }

                // phase: staged
                RestoreJournal.write(ctx, RestoreJournalData(token = token, phase = "staged", newDir = newDir))

                // 切换目录 + 替换数据
                val next = payload.data
                next.materials = finalMaterials
                val b = next.settings.background
                if (payload.hfFormat) {
                    // 鸿蒙备份里 data.json 的 path 是旧设备的绝对路径，跨设备不可用：先清空再按 key 重新指向
                    // （v1/v2 可能没有 backgrounds[]，这时也要清空，避免留下失效的外机路径）
                    b.light.path = bgKeyPath["light"] ?: ""
                    b.dark.path = bgKeyPath["dark"] ?: ""
                    b.lightClassic.path = bgKeyPath["lightClassic"] ?: ""
                    b.lightPlain.path = bgKeyPath["lightPlain"] ?: ""
                    b.darkClassic.path = bgKeyPath["darkClassic"] ?: ""
                    b.darkPlain.path = bgKeyPath["darkPlain"] ?: ""
                } else {
                    fun remap(style: com.juxia.app.model.BgImageStyle) {
                        if (style.path.isEmpty()) return
                        val staged = "bg_" + File(style.path).name
                        bgMap[staged]?.let { style.path = it }
                    }
                    remap(b.light); remap(b.dark); remap(b.lightClassic); remap(b.lightPlain); remap(b.darkClassic); remap(b.darkPlain)
                }
                Store.instance.replaceAll(next, token)

                // phase: db_committed
                RestoreJournal.write(ctx, RestoreJournalData(token = token, phase = "db_committed", newDir = newDir))

                // 重建索引
                var failed = 0
                for (m in finalMaterials) {
                    if (m.path.isNotEmpty()) {
                        if (!Store.instance.indexMaterial(m.id)) failed++
                    } else if (m.text.isNotEmpty()) {
                        if (!Store.instance.reindexMaterial(m.id, m.text)) failed++
                    }
                }
                if (failed > 0) {
                    return@withContext "恢复完成，但 $failed 份材料索引失败；重启后会自动重试。"
                }
                RestoreJournal.write(ctx, RestoreJournalData(token = token, phase = "done", newDir = newDir))
                payload.cleanup()
                null
            } catch (e: Exception) {
                payload.cleanup()
                val msg = e.message ?: "恢复失败"
                afterRestoreJournalFailure(ctx, msg)
                msg
            }
        }

    /** journal 写失败的边缘态：DB 可能已提交，如实上报让用户重启后续做 */
    private fun afterRestoreJournalFailure(ctx: Context, msg: String) {
        AppError.report("恢复中断。", "数据可能只恢复了一部分；不要继续修改，重启应用后会自动收尾或回滚。", true)
    }

    /** 恢复后清理：丢缺失文件的材料行；目录只保留"当前材料实际所在"的 generation */
    suspend fun pruneMissingMaterials(ctx: Context) {
        val st = Store.instance
        val keep = st.data.materials.filter { (it.path.isNotEmpty() && File(it.path).exists()) || it.text.isNotEmpty() }
        if (keep.size != st.data.materials.size) {
            st.data.materials = keep.toMutableList()
            st.persist()
        }
        // 二轮#6：不能拿 materials 根目录当 keepDir（会把 restore_* 整个删掉）。
        // 收集所有被引用文件的父目录作为保留集。
        val keepDirs = keep.mapNotNull { if (it.path.isNotEmpty()) File(it.path).parentFile?.absolutePath else null }
            .toMutableSet()
        if (keepDirs.isEmpty()) keepDirs.add(File(ctx.filesDir, "materials/restore_none").absolutePath)
        val root = File(ctx.filesDir, "materials")
        try {
            if (!root.exists()) return
            root.listFiles()?.forEach { f ->
                val path = f.absolutePath
                val keepThis = keepDirs.any { kd -> path == kd || path.startsWith(kd + "/") }
                if (keepThis) return@forEach
                try { if (f.isDirectory) RestoreJournal.removeDir(path) else f.delete() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            android.util.Log.e("juxia", "prune materials fail", e)
        }
    }
}
