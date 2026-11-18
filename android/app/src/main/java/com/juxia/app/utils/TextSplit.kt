package com.juxia.app.utils

// 句栖 · 文本切分（翻译自 TextSplit.ets，逐行对齐）
// 注意：splitSentences 不调用 stripMarkdown，两者是独立导出；
// MaterialIndexer 只在 .md 材料上先 stripMarkdown 再 splitSentences。
// 只按空行分句；单个换行按空格处理；段内标点不再单独切。

fun stripMarkdown(text: String): String {
    var t = text.replace(Regex("\r"), "")
    t = t.replace(Regex("^---[ \\t]*\n[\\s\\S]*?\n---[ \\t]*\n"), "")
    t = t.replace(Regex("```[\\s\\S]*?```"), " ")
    t = t.replace(Regex("`([^`]+)`"), "$1")
    t = t.replace(Regex("!\\[([^\\]]*)\\]\\([^)]*\\)"), "$1")
    t = t.replace(Regex("\\[([^\\]]+)\\]\\([^)]*\\)"), "$1")
    t = t.replace(Regex("^#{1,6}\\s*", RegexOption.MULTILINE), "")
    t = t.replace(Regex("^\\s*[-*+]\\s+", RegexOption.MULTILINE), "")
    t = t.replace(Regex("^\\s*\\d+\\.\\s+", RegexOption.MULTILINE), "")
    t = t.replace(Regex("^\\s*>\\s?", RegexOption.MULTILINE), "")
    t = t.replace(Regex("[*_~]{1,3}"), "")
    t = t.replace(Regex("<[^>]+>"), " ")
    return t
}

fun splitSentences(text: String): List<String> {
    val out = mutableListOf<String>()
    val normalized = text.replace(Regex("\r"), "")
    val blocks = normalized.split(Regex("\n[ \\t]*\n+"))
    for (block in blocks) {
        val line = block.replace(Regex("\n+"), " ").trim()
        if (line.isNotEmpty()) out.add(line)
    }
    return out
}
