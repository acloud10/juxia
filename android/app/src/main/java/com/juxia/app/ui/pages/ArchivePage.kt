package com.juxia.app.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.NoteItem
import com.juxia.app.model.OwnEntry
import com.juxia.app.model.fmtDate
import com.juxia.app.model.fmtMD
import com.juxia.app.model.revisitAtFromDays
import com.juxia.app.services.ReminderService
import com.juxia.app.state.UiState
import com.juxia.app.ui.Blank
import com.juxia.app.ui.Card
import com.juxia.app.ui.GhostButton
import com.juxia.app.ui.InnerScrollNav
import com.juxia.app.ui.Label
import com.juxia.app.ui.NoteLine
import com.juxia.app.ui.PrimaryButton
import com.juxia.app.ui.QuietButton
import com.juxia.app.ui.appTokens
import com.juxia.app.ui.padBottom
import com.juxia.app.ui.scaledSp
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import java.util.Calendar

// 句栖 · 回忆页（翻译自 ArchivePage.ets：时间线 / 分类 / 回访一览）
private data class TlNote(val id: String, val at: Long, val text: String, val note: String, val cat: String)
private data class MonthStat(val key: String, val label: String, var resolved: Int = 0, var letgo: Int = 0,
                             var silly: Int = 0, var tired: Int = 0, var total: Int = 0)

