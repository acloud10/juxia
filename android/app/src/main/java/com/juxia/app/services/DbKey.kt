package com.juxia.app.services

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec

// 句栖 · 数据库密钥（D2-A）
// 首次启动生成 256 位随机口令，用 Android Keystore 的 AES/GCM 密钥包裹后存 SharedPreferences。
// Keystore 条目不可导出、不进备份 —— 威胁模型 = 鸿蒙 relationalStore encrypt 的系统托管密钥：
// 防 root/物理提取，不防用户本人；备份走 SJ4 应用层加密，与本层正交。
object DbKey {
    private const val KS_ALIAS = "juxia_db_key"
    private const val PREF_ENC = "db_key_enc"

    @Synchronized
    fun getPassphrase(ctx: Context): String {
        val prefs = ctx.getSharedPreferences("juxia_prefs", Context.MODE_PRIVATE)
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(KS_ALIAS)) {
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            gen.init(
                KeyGenParameterSpec.Builder(
                    KS_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            gen.generateKey()
        }
        val key = (ks.getEntry(KS_ALIAS, null) as KeyStore.SecretKeyEntry).secretKey
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val enc = prefs.getString(PREF_ENC, null)
        if (enc == null) {
            val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val blob = cipher.iv + cipher.doFinal(raw)
            prefs.edit().putString(PREF_ENC, Base64.encodeToString(blob, Base64.NO_WRAP)).apply()
            Log.i("juxia", "db key created")
            return Base64.encodeToString(raw, Base64.NO_WRAP)
        }
        return try {
            val blob = Base64.decode(enc, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, blob.copyOfRange(0, 12)))
            Base64.encodeToString(cipher.doFinal(blob.copyOfRange(12, blob.size)), Base64.NO_WRAP)
        } catch (e: Exception) {
            // Keystore 密钥丢失（恢复出厂/换机同步残留）：旧库无法解开。
            // 不删除任何文件，让上层走 prefs 缓存兜底并如实报错。
            Log.e("juxia", "db key unwrap fail", e)
            throw Exception("DB_KEY_LOST")
        }
    }
}
