package com.juxia.app.services

import com.juxia.app.utils.splitSentences
import com.juxia.app.utils.stripMarkdown
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.yield
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.Charset
import java.nio.charset.CharsetDecoder
import java.nio.charset.CodingErrorAction

// 句栖 · 材料分块索引（翻译自 MaterialIndexer.ets）
// 64KB 分块读取，只在空行边界切句（句子不被截断）；攒够 250 句批量入库并让出协程。
data class MaterialIndexResult(val ok: Boolean, val count: Int)

object MaterialIndexer {
    private const val CHUNK = 64 * 1024

    /** 找 pending 末尾最后一个"空行边界"（\n 前忽略空格/tab 仍是 \n），找不到且超长时退到末个换行 */
    private fun lastBreak(s: String): Int {
        var last = -1
        var i = s.length - 1
        while (i >= 0) {
            if (s[i] == '\n') {
                var j = i - 1
                while (j >= 0 && (s[j] == ' ' || s[j] == '\t')) j--
                if (j >= 0 && s[j] == '\n') {
                    last = i
                    break
                }
            }
            i--
        }
        if (last < 0 && s.length > 40000) {
            val nl = s.lastIndexOf('\n')
            last = if (nl >= 0) nl else s.length - 1
        }
        return last
    }

    private fun detectEncoding(path: String): String {
        return try {
            val bytes = File(path).inputStream().use {
                val buffer = ByteArray(4096)
                val read = it.read(buffer)
                if (read > 0) buffer.copyOf(read) else ByteArray(0)
            }
            if (bytes.isEmpty()) return "utf-8"
            if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()) return "utf-8"
            if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) return "utf-16le"
            if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) return "utf-16be"
            if (bytes.size >= 4 && bytes[1] == 0.toByte() && bytes[3] == 0.toByte()) return "utf-16le"
            if (bytes.size >= 4 && bytes[0] == 0.toByte() && bytes[2] == 0.toByte()) return "utf-16be"
            try {
                val probe = Charset.forName("UTF-8").newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                probe.decode(ByteBuffer.wrap(bytes))
                "utf-8"
            } catch (e: Exception) {
                "gb18030"
            }
        } catch (e: Exception) {
            "utf-8"
        }
    }

    /** 流式解码一个块（多字节字符跨块时由 decoder 内部保留残码） */
    private fun decodeChunk(decoder: CharsetDecoder, bytes: ByteArray, endOfInput: Boolean): String {
        val cb = CharBuffer.allocate(bytes.size * 2 + 8)
        decoder.decode(ByteBuffer.wrap(bytes), cb, endOfInput)
        if (endOfInput) decoder.flush(cb)
        cb.flip()
        return cb.toString()
    }

    suspend fun indexFile(id: String, path: String, markdown: Boolean = false, quiet: Boolean = false): MaterialIndexResult =
        withContext(Dispatchers.IO) {
            try {
                val encoding = detectEncoding(path)
                val decoder = try {
                    Charset.forName(encoding).newDecoder()
                } catch (e: Exception) {
                    Charsets.UTF_8.newDecoder()
                }
                val clean: (String) -> String = { s -> if (markdown) stripMarkdown(s) else s }
                var pending = ""
                var ord = 0
                var batch = mutableListOf<String>()
                File(path).inputStream().buffered(CHUNK).use { input ->
                    // InputStreamReader + 同一个 decoder 会自动保存跨块的多字节残码
                    val reader = java.io.InputStreamReader(input, decoder)
                    val cbuf = CharArray(CHUNK)
                    while (true) {
                        val n = reader.read(cbuf)
                        if (n <= 0) break
                        pending += String(cbuf, 0, n)
                        val cut = lastBreak(pending)
                        if (cut >= 0) {
                            val complete = pending.substring(0, cut + 1)
                            pending = pending.substring(cut + 1)
                            batch = (batch + splitSentences(clean(complete))).toMutableList()
                        }
                        if (batch.size >= 250) {
                            val written = com.juxia.app.data.Store.instance.appendMaterialSentences(id, ord, batch)
                            if (written != batch.size) throw IllegalStateException("INDEX_PARTIAL")
                            ord += written
                            batch = mutableListOf()
                            yield()
                        }
                    }
                }
                batch = (batch + splitSentences(clean(pending))).toMutableList()
                if (batch.isNotEmpty()) {
                    val written = com.juxia.app.data.Store.instance.appendMaterialSentences(id, ord, batch)
                    if (written != batch.size) throw IllegalStateException("INDEX_PARTIAL")
                    ord += written
                }
                MaterialIndexResult(true, ord)
            } catch (e: Exception) {
                if (!quiet) {
                    AppError.report("材料索引失败。", "回到材料库重新导入；原文件不会被删除。")
                }
                MaterialIndexResult(false, 0)
            }
        }

    /** 整文件读取（供小文件/编辑器场景） */
    fun readText(path: String): String {
        val bytes = File(path).inputStream().buffered(CHUNK).use { it.readBytes() }
        return decode(bytes)
    }

    fun decode(bytes: ByteArray): String {
        if (bytes.isEmpty()) return ""
        if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte())
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte())
            return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
        if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte())
            return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
        val end = minOf(bytes.size, 4096)
        var zeros = 0
        for (i in 0 until end) if (bytes[i] == 0.toByte()) zeros++
        if (zeros > end / 4) return String(bytes, Charsets.UTF_16LE)
        val d = String(bytes, Charsets.UTF_8)
        return if (d.contains('\uFFFD')) String(bytes, Charset.forName("GB18030")) else d
    }
}