private val CAT_COLORS = mapOf(
    "resolved" to "#7a9b76", "letgo" to "#8fa3b8", "silly" to "#c9a86a", "tired" to "#b8434a"
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ArchivePage() {
    val st = Store.instance
    val dataVersion by UiState.dataVersion.collectAsState()
    val t = appTokens()
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()

    var tab by remember { mutableStateOf("timeline") }
    var q by remember { mutableStateOf("") }
    var showRevisit by remember { mutableStateOf(false) }
    var replyOpenId by remember { mutableStateOf("") }
    var replyText by remember { mutableStateOf("") }
    var panel by remember { mutableStateOf("") } // note / revisit
    var targetId by remember { mutableStateOf("") }
    var noteInput by remember { mutableStateOf("") }
    var revisitDaysText by remember { mutableStateOf("7") }
    var askNotify by remember { mutableStateOf(false) }

    val items = st.archived()
    fun match(e: OwnEntry): Boolean {
        val kw = q.trim().lowercase()
        if (kw.isEmpty()) return true
        return e.text.lowercase().contains(kw) || e.archNote.lowercase().contains(kw) ||
            e.notes.any { it.text.lowercase().contains(kw) }
    }
    fun revisitList(): List<OwnEntry> = items.filter { it.revisitAt > 0 }.sortedBy { it.revisitAt }
    fun timelineNotes(): List<TlNote> {
        val out = mutableListOf<TlNote>()
        items.filter { match(it) }.forEach { e ->
            out.add(TlNote(e.id + "-arch", e.archAt, e.text, e.archNote, e.archCat))
            e.notes.forEachIndexed { i, n ->
                out.add(TlNote("${e.id}-n$i", n.at, e.text, n.text, e.archCat))
            }
        }
        return out.sortedByDescending { it.at }.take(60)
    }
    fun months(): List<MonthStat> {
        val map = LinkedHashMap<String, MonthStat>()
        items.forEach { e ->
            val c = Calendar.getInstance().apply { timeInMillis = e.archAt }
            val key = "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH) + 1}"
            val m = map.getOrPut(key) { MonthStat(key, "${c.get(Calendar.MONTH) + 1}月") }
            when (e.archCat) {
                "resolved" -> m.resolved++
                "letgo" -> m.letgo++
                "silly" -> m.silly++
                "tired" -> m.tired++
            }
            m.total++
        }
        return map.values.sortedBy {
            val p = it.key.split("-")
            p[0].toInt() * 12 + p[1].toInt()
        }.takeLast(6)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = padBottom())
    ) {
        Label("回忆区 · 分门别类，不再被抽到")

        // 回访一览（折叠）
        Card(modifier = Modifier.clickable { showRevisit = !showRevisit }, padded = 0.dp) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("回访一览", color = t.inkStrongColor, fontSize = scaledSp(14), fontFamily = FontSerif, letterSpacing = 1.sp)
                    Text("${revisitList().size} 件", color = t.inkSoftColor, fontSize = scaledSp(10),
                        modifier = Modifier.padding(start = 8.dp))
                }
                Text(if (showRevisit) "－" else "＋", color = t.sealColor, fontSize = scaledSp(15))
            }
        }
        if (showRevisit) {
            val rv = rememberScrollState()
            Card(modifier = Modifier.padding(top = 10.dp), padded = 0.dp) {
                Column(Modifier.heightIn(max = 380.dp).verticalScroll(rv).padding(horizontal = 16.dp, vertical = 6.dp)) {
                    if (revisitList().isEmpty()) {
                        Text("还没有约定回访。把一件旧事标记为「已解决 / 已放下」时，可以约一个时间。",
                            color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(24))
                    } else {
                        revisitList().forEach { e ->
                            RevisitCard(e, replyOpenId == e.id, replyText,
                                onReplyOpen = { replyOpenId = e.id; replyText = "" },
                                onReplyClose = { replyOpenId = ""; replyText = "" },
                                onReplyChange = { replyText = it },
                                onReplySave = {
                                    val body = replyText.trim()
                                    if (body.isEmpty()) UiState.showToast("先写一句，再回一句话")
                                    else {
                                        if (st.addReply(e.id, body, "revisit")) {
                                            replyText = ""; replyOpenId = ""
                                            UiState.showToast("回好了，收进句库的「回信」里")
                                        } else UiState.showToast("这句话没有保存成功，再试一次")
                                    }
                                },
                                onSoon = {
                                    e.revisitAt = System.currentTimeMillis(); e.snoozeUntil = 0
                                    st.persist()
                                    ReminderService.rescheduleAll(ctx)
                                    UiState.showToast("已排进今天的回访")
                                },
                                onCancel = {
                                    st.clearRevisit(e.id)
                                    ReminderService.rescheduleAll(ctx)
                                    UiState.showToast("已取消这次回访")
                                })
                        }
                    }
                }
                if (rv.maxValue > 0) {
                    InnerScrollNav(
                        onTop = { scope.launch { rv.animateScrollTo(0) } },
                        onBottom = { scope.launch { rv.animateScrollTo(rv.maxValue) } }
                    )
                }
            }
        }

        // 分类 chips
        FlowRow(
            Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            listOf("timeline" to "时间线", "resolved" to "已解决", "letgo" to "已放下",
                   "silly" to "看起来很蠢", "tired" to "听腻了").forEach { (k, n) ->
                val on = tab == k
                Text(
                    text = n,
                    color = if (on) t.sealInkColor else t.inkSoftColor,
                    fontFamily = FontSans, fontSize = scaledSp(11.5), letterSpacing = 1.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(if (on) t.sealColor else t.cardColor)
                        .border(
                            width = 1.dp,
                            color = if (on) t.sealColor else t.lineColor,
                            shape = RoundedCornerShape(999.dp)
                        )
                        .clickable { tab = k }
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                )
            }
        }

        com.juxia.app.ui.PaperInput(value = q, onChange = { q = it },
            placeholder = "搜索：句子或备注", multiLine = false)
        Spacer(Modifier.height(12.dp))

        if (tab == "timeline") {
            val tl = rememberScrollState()
            Card(padded = 0.dp) {
                Column(Modifier.heightIn(max = 520.dp).verticalScroll(tl).padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Text("每月收进回忆区的句子数，按类别堆叠；下面的时间线是这些句子留下的备注——你的第二本日记。",
                        color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(23))
                    // 堆叠柱
                    val ms = months()
                    val max = maxOf(1, ms.maxOfOrNull { it.total } ?: 1)
                    Row(
                        Modifier.fillMaxWidth().height(100.dp).padding(top = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.Bottom
                    ) {
                        ms.forEach { m ->
                            Column(
                                Modifier.weight(1f).fillMaxWidth(),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Bottom
                            ) {
                                Text("${m.total}", color = t.inkSoftColor, fontSize = scaledSp(9), fontFamily = FontSans)
                                Column(
                                    Modifier.fillMaxWidth().height(56.dp)
                                        .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                        .background(t.lineSoftColor),
                                    verticalArrangement = Arrangement.Bottom
                                ) {
                                    listOf("tired" to m.tired, "silly" to m.silly, "letgo" to m.letgo, "resolved" to m.resolved)
                                        .filter { it.second > 0 }
                                        .forEach { (cat, count) ->
                                            val h = maxOf(2, (count * 56 / max))
                                            Box(
                                                Modifier.fillMaxWidth().height(h.dp)
                                                    .background(com.juxia.app.ui.theme.argb(CAT_COLORS[cat] ?: "#888888"))
                                            )
                                        }
                                }
                                Text(m.label, color = t.inkSoftColor, fontSize = scaledSp(9), fontFamily = FontSans,
                                    modifier = Modifier.padding(top = 4.dp))
                            }
                        }
                    }
                    // 图例
                    Row(Modifier.padding(top = 8.dp)) {
                        CAT_COLORS.forEach { (cat, color) ->
                            Row(
                                Modifier.padding(end = 14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(Modifier.width(8.dp).height(8.dp).clip(RoundedCornerShape(3.dp))
                                    .background(com.juxia.app.ui.theme.argb(color)))
                                Text(" " + st.catLabel(cat), color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans)
                            }
                        }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(t.lineColor).padding(top = 10.dp))
                    // 备注流（60 条）
                    timelineNotes().forEach { n ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                            androidx.compose.material3.HorizontalDivider(color = t.lineSoftColor, thickness = 1.dp)
                            Spacer(Modifier.height(10.dp))
                            Text("${fmtDate(n.at)} · ${st.catLabel(n.cat)}", color = t.inkSoftColor,
                                fontSize = scaledSp(10), fontFamily = FontSans, letterSpacing = 1.5.sp)
                            Text(n.text, color = t.inkStrongColor, fontSize = scaledSp(15), fontFamily = FontSerif,
                                lineHeight = scaledSp(30), modifier = Modifier.padding(top = 2.dp))
                            if (n.note.isNotEmpty()) {
                                Text(n.note, color = t.inkColor, fontSize = scaledSp(13), fontFamily = FontSans,
                                    lineHeight = scaledSp(24), modifier = Modifier.padding(top = 2.dp))
                            }
                        }
                    }
                }
            }
            if (tl.maxValue > 0) {
                InnerScrollNav(
                    onTop = { scope.launch { tl.animateScrollTo(0) } },
                    onBottom = { scope.launch { tl.animateScrollTo(tl.maxValue) } }
                )
            }
        } else {
            val list = items.filter { it.archCat == tab && match(it) }
            if (list.isEmpty()) {
                Card(padded = 40.dp) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        Text(if (q.isNotEmpty()) "没有找到" else "这一类还没有句子",
                            color = t.inkStrongColor, fontSize = scaledSp(14), fontFamily = FontSerif)
                        Spacer(Modifier.height(6.dp))
                        Text(if (q.isNotEmpty()) "换个词试试。" else "空着也挺好。",
                            color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans,
                            lineHeight = scaledSp(22), textAlign = TextAlign.Center)
                    }
                }
            } else {
                val ar = rememberScrollState()
                Column(Modifier.heightIn(max = 420.dp).verticalScroll(ar)) {
                    list.forEach { e -> ArchiveCard(e, st, onNote = { targetId = e.id; noteInput = ""; panel = "note" },
                        onRevisit = {
                            targetId = e.id
                            var days = st.data.settings.revisitDays
                            if (e.revisitAt > System.currentTimeMillis())
                                days = maxOf(1, ((e.revisitAt - System.currentTimeMillis()) / 86400000L).toInt() + 1)
                            revisitDaysText = "$days"
                            panel = "revisit"
                        },
                        onRevive = {
                            st.revive(e.id)
                            ReminderService.rescheduleAll(ctx)
                            UiState.showToast("回来了，它重新参与抽签")
                        })
                }
                if (ar.maxValue > 0) {
                    InnerScrollNav(
                        onTop = { scope.launch { ar.animateScrollTo(0) } },
                        onBottom = { scope.launch { ar.animateScrollTo(ar.maxValue) } }
                    )
                }
            }
        }

        Blank()
        Text("回忆区只保留自己的话；句库条目用排除名单管理",
            color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 22.dp))
    }

    // 底部单：备注 / 回访天数
    if (panel.isNotEmpty()) {
        com.juxia.app.ui.AppSheet(onClose = { panel = "" }) {
            when (panel) {
                "note" -> {
                    Text("补一句备注", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(10.dp))
                    com.juxia.app.ui.PaperInput(value = noteInput, onChange = { noteInput = it },
                        placeholder = "此刻想起它，是什么感觉？")
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("记下") {
                            val body = noteInput.trim()
                            if (body.isNotEmpty()) st.addNote(targetId, body)
                            panel = ""
                            if (body.isNotEmpty()) UiState.showToast("已记下")
                        }
                    }
                }
                "revisit" -> {
                    Text("多少天后再问一次", color = t.inkStrongColor, fontSize = scaledSp(16), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(8.dp))
                    Text("默认 ${st.data.settings.revisitDays} 天，可单独改。从今天起算，天数会随着时间减少，到点由系统提醒你；通知排不进去时，到期打开句栖也会看到回访卡。",
                        color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans, lineHeight = scaledSp(20))
                    Spacer(Modifier.height(8.dp))
                    com.juxia.app.ui.PaperInput(value = revisitDaysText, onChange = { revisitDaysText = it.filter { c -> c.isDigit() } },
                        placeholder = "输入天数", multiLine = false)
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("保存天数") {
                            val days = (revisitDaysText.toIntOrNull() ?: 0).coerceIn(1, 3650)
                            val at = revisitAtFromDays(days, st.data.settings.revisitHour, st.data.settings.revisitMinute)
                            st.setRevisitAt(targetId, at)
                            ReminderService.rescheduleAll(ctx)
                            panel = ""
                            if (!ReminderService.isNotificationEnabled(ctx)) askNotify = true
                            UiState.showToast("$days 天后轻轻问你一次")
                        }
                    }
                }
            }
        }
    }

    if (askNotify) {
        AlertDialog(
            onDismissRequest = { askNotify = false },
            title = { Text("开启通知", fontFamily = FontSerif) },
            text = { Text("仍未开启，可到系统设置里允许句栖通知。开启后，句栖才能在约定时间轻轻问你一次。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    askNotify = false
                    val intent = android.content.Intent(
                        if (android.os.Build.VERSION.SDK_INT >= 26) android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS
                        else android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    ).apply { data = android.net.Uri.parse("package:" + ctx.packageName) }
                    try { ctx.startActivity(intent) } catch (_: Exception) {}
                    UiState.showToast("到期打开句栖，仍会看到回访卡")
                }) { Text("去开启", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { askNotify = false; UiState.showToast("到期打开句栖，仍会看到回访卡") }) { Text("稍后") }
            }
        )
    }
}
}

