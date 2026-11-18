package com.juxia.app.utils

// 句栖 · SVG Path 缩放（翻译自 PathScale.ets：只缩放坐标，A 命令的弧标志位原样保留）
object PathScale {
    // 已知怪癖（与鸿蒙版行为一致，忠实保留）：原始词法只认 [MLAQZ]，
    // 书签图标中的 V/h/v/H/a 命令会被静默丢弃——这是 ArkTS 原版的同款行为。
    private val tokenRe = Regex("[MLAQZ]|-?\\d+(\\.\\d+)?")

    fun scalePath(cmd: String, scale: Double): String {
        val tokens = tokenRe.findAll(cmd).map { it.value }.toList()
        val out = StringBuilder()
        var i = 0
        fun num(k: Int): Double = tokens[k].toDouble()
        while (i < tokens.size) {
            when (tokens[i]) {
                "M", "L" -> {
                    out.append("${tokens[i]} ${(num(i + 1) * scale).format2()} ${(num(i + 2) * scale).format2()} ")
                    i += 3
                }
                "Q" -> {
                    out.append("Q ${(num(i + 1) * scale).format2()} ${(num(i + 2) * scale).format2()} " +
                        "${(num(i + 3) * scale).format2()} ${(num(i + 4) * scale).format2()} ")
                    i += 5
                }
                "A" -> {
                    out.append("A ${(num(i + 1) * scale).format2()} ${(num(i + 2) * scale).format2()} " +
                        "${tokens[i + 3]} ${tokens[i + 4]} ${tokens[i + 5]} " +
                        "${(num(i + 6) * scale).format2()} ${(num(i + 7) * scale).format2()} ")
                    i += 8
                }
                "Z" -> {
                    out.append("Z ")
                    i += 1
                }
                else -> i += 1
            }
        }
        return out.toString()
    }

    private fun Double.format2(): String = "%.2f".format(this)

    /** ArkTS pathScale(sizeVp, grid) = sizeVp * density / grid；Compose 侧 density 由调用处传入 */
    fun pathScale(sizeVp: Float, grid: Int, density: Float): Double =
        (sizeVp * density / grid).toDouble()
}
