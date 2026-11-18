package com.juxia.app.services

import android.util.Log
import java.util.concurrent.atomic.AtomicLong

// 句栖 · 全局错误出口（翻译自 AppError.ets：1.2s 去重抑制；UI 层通过 listener 接管展示）
object AppError {
    data class Report(val title: String, val hint: String, val fatal: Boolean)

    private const val SUPPRESS_MS = 1200L
    private val lastAt = AtomicLong(0)
    @Volatile var listener: ((Report) -> Unit)? = null

    fun report(title: String, hint: String, fatal: Boolean = false) {
        val now = System.currentTimeMillis()
        val prev = lastAt.get()
        if (now - prev < SUPPRESS_MS) return
        if (!lastAt.compareAndSet(prev, now)) return
        Log.e("juxia", "AppError: $title | $hint")
        listener?.invoke(Report(title, hint, fatal))
    }
}
