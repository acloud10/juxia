package com.juxia.app.services

import com.juxia.app.model.AppData
import com.juxia.app.model.OwnEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

// 纯 JVM 测试：javax.crypto + 文件 IO 不需要安卓运行时，Android Studio 里可直接跑
class BackupServiceTest {
    private fun sample(): AppData = AppData().apply {
        own.add(OwnEntry(id = "e1", kind = "encourage", text = "慢慢来，会比较快。我陪你。", createdAt = 1731600000000))
        own.add(OwnEntry(id = "e2", kind = "wound", text = "那件没做完的事", bindIds = mutableListOf("e1")))
        settings.appName = "句栖"
        meta.openDays.add("2026-11-15")
    }

    @Test
    fun sj4Roundtrip() {
        val f = File.createTempFile("juxia", ".sj4")
        try {
            val data = sample()
            BackupService.encryptToFile(f, "只有我知道的密语", kotlinx.serialization.json.Json {
                encodeDefaults = true
            }.encodeToString(AppData.serializer(), data))
            val plain = BackupService.decryptFromFile(f, "只有我知道的密语")
            val back = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                .decodeFromString(AppData.serializer(), plain)
            assertEquals(data.own[0].text, back.own[0].text)
            assertEquals(data.own[1].bindIds, back.own[1].bindIds)
            assertEquals(data.settings.appName, back.settings.appName)
            assertEquals(data.meta.openDays, back.meta.openDays)
            // magic 头校验
            val head = f.readBytes().take(3).toByteArray()
            assertEquals("SJ4", String(head, Charsets.US_ASCII))
        } finally {
            f.delete()
        }
    }

    @Test
    fun wrongPassphraseFails() {
        val f = File.createTempFile("juxia", ".sj4")
        try {
            BackupService.encryptToFile(f, "正确密语", "{}")
            try {
                BackupService.decryptFromFile(f, "错误密语")
                fail("应当抛出密语错误")
            } catch (e: BackupService.BackupException) {
                assertEquals("密语错误或备份文件损坏", e.message)
            }
        } finally {
            f.delete()
        }
    }

    @Test
    fun truncatedFileFails() {
        val f = File.createTempFile("juxia", ".sj4")
        try {
            BackupService.encryptToFile(f, "密语", "{}")
            val raf = java.io.RandomAccessFile(f, "rw")
            raf.setLength(10) // 截断到小于最小合法尺寸
            raf.close()
            try {
                BackupService.decryptFromFile(f, "密语")
                fail("应当抛出不完整")
            } catch (e: BackupService.BackupException) {
                assertEquals("备份文件不完整", e.message)
            }
        } finally {
            f.delete()
        }
    }

    @Test
    fun badMagicFails() {
        val f = File.createTempFile("juxia", ".sj4")
        try {
            f.writeBytes(ByteArray(64) { 0 })
            try {
                BackupService.decryptFromFile(f, "密语")
                fail("应当抛出 magic 不匹配")
            } catch (e: BackupService.BackupException) {
                assertEquals("不是 SJ4 完整加密备份", e.message)
            }
        } finally {
            f.delete()
        }
    }
}