@Composable
private fun RevisitCard(
    e: OwnEntry, replyOpen: Boolean, replyText: String,
    onReplyOpen: () -> Unit, onReplyClose: () -> Unit, onReplyChange: (String) -> Unit, onReplySave: () -> Unit,
    onSoon: () -> Unit, onCancel: () -> Unit
) {
    val t = appTokens()
    val now = System.currentTimeMillis()
    val due = e.revisitAt <= now
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(e.text, color = t.inkColor, fontSize = scaledSp(15.5), fontFamily = FontSerif, lineHeight = scaledSp(31))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) {
            Text(
                if (due) "已到期" else "还有 ${(e.revisitAt - now + 86399999) / 86400000} 天",
                color = if (due) t.sealInkColor else t.inkSoftColor,
                fontFamily = FontSans, fontSize = scaledSp(10.5),
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (due) t.sealColor else t.cardColor)
                    .padding(horizontal = 9.dp, vertical = 2.dp)
            )
            Text(fmtMD(e.revisitAt), color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
                modifier = Modifier.padding(horizontal = 8.dp))
            QuietButton("提前到今天", onSoon)
            QuietButton("取消回访", onCancel)
            QuietButton("回一句话", onReplyOpen)
        }
        if (replyOpen) {
            Column(Modifier.padding(top = 8.dp)) {
                com.juxia.app.ui.PaperInput(value = replyText, onChange = onReplyChange,
                    placeholder = "不用写完整，回一句话就好")
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuietButton("取消") { onReplyChange(""); onReplyClose() }
                    PrimaryButton("保存回信") { onReplySave() }
                }
            }
        }
    }
}

