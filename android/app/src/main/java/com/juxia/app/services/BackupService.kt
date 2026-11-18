package com.juxia.app.services

import com.juxia.app.model.AppData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.io.RandomAccessFile
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import javax.crypto.AEADBadTagException

// 句栖 · SJ4 备份加解密（翻译自 BackupService.ets）
// 格式：magic "SJ4" + 32B salt + 12B IV + AES-256-GCM 流式密文（tag 附在流尾，加密时 doFinal 产出）
// 与鸿蒙版字节级互通：同一密语、同一载荷，两端必须能互相解。
object BackupService {
    private const val MAGIC = "SJ4"
    private const val SALT_LEN = 32
    private const val IV_LEN = 12
    private const val TAG_LEN = 16
    private const val ITERATIONS = 310000
    private const val CHUNK = 64 * 1024

    class BackupException(message: String) : Exception(message)

    // 载荷序列化与鸿蒙版 JSON.stringify 对齐：默认字段也输出，多余字段读时忽略（前向兼容）
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    private fun deriveKey(passphrase: String, salt: ByteArray): SecretKeySpec {
        return try {
            val spec = PBEKeySpec(passphrase.toCharArray(), salt, ITERATIONS, 256)
            val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
        } catch (e: Exception) {
            throw BackupException("派生备份密钥失败：${e.message}")
        }
    }

