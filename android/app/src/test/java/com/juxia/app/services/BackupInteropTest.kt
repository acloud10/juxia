package com.juxia.app.services

import com.juxia.app.model.AppData
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * 跨端备份互通的纯 JVM 测试。
 *
 * 用**手工构造**的鸿蒙格式备份包（juxia-full v3 + data.json + materials/<id>.txt + backgrounds/<key>.jpg）
 * 验证安卓端的读取链路，而不是用安卓自己写出来的包自证——这样才能证明「鸿蒙导出 → 安卓导入」这一步。
 */
class BackupInteropTest {

    private fun sha(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun zipOf(entries: List<Pair<String, ByteArray>>): File {
        val f = File.createTempFile("juxia-interop", ".zip")
        ZipOutputStream(f.outputStream()).use { zos ->
            entries.forEach { (name, bytes) ->
                zos.putNextEntry(ZipEntry(name))
                zos.write(bytes)
                zos.closeEntry()
            }
        }
        return f
    }

    /** 鸿蒙 1.0.5 导出的那种包：清单是 juxia-full v3，材料清单在 data.json 里，背景按槽位名 */
    private fun harmonyStyleZip(materialText: String = "第一句。第二句。", bgBytes: ByteArray = byteArrayOf(1, 2, 3, 4)): File {
        val data = AppData().apply {
            // 旧设备绝对路径：跨设备必须被重映射掉
            settings.background.light.path = "/data/storage/el2/base/files/backgrounds/light.jpg"
            materials.add(
                com.juxia.app.model.MaterialEntry(
                    id = "m1", name = "测试材料", text = "", path = "/old/device/m1.txt",
                    size = materialText.toByteArray(Charsets.UTF_8).size.toLong(), createdAt = 1731600000000
                )
            )
        }
        val json = kotlinx.serialization.json.Json { encodeDefaults = true }
        val dataBytes = json.encodeToString(AppData.serializer(), data).toByteArray(Charsets.UTF_8)
        val matBytes = materialText.toByteArray(Charsets.UTF_8)

        val manifest = """
            {"format":"juxia-full","version":3,"createdAt":1731600000000,
             "dataBytes":${dataBytes.size},"dataSha256":"${sha(dataBytes)}",
             "materialCount":1,
             "materials":[{"id":"m1","bytes":${matBytes.size},"sha256":"${sha(matBytes)}"}],
             "backgrounds":[{"key":"light","bytes":${bgBytes.size},"sha256":"${sha(bgBytes)}"}],
             "includeMaterials":true}
        """.trimIndent().toByteArray(Charsets.UTF_8)

        return zipOf(
            listOf(
                "manifest.json" to manifest,
                "data.json" to dataBytes,
                "materials/m1.txt" to matBytes,
                "backgrounds/light.jpg" to bgBytes
            )
        )
    }

    @Test
    fun readsHarmonyStyleBackup() = runBlocking {
        val f = harmonyStyleZip()
        try {
            ZipFile(f).use { zip ->
                val m = BackupOps.verifyFullManifest(zip)
                assertEquals(BackupOps.FORMAT_FULL, m.format)
                assertEquals(3, m.version)
                assertEquals(1, m.materialCount)
                assertEquals("m1", m.materials[0].id)
                assertEquals("light", m.backgrounds[0].key)
            }
            val payload = BackupOps.parseBackup(f)
            try {
                assertTrue("应识别为鸿蒙格式", payload.hfFormat)
                assertEquals(1, payload.data.materials.size)
                assertEquals("测试材料", payload.data.materials[0].name)
                assertTrue("材料文件应被解出", payload.hasMaterials)
                assertNotNull("材料载荷应落临时文件", payload.materialsFiles["m1"])
                assertNotNull("背景应按 key 解出", payload.bgKeyFiles["light"])
                assertEquals(4L, payload.bgKeyFiles["light"]!!.length())
            } finally {
                payload.cleanup()
            }
        } finally {
            f.delete()
        }
    }

    /** 鸿蒙早期/安卓 1.0.4 之前的旧清单：juxia-backup-manifest + entries[] 也要能读 */
    @Test
    fun readsLegacyStyleBackup() = runBlocking {
        val json = kotlinx.serialization.json.Json { encodeDefaults = true }
        val dataBytes = json.encodeToString(AppData.serializer(), AppData()).toByteArray(Charsets.UTF_8)
        val manifest = """
            {"format":"juxia-backup-manifest","version":2,
             "entries":[{"name":"data.json","size":${dataBytes.size},"sha256":"${sha(dataBytes)}"}],
             "note":""}
        """.trimIndent().toByteArray(Charsets.UTF_8)
        val f = zipOf(listOf("manifest.json" to manifest, "data.json" to dataBytes))
        try {
            val payload = BackupOps.parseBackup(f)
            try {
                assertEquals(false, payload.hfFormat)
                assertTrue(payload.data.materials.isEmpty())
            } finally {
                payload.cleanup()
            }
        } finally {
            f.delete()
        }
    }

    /** 清单里的 sha 对不上必须拒绝（防止半截/被改过的包） */
    @Test
    fun rejectsTamperedPayload() {
        val f = harmonyStyleZip()
        try {
            // 改掉 materials/m1.txt 的内容，manifest 里的 sha256 就对不上了
            val tampered = zipOf(
                listOf(
                    "manifest.json" to readEntry(f, "manifest.json"),
                    "data.json" to readEntry(f, "data.json"),
                    "materials/m1.txt" to "被改过的内容".toByteArray(Charsets.UTF_8),
                    "backgrounds/light.jpg" to readEntry(f, "backgrounds/light.jpg")
                )
            )
            try {
                ZipFile(tampered).use { zip -> BackupOps.verifyFullManifest(zip) }
                fail("应当拒绝 sha 不一致的包")
            } catch (e: Exception) {
                assertTrue(e.message ?: "", (e.message ?: "").isNotEmpty())
            } finally {
                tampered.delete()
            }
        } finally {
            f.delete()
        }
    }

    /** 未知 format 必须拒绝，不能默默当成本端格式 */
    @Test
    fun rejectsUnknownFormat() {
        val json = kotlinx.serialization.json.Json { encodeDefaults = true }
        val dataBytes = json.encodeToString(AppData.serializer(), AppData()).toByteArray(Charsets.UTF_8)
        val manifest = """{"format":"someone-else","version":9,"entries":[]}""".toByteArray(Charsets.UTF_8)
        val f = zipOf(listOf("manifest.json" to manifest, "data.json" to dataBytes))
        try {
            ZipFile(f).use { zip ->
                try {
                    BackupOps.verifyFullManifest(zip)
                    fail("应当拒绝未知 format")
                } catch (e: Exception) {
                    assertTrue(true)
                }
            }
        } finally {
            f.delete()
        }
    }

    private fun readEntry(zipFile: File, name: String): ByteArray =
        ZipFile(zipFile).use { zip ->
            val e = zip.getEntry(name)
            zip.getInputStream(e).use { it.readBytes() }
        }
}
