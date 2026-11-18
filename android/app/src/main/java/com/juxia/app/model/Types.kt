package com.juxia.app.model

import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.Date

// 句栖 · 数据模型（翻译自 Types.ets，字段名原样保留：SJ4 备份互通依赖这些名字）
const val DAY_MS: Long = 86400000L

@Serializable
data class Settings(
    var ritualMode: String = "full", // full / short / off
    var revisitDays: Int = 90,
    var revisitHour: Int = 9,
    var revisitMinute: Int = 0,
    var theme: String = "system", // system / light / dark
    var skin: String = "classic", // classic / plain
    var showDays: Boolean = true,
    var showSeal: Boolean = true,
    var appName: String = "句栖",
    var bootLong: Boolean = false,
    var bootText: String = "",
    var bootHoldMs: Long = 1200,
    var bootFontScale: Double = 1.25,
    var backupRemindOff: Boolean = false,
    var fullIncludeMaterials: Boolean = true,
    var plainIncludeMaterials: Boolean = true,
    var drawCount: Int = 0,
    var drawOwn: Boolean = true,
    var drawLib: Boolean = true,
    var nickname: String = "",
    var showGreeting: Boolean = false,
    var showReflect: Boolean = true,
    var fontScale: Double = 1.0,
    var fontScaleFollow: Boolean = true,
    var privacyAccepted: Boolean = false,
    var background: BackgroundStyle = BackgroundStyle(),
)

@Serializable
data class DayState(
    var date: String = "",
    var mood: String = "", // "" / good / bad
    var wrote: Boolean = false,
    var drew: Boolean = false,
    var backupDismissed: Boolean = false,
)

@Serializable
data class MetaState(
    var firstUse: Long = 0,
    var seen: Boolean = false,
    var lastBackupAt: Long = 0,
    var openDays: MutableList<String> = mutableListOf(),
    var revisitReminderIds: MutableMap<String, Long> = mutableMapOf(),
)

@Serializable
data class NoteItem(var at: Long = 0, var text: String = "")

@Serializable
data class OwnEntry(
    var id: String = "",
    var kind: String = "encourage", // encourage / wound
    var text: String = "",
    var note: String = "",
    var bindIds: MutableList<String> = mutableListOf(),
    var createdAt: Long = 0,
    var archCat: String = "",
    var archNote: String = "",
    var archAt: Long = 0,
    var revisitAt: Long = 0,
    var snoozeUntil: Long = 0,
    var foot: MutableList<String> = mutableListOf(),
    var footIds: MutableList<String> = mutableListOf(),
    var notes: MutableList<NoteItem> = mutableListOf(),
    var replyToId: String = "",
    var replyFrom: String = "", // draw / revisit
) {
    fun isArchived(): Boolean = archAt > 0
}

@Serializable
data class LibEntry(
    var id: String = "",
    var text: String = "",
    var source: String = "",
    var origin: String = "material",
    var tag: String = "",
    var createdAt: Long = 0,
    var bindIds: MutableList<String> = mutableListOf(),
)

@Serializable
data class DislikeEntry(
    var text: String = "",
    var source: String = "",
    var origin: String = "",
    var at: Long = 0,
)

@Serializable
data class MaterialEntry(
    var id: String = "",
    var name: String = "",
    var text: String = "",
    var path: String = "",
    var size: Long = 0,
    var createdAt: Long = 0,
)

@Serializable
data class AppData(
    var version: Int = 2,
    var own: MutableList<OwnEntry> = mutableListOf(),
    var lib: MutableList<LibEntry> = mutableListOf(),
    var dislikes: MutableList<DislikeEntry> = mutableListOf(),
    var materials: MutableList<MaterialEntry> = mutableListOf(),
    var settings: Settings = Settings(),
    var day: DayState = DayState(),
    var meta: MetaState = MetaState(),
)

// 抽签上下文：own（自己的话）/ lib（句库）
data class RitualCtx(
    var type: String = "lib",
    var badge: String = "",
    var tag: String = "",
    var text: String = "",
    var source: String = "",
    var origin: String = "",
    var entry: OwnEntry? = null,
    var todayFlow: Boolean = false,
)

fun todayStr(d: Date = Date()): String {
    val c = Calendar.getInstance().apply { time = d }
    return "%04d-%02d-%02d".format(
        c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
}

fun fmtDate(ts: Long): String {
    val c = Calendar.getInstance().apply { timeInMillis = ts }
    return "${c.get(Calendar.YEAR)}年${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日"
}

fun fmtMD(ts: Long): String {
    val c = Calendar.getInstance().apply { timeInMillis = ts }
    return "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日"
}

// N 天后的指定时刻；时间点由设置里的回访时间决定
fun revisitAtFromDays(days: Int, hour: Int = 9, minute: Int = 0): Long {
    val c = Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, maxOf(1, days))
        set(Calendar.HOUR_OF_DAY, hour)
        set(Calendar.MINUTE, minute)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return c.timeInMillis
}

fun weekdayCN(d: Date): String {
    val names = listOf("日", "一", "二", "三", "四", "五", "六")
    return names[Calendar.getInstance().apply { time = d }.get(Calendar.DAY_OF_WEEK) - 1]
}

private val CND = listOf("〇", "一", "二", "三", "四", "五", "六", "七", "八", "九")

fun sealCN(ds: String): String {
    return ds.split("-").joinToString("·") { part ->
        part.map { ch -> ch.digitToIntOrNull()?.let { CND[it] } ?: ch.toString() }.joinToString("")
    }
}