    /** 加密：data 的 UTF-8 字节流式写入，密文流尾附 GCM tag */
    @Throws(BackupException::class)
    fun encryptToFile(file: File, passphrase: String, data: String) {
        val salt = ByteArray(SALT_LEN).also { SecureRandom().nextBytes(it) }
        val iv = ByteArray(IV_LEN).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(passphrase, salt)
        val plain = data.toByteArray(Charsets.UTF_8)
        try {
            file.outputStream().buffered(CHUNK).use { out ->
                out.write(MAGIC.toByteArray(Charsets.US_ASCII))
                out.write(salt)
                out.write(iv)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, iv))
                var off = 0
                while (off < plain.size) {
                    val n = minOf(CHUNK, plain.size - off)
                    out.write(cipher.update(plain, off, n))
                    off += n
                }
                out.write(cipher.doFinal()) // GCM tag 随 doFinal 输出，位于流尾
            }
        } catch (e: BackupException) {
            throw e
        } catch (e: Exception) {
            throw BackupException("加密文件失败：${e.message}")
        }
    }

    /** 文件→文件流式解密（#16：不整包进内存）。密语错误抛 BackupException */
    @Throws(BackupException::class)
    fun decryptToFile(src: File, dst: File, passphrase: String) {
        val raf = RandomAccessFile(src, "r")
        try {
            val size = raf.length()
            if (size < MAGIC.length + SALT_LEN + IV_LEN + TAG_LEN + 1) throw BackupException("备份文件不完整")
            val magicBytes = ByteArray(MAGIC.length).also { raf.readFully(it) }
            if (String(magicBytes, Charsets.US_ASCII) != MAGIC) throw BackupException("不是 SJ4 完整加密备份")
            val salt = ByteArray(SALT_LEN).also { raf.readFully(it) }
            val iv = ByteArray(IV_LEN).also { raf.readFully(it) }
            val key = deriveKey(passphrase, salt)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, iv))
            raf.seek((MAGIC.length + SALT_LEN + IV_LEN).toLong())
            dst.outputStream().buffered(CHUNK).use { out ->
                val buf = ByteArray(CHUNK)
                var remaining = size - (MAGIC.length + SALT_LEN + IV_LEN)
                try {
                    while (remaining > 0) {
                        val n = raf.read(buf, 0, minOf(CHUNK.toLong(), remaining).toInt())
                        if (n < 0) break
                        val part = cipher.update(buf, 0, n)
                        if (part != null) out.write(part)
                        remaining -= n
                    }
                    out.write(cipher.doFinal())
                } catch (e: AEADBadTagException) {
                    throw BackupException("密语错误或备份文件损坏")
                }
            }
        } finally {
            raf.close()
        }
    }

    /** 文件→文件流式加密 */
    @Throws(BackupException::class)
    fun encryptFileToFile(src: File, dst: File, passphrase: String) {
        val salt = ByteArray(SALT_LEN).also { SecureRandom().nextBytes(it) }
        val iv = ByteArray(IV_LEN).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(passphrase, salt)
        try {
            dst.outputStream().buffered(CHUNK).use { out ->
                out.write(MAGIC.toByteArray(Charsets.US_ASCII))
                out.write(salt)
                out.write(iv)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, iv))
                src.inputStream().buffered(CHUNK).use { input ->
                    val buf = ByteArray(CHUNK)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(cipher.update(buf, 0, n))
                    }
                    out.write(cipher.doFinal())
                }
            }
        } catch (e: BackupException) { throw e
        } catch (e: Exception) { throw BackupException("加密文件失败：${e.message}") }
    }

    /** 解密：tag 从文件尾部读取；密语错误或文件损坏时抛 "密语错误或备份文件损坏" */
    @Throws(BackupException::class)
    fun decryptFromFile(file: File, passphrase: String): String {
        val raf = RandomAccessFile(file, "r")
        try {
            val size = raf.length()
            if (size < MAGIC.length + SALT_LEN + IV_LEN + TAG_LEN + 1) {
                throw BackupException("备份文件不完整")
            }
            val magicBytes = ByteArray(MAGIC.length).also { raf.readFully(it) }
            if (String(magicBytes, Charsets.US_ASCII) != MAGIC) {
                throw BackupException("不是 SJ4 完整加密备份")
            }
            val salt = ByteArray(SALT_LEN).also { raf.readFully(it) }
            val iv = ByteArray(IV_LEN).also { raf.readFully(it) }
            val key = deriveKey(passphrase, salt)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, iv))
            val bos = java.io.ByteArrayOutputStream()
            raf.seek((MAGIC.length + SALT_LEN + IV_LEN).toLong())
            val buf = ByteArray(CHUNK)
            // JCE 与 HarmonyOS cryptoFramework 的差异：JCE 的 GCM tag 含在输入流尾，
            // 随 update() 一起喂入、doFinal() 校验；鸿蒙版是从文件尾显式读出 tag 传给 GcmParamsSpec。
            // 文件格式不变（tag 仍在流尾），只是消费方式不同。
            var remaining = size - (MAGIC.length + SALT_LEN + IV_LEN)
            while (remaining > 0) {
                val n = raf.read(buf, 0, minOf(CHUNK.toLong(), remaining).toInt())
                if (n < 0) break
                val part = cipher.update(buf, 0, n)
                if (part != null) bos.write(part)
                remaining -= n
            }
            return try {
                bos.write(cipher.doFinal()) // 校验 tag，失败抛 AEADBadTagException
                bos.toString("UTF-8")
            } catch (e: AEADBadTagException) {
                throw BackupException("密语错误或备份文件损坏")
            }
        } catch (e: BackupException) {
            throw e
        } finally {
            raf.close()
        }
    }

    suspend fun sj4Export(file: File, passphrase: String, data: AppData): Unit =
        withContext(Dispatchers.IO) {
            val plain = try {
                json.encodeToString(AppData.serializer(), data)
            } catch (e: Exception) {
                throw BackupException("备份序列化失败：${e.message}")
            }
            encryptToFile(file, passphrase, plain)
        }

    suspend fun sj4Import(file: File, passphrase: String): AppData =
        withContext(Dispatchers.IO) {
            val plain = decryptFromFile(file, passphrase)
            try {
                json.decodeFromString(AppData.serializer(), plain)
            } catch (e: Exception) {
                throw BackupException("备份数据无法解析：${e.message}")
            }
        }
}