@Composable
private fun ArchiveCard(
    e: OwnEntry, st: Store,
    onNote: () -> Unit, onRevisit: () -> Unit, onRevive: () -> Unit
) {
    val t = appTokens()
    Card(modifier = Modifier.padding(bottom = 12.dp), padded = 18.dp) {
        Text(e.text, color = t.inkStrongColor, fontSize = scaledSp(16.5), fontFamily = FontSerif, lineHeight = scaledSp(33))
        Text("${fmtDate(e.archAt)} 标记为「${st.catLabel(e.archCat)}」",
            color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans, letterSpacing = 1.sp,
            modifier = Modifier.padding(top = 4.dp))
        if (e.archNote.isNotEmpty()) NoteLine("${fmtMD(e.archAt)}  ${e.archNote}")
        e.notes.forEach { NoteLine(it.text) }
        if (e.kind == "wound" && (e.archCat == "resolved" || e.archCat == "letgo")) {
            Text(
                if (e.revisitAt > 0) "回访：${fmtMD(e.revisitAt)} 轻轻问一次" +
                    (if (e.snoozeUntil > System.currentTimeMillis()) "（再等等到 ${fmtMD(e.snoozeUntil)}）" else "")
                else "未设回访",
                color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans,
                modifier = Modifier.padding(top = 6.dp)
            )
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            QuietButton("加备注", onNote)
            if (e.kind == "wound") QuietButton(if (e.revisitAt > 0) "改回访天数" else "设置回访天数", onRevisit)
            QuietButton("复活回台前", onRevive)
        }
    }
}
