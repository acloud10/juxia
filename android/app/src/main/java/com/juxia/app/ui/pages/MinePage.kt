package com.juxia.app.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import kotlinx.coroutines.launch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.NoteItem
import com.juxia.app.model.OwnEntry
import com.juxia.app.model.fmtDate
import com.juxia.app.model.fmtMD
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

// 句栖 · 我的页（翻译自 MinePage.ets：鼓励池/旧事簿/省身/关联/归档面板/备注）
private data class ReflectGroup(val key: String, val label: String, val items: List<OwnEntry>)
private data class ReflectYear(val key: String, val label: String, val total: Int, val months: List<ReflectGroup>)

@Composable
fun MinePage() {
    val st = Store.instance
    val dataVersion by UiState.dataVersion.collectAsState()
    val t = appTokens()
    val ctx = LocalContext.current
    val showRef = st.data.settings.showReflect

    var q by remember { mutableStateOf("") }
    var expanded by remember { mutableStateOf(setOf("encourage", "wound")) }
    var refQ by remember { mutableStateOf("") }
    var refLimit by remember { mutableIntStateOf(30) }
    var refOpenYears by remember { mutableStateOf(setOf<String>()) }
    var refOpenMonths by remember { mutableStateOf(setOf<String>()) }
    var panel by remember { mutableStateOf("") } // note/bind/archive/reflectWrite/reflectNote/reflectEdit
    var panelEntryId by remember { mutableStateOf("") }
    var bindRev by remember { mutableIntStateOf(0) }
    var archCat by remember { mutableStateOf("resolved") }
    var archNote by remember { mutableStateOf("") }
    var withRevisit by remember { mutableStateOf(true) }
    var noteInput by remember { mutableStateOf("") }
    var refText by remember { mutableStateOf("") }
    var refNoteInput by remember { mutableStateOf("") }
    var refEditId by remember { mutableStateOf("") }
    var refEditText by remember { mutableStateOf("") }
    var deleteTarget by remember { mutableStateOf<OwnEntry?>(null) }
    var deleteNoteTarget by remember { mutableStateOf<OwnEntry?>(null) }
    val listScroll = rememberScrollState()

    // 仪式外发的绑定/归档请求
    val bindReq by UiState.bindRequest.collectAsState()
    val archReq by UiState.archiveRequest.collectAsState()
    androidx.compose.runtime.LaunchedEffect(bindReq) {
        bindReq?.let {
            panel = "bind"; panelEntryId = it; bindRev++
            UiState.consumeBind()
        }
    }
    androidx.compose.runtime.LaunchedEffect(archReq) {
        archReq?.let {
            st.data.own.find { e -> e.id == it }?.let { e ->
                panel = "archive"; panelEntryId = e.id
                archCat = if (e.kind == "wound") "resolved" else "silly"
                archNote = ""; withRevisit = true
            }
            UiState.consumeArchive()
        }
    }

    fun entry(): OwnEntry? = st.data.own.find { it.id == panelEntryId }
    fun kw(): String = q.trim().lowercase()

    fun matches(e: OwnEntry): Boolean {
        val k = kw()
        if (k.isEmpty()) return true
        return e.text.lowercase().contains(k) || e.note.lowercase().contains(k) ||
            e.foot.any { it.lowercase().contains(k) } ||
            e.notes.any { it.text.lowercase().contains(k) }
    }

    fun filtered(kind: String): List<OwnEntry> =
        st.data.own.filter { it.kind == kind && !it.isArchived() && matches(e = it) }

    fun boundNames(e: OwnEntry): List<String> {
        val names = mutableListOf<String>()
        for (id in e.bindIds) {
            val x = st.data.own.find { it.id == id } ?: continue
            if (x.isArchived()) continue
            names.add(x.text)
        }
        return names
    }

    fun latestNote(e: OwnEntry): String = e.notes.lastOrNull()?.text ?: ""

    fun refMatches(e: OwnEntry): Boolean {
        val k = refQ.trim().lowercase()
        if (k.isEmpty()) return true
        return e.text.lowercase().contains(k) || e.notes.any { it.text.lowercase().contains(k) }
    }

    fun refYearGroups(): List<ReflectYear> {
        val list = st.reflects().filter { refMatches(it) }
            .sortedByDescending { it.createdAt }
        val years = LinkedHashMap<String, MutableList<OwnEntry>>()
        for (e in list) {
            val c = Calendar.getInstance().apply { timeInMillis = e.createdAt }
            val key = "${c.get(Calendar.YEAR)}"
            years.getOrPut(key) { mutableListOf() }.add(e)
        }
        return years.map { (yKey, items) ->
            val months = LinkedHashMap<String, MutableList<OwnEntry>>()
            for (e in items) {
                val c = Calendar.getInstance().apply { timeInMillis = e.createdAt }
                val mKey = "$yKey-${c.get(Calendar.MONTH) + 1}"
                months.getOrPut(mKey) { mutableListOf() }.add(e)
            }
            ReflectYear(
                key = yKey, label = "${yKey}年", total = items.size,
                months = months.map { (mKey, ms) ->
                    ReflectGroup(mKey, "${ms[0].let { Calendar.getInstance().apply { timeInMillis = it.createdAt }.get(Calendar.MONTH) + 1 }}月", ms)
                }
            )
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = padBottom())
    ) {
        Label("我的话 · 未导出时只有这台设备看得到")
        com.juxia.app.ui.PaperInput(
            value = q,
            onChange = { v ->
                q = v
                if (v.trim().isNotEmpty()) expanded = setOf("encourage", "wound")
            },
            placeholder = "搜索：句子或备注",
            multiLine = false
        )
        Spacer(Modifier.height(12.dp))

        ListSection(
            kind = "encourage", title = "鼓励池",
            emptyText = "还一句都没有。下一个心情不错的日子，写一句留给低谷时的自己。", searchActive = q.isNotEmpty(),
            entries = filtered("encourage"),
            open = "encourage" in expanded,
            onToggle = { expanded = if (it) expanded + "encourage" else expanded - "encourage" },
            onNote = { panel = "note"; panelEntryId = it.id; noteInput = st.loadDraft("note_" + it.id).ifEmpty { latestNote(it) } },
            onBind = { panel = "bind"; panelEntryId = it.id; bindRev++ },
            onArchive = {
                panel = "archive"; panelEntryId = it.id
                archCat = if (it.kind == "wound") "resolved" else "silly"
                archNote = ""; withRevisit = true
            },
            onDelete = { deleteTarget = it },
            onWrite = { UiState.setTab("today") },
            boundNames = ::boundNames, latestNote = ::latestNote, footLines = { st.footLines(it) },
            scrollState = listScroll,
            onDeleteNote = { deleteNoteTarget = it }
        )
        ListSection(
            kind = "wound", title = "旧事簿",
            emptyText = "树洞是空的。难过的事写下来，就已经轻了一点。", searchActive = q.isNotEmpty(),
            entries = filtered("wound"),
            open = "wound" in expanded,
            onToggle = { expanded = if (it) expanded + "wound" else expanded - "wound" },
            onNote = { panel = "note"; panelEntryId = it.id; noteInput = st.loadDraft("note_" + it.id).ifEmpty { latestNote(it) } },
            onBind = { panel = "bind"; panelEntryId = it.id; bindRev++ },
            onArchive = {
                panel = "archive"; panelEntryId = it.id
                archCat = if (it.kind == "wound") "resolved" else "silly"
                archNote = ""; withRevisit = true
            },
            onDelete = { deleteTarget = it },
            onWrite = { UiState.setTab("today") },
            boundNames = ::boundNames, latestNote = ::latestNote, footLines = { st.footLines(it) },
            scrollState = listScroll,
            onDeleteNote = { deleteNoteTarget = it }
        )

        if (showRef) {
            ReflectSection(
                groups = refYearGroups(),
                openYears = refOpenYears, openMonths = refOpenMonths,
                onToggleYear = { refOpenYears = if (it.second) refOpenYears + it.first else refOpenYears - it.first },
                onToggleMonth = { refOpenMonths = if (it.second) refOpenMonths + it.first else refOpenMonths - it.first },
                limit = refLimit,
                onMore = { refLimit += 30 },
                searchActive = refQ.isNotEmpty(),
                refQ = refQ, onRefQ = { refQ = it; refLimit = 30 },
                onWrite = { refText = ""; panel = "reflectWrite" },
                onNote = { e -> refNoteInput = latestNote(e); panelEntryId = e.id; panel = "reflectNote" },
                onEdit = { e -> refEditId = e.id; refEditText = e.text; panel = "reflectEdit" },
                onDelete = { deleteTarget = it }
            )
        }

        if (st.data.own.isEmpty() && st.data.lib.isEmpty() && refQ.isEmpty() && q.isEmpty()) {
            EmptyGuide { UiState.setTab("today") }
        }

        Blank()
        Text(
            "鼓励与旧事可以互相关联；旧事归档时会自动给鼓励留下注脚",
            color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 22.dp)
        )
    }

    // —— 底部单 ——
    if (panel.isNotEmpty()) {
        com.juxia.app.ui.AppSheet(onClose = { panel = "" }) {
            when (panel) {
                "note" -> {
                    Text("加备注", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(10.dp))
                    entry()?.let { e ->
                        Text(e.text, color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSerif,
                            lineHeight = scaledSp(21), maxLines = 3, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.fillMaxWidth())
                    }
                    Spacer(Modifier.height(10.dp))
                    com.juxia.app.ui.PaperInput(value = noteInput, onChange = { noteInput = it; st.saveDraft("note_" + panelEntryId, it) }, placeholder = "备注：此刻想留下的一句话")
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("保存备注") {
                            val ok = entry()?.let { st.setNote(it.id, noteInput.trim()) } == true
                            st.clearDraft("note_" + panelEntryId)
                            panel = ""
                            UiState.showToast(if (ok) "备注已保存" else "这条已经不在台前了")
                        }
                    }
                }
                "bind" -> {
                    val e = entry()
                    Text(if (e?.kind == "encourage") "这句话曾陪我度过哪件事" else "哪句话曾陪你度过这件事",
                        color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(12.dp))
                    Text("可关联多件，再点一次解除。两边是同一根线。",
                        color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
                    Spacer(Modifier.height(10.dp))
                    bindRev.let { }
                    val others: List<OwnEntry> = if (e != null)
                        st.data.own.filter { it.kind != e.kind && !it.isArchived() }
                    else emptyList()
                    if (others.isEmpty()) {
                        Text(if (e?.kind == "encourage") "树洞还是空的。先写一件难过的事，再回来关联。" else "鼓励池还是空的。先写一句鼓励，再回来关联。",
                            color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
                    }
                    others.forEach { x ->
                        // e?.kind == "..." 不构成智能转换，必须显式判空（Kotlin 空安全 ≠ JS 宽松语义）
                        val encId = if (e != null && e.kind == "encourage") e.id else x.id
                        val wndId = if (e != null && e.kind == "wound") e.id else x.id
                        val bound = e?.bindIds?.contains(x.id) == true
                        Row(
                            Modifier.fillMaxWidth().padding(vertical = 10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(x.text.take(20) + if (x.text.length > 20) "…" else "",
                                color = t.inkColor, fontSize = scaledSp(14.5), fontFamily = FontSerif)
                            if (e != null) {
                                if (bound) {
                                    PrimaryButton("解除关联") {
                                        st.toggleBind(encId, wndId); bindRev++
                                        UiState.showToast("已解除关联")
                                    }
                                } else {
                                    GhostButton("关联") {
                                        st.toggleBind(encId, wndId); bindRev++
                                        UiState.showToast("已关联")
                                    }
                                }
                            }
                        }
                    }
                }
                "archive" -> {
                    val e = entry()
                    Text("标记退役", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(12.dp))
                    Text("标记后不再被抽到，分门别类收进回忆区。",
                        color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
                    Spacer(Modifier.height(12.dp))
                    val cats = if (e?.kind == "wound") listOf("resolved" to "已解决", "letgo" to "已放下")
                               else listOf("silly" to "看起来很蠢", "tired" to "听腻了")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        cats.forEach { (k, n) ->
                            if (archCat == k) PrimaryButton(n) { archCat = k } else GhostButton(n) { archCat = k }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    com.juxia.app.ui.PaperInput(value = archNote, onChange = { archNote = it },
                        placeholder = if (e?.kind == "wound") "备注：为什么解决了 / 放下了？"
                                    else "备注：为什么听腻了 / 觉得蠢？")
                    if (e?.kind == "wound") {
                        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(withRevisit, { withRevisit = it })
                            Text(" ${st.data.settings.revisitDays} 天后轻轻问我一次",
                                color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans)
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    PrimaryButton("收进回忆区", Modifier.fillMaxWidth()) {
                        entry()?.let { en ->
                            st.archiveOwn(en.id, archCat, archNote.trim(), withRevisit)
                            panel = ""
                            ReminderService.rescheduleAll(ctx)
                            UiState.showToast(
                                if (withRevisit && !ReminderService.isNotificationEnabled(ctx))
                                    "系统通知没排进去；到期打开句栖仍会看到回访卡"
                                else "已收进回忆区")
                        }
                    }
                }
                "reflectWrite" -> {
                    Text("写一条省身", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(10.dp))
                    com.juxia.app.ui.PaperInput(value = refText, onChange = { refText = it },
                        placeholder = "今天，你想省察什么？")
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("保存") {
                            if (refText.trim().isEmpty()) UiState.showToast("先写一句再保存")
                            else {
                                st.addReflect(refText.trim())
                                refText = ""
                                panel = ""
                                UiState.showToast("已记下这条省身")
                            }
                        }
                    }
                }
                "reflectNote" -> {
                    Text("省身备注", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(10.dp))
                    entry()?.let { e ->
                        Text(e.text, color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSerif,
                            lineHeight = scaledSp(21), maxLines = 3, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.fillMaxWidth())
                    }
                    Spacer(Modifier.height(10.dp))
                    com.juxia.app.ui.PaperInput(value = refNoteInput, onChange = { refNoteInput = it }, placeholder = "此刻补充一句……")
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("保存备注") {
                            val ok = entry()?.let { st.setNote(it.id, refNoteInput.trim()) } == true
                            panel = ""
                            UiState.showToast(if (ok) "备注已加上" else "这条已经不在台前了")
                        }
                    }
                }
                "reflectEdit" -> {
                    Text("编辑省身", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif, letterSpacing = 2.sp)
                    Spacer(Modifier.height(10.dp))
                    com.juxia.app.ui.PaperInput(value = refEditText, onChange = { refEditText = it }, placeholder = "")
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        QuietButton("取消") { panel = "" }
                        PrimaryButton("保存修改") {
                            if (refEditText.trim().isEmpty()) UiState.showToast("正文不能为空")
                            else {
                                if (!st.updateOwnText(refEditId, refEditText.trim())) {
                                    UiState.showToast("正文不能为空")
                                } else {
                                    panel = ""
                                    UiState.showToast("省身已更新")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 删除确认：条目（句子/省身）与单条备注，两种流程
    deleteTarget?.let { e ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text(if (e.kind == "reflect") "删除这条省身？" else "删除这句话？", fontFamily = FontSerif) },
            text = { Text(if (e.kind == "reflect") "连同它的备注一起删除，无法恢复。" else "连同它的备注、关联关系一起删除，无法恢复。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    st.removeOwn(e.id)
                    deleteTarget = null
                    UiState.showToast("已删除")
                }) { Text("删除", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("取消") }
            }
        )
    }
    deleteNoteTarget?.let { e ->
        AlertDialog(
            onDismissRequest = { deleteNoteTarget = null },
            title = { Text("删除这条备注？", fontFamily = FontSerif) },
            text = { Text("只删除这条备注，不删除原句；无法恢复。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    st.removeLatestNote(e.id)
                    deleteNoteTarget = null
                    UiState.showToast("备注已删除")
                }) { Text("删除", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { deleteNoteTarget = null }) { Text("取消") }
            }
        )
    }
}


// —— 列表分区：标题行 + 限高内滚动 + 条目行 ——
@Composable
private fun ListSection(
    kind: String, title: String, emptyText: String, entries: List<OwnEntry>,
    open: Boolean, onToggle: (Boolean) -> Unit,
    onNote: (OwnEntry) -> Unit, onBind: (OwnEntry) -> Unit, onArchive: (OwnEntry) -> Unit,
    onDelete: (OwnEntry) -> Unit, onWrite: () -> Unit,
    boundNames: (OwnEntry) -> List<String>, latestNote: (OwnEntry) -> String, footLines: (OwnEntry) -> List<String>,
    scrollState: androidx.compose.foundation.ScrollState,
    searchActive: Boolean = false, onDeleteNote: (OwnEntry) -> Unit = {}
) {
    val t = appTokens()
    val st = Store.instance
    val inner = rememberScrollState()
    Card(padded = 0.dp) {
        Row(
            Modifier.fillMaxWidth().clickable { onToggle(!open) }
                .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, color = t.inkStrongColor, fontSize = scaledSp(14), fontFamily = FontSerif, letterSpacing = 1.5.sp)
            Text(
                "${entries.size} ${if (kind == "encourage") "句" else "件"}",
                color = t.inkSoftColor, fontSize = scaledSp(10), fontFamily = FontSans,
                modifier = Modifier
                    .padding(start = 8.dp)
                    .background(t.cardColor)
                    .border(1.dp, t.lineColor, RoundedCornerShape(999.dp))
                    .padding(horizontal = 9.dp, vertical = 2.dp)
            )
            Spacer(Modifier.weight(1f))
            Text(if (open) "−" else "＋", color = t.sealColor, fontSize = scaledSp(16), fontFamily = FontSans)
        }
        if (open) {
            if (entries.isEmpty()) {
                Column(
                    Modifier.fillMaxWidth().padding(top = 22.dp, bottom = 26.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        if (searchActive) "没有找到"
                        else if (kind == "encourage") "还一句都没有" else "树洞是空的",
                        color = t.inkStrongColor, fontSize = scaledSp(14), fontFamily = FontSerif
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        if (searchActive) "换个词试试。" else emptyText,
                        color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans,
                        lineHeight = scaledSp(22), textAlign = TextAlign.Center
                    )
                }
            } else {
                Column(Modifier.heightIn(max = 360.dp).verticalScroll(inner).padding(horizontal = 16.dp)) {
                    entries.forEachIndexed { i, e ->
                        if (i > 0) Spacer(Modifier.height(2.dp))
                        EntryRow(e, kind, boundNames(e), latestNote(e), footLines(e),
                            onNote = { onNote(e) }, onBind = { onBind(e) },
                            onArchive = { onArchive(e) }, onDelete = { onDelete(e) },
                            onDeleteNote = { onDeleteNote(e) })
                        Spacer(Modifier.height(2.dp))
                    }
                }
                val innerScope = androidx.compose.runtime.rememberCoroutineScope()
                if (inner.maxValue > 0) {
                    InnerScrollNav(
                        onTop = { innerScope.launch { inner.animateScrollTo(0) } },
                        onBottom = { innerScope.launch { inner.animateScrollTo(inner.maxValue) } }
                    )
                }
            }
            if (entries.isNotEmpty()) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 12.dp)) {
                    GhostButton(if (kind == "encourage") "写一句鼓励自己的话" else "写一件放进树洞", Modifier.fillMaxWidth()) { onWrite() }
                }
            }
        }
    }
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun EntryRow(
    e: OwnEntry, kind: String, bounds: List<String>, note: String, foot: List<String>,
    onNote: () -> Unit, onBind: () -> Unit, onArchive: () -> Unit, onDelete: () -> Unit,
    onDeleteNote: () -> Unit = {}
) {
    val t = appTokens()
    Column(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 10.dp)) {
        androidx.compose.material3.HorizontalDivider(color = t.lineSoftColor, thickness = 1.dp)
        Spacer(Modifier.height(10.dp))
        Text(e.text, color = t.inkStrongColor, fontSize = scaledSp(16.5), fontFamily = FontSerif,
            lineHeight = scaledSp(33))
        val meta = buildList {
            add(fmtDate(e.createdAt))
            bounds.forEach {
                val name = it.take(12) + if (it.length > 12) "…" else ""
                add(if (kind == "encourage") "曾陪我度过「$name」" else "有「$name」陪着")
            }
        }.joinToString(" · ")
        Spacer(Modifier.height(4.dp))
        Text(meta, color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans, letterSpacing = 1.sp)
        if (note.isNotEmpty()) {
            NoteLine(note)
        }
        foot.forEach { NoteLine(it) }
        if (note.isNotEmpty()) {
            QuietButton("删除备注", onDeleteNote)
        }
        // 鸿蒙是 Flex 换行；Android 用两行避免四个操作按钮被裁切。
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            QuietButton("加备注", onNote)
            QuietButton(if (kind == "encourage") "关联旧事" else "关联鼓励", onBind)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            QuietButton(if (kind == "wound") "标记已解决 / 已放下" else "不再参与抽签", onArchive)
            QuietButton("删除", onDelete)
        }
    }
}

// —— 省身分区 ——
@Composable
private fun ReflectSection(
    groups: List<ReflectYear>,
    openYears: Set<String>, openMonths: Set<String>,
    onToggleYear: (Pair<String, Boolean>) -> Unit, onToggleMonth: (Pair<String, Boolean>) -> Unit,
    limit: Int, onMore: () -> Unit,
    searchActive: Boolean = false,
    refQ: String = "", onRefQ: (String) -> Unit = {},
    onWrite: () -> Unit, onNote: (OwnEntry) -> Unit, onEdit: (OwnEntry) -> Unit, onDelete: (OwnEntry) -> Unit
) {
    val t = appTokens()
    val total = groups.sumOf { it.total }
    Card(padded = 0.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("省身", color = t.inkStrongColor, fontSize = scaledSp(14), fontFamily = FontSerif, letterSpacing = 2.sp)
            Text("$total", color = t.inkSoftColor, fontSize = scaledSp(10))
        }
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp)) {
            PrimaryButton("写一条省身", Modifier.fillMaxWidth()) { onWrite() }
            Spacer(Modifier.height(8.dp))
            com.juxia.app.ui.PaperInput(value = refQ, onChange = onRefQ,
                placeholder = "搜索省身正文或备注", multiLine = false)
            Spacer(Modifier.height(8.dp))
            if (groups.isEmpty()) {
                Text(if (searchActive) "没有找到。换个词，或清空搜索。" else "省身不是任务。想写的时候再写。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                    lineHeight = scaledSp(23),
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 16.dp))
            } else {
                var shown = 0
                groups.forEach { y ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onToggleYear(y.key to (y.key !in openYears)) }.padding(vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("${if (y.key in openYears) "－" else "＋"} ${y.label}",
                            color = t.inkColor, fontSize = scaledSp(13.5), fontFamily = FontSerif)
                        Text("${y.total}", color = t.inkSoftColor, fontSize = scaledSp(10))
                    }
                    if (y.key in openYears) {
                        y.months.forEach { m ->
                            Row(
                                Modifier.fillMaxWidth().clickable { onToggleMonth(m.key to (m.key !in openMonths)) }.padding(start = 12.dp, top = 4.dp, bottom = 2.dp),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("${if (m.key in openMonths) "－" else "＋"} ${m.label}",
                                    color = t.inkColor, fontSize = scaledSp(12.5), fontFamily = FontSerif)
                                Text("${m.items.size}", color = t.inkSoftColor, fontSize = scaledSp(10))
                            }
                            if (m.key in openMonths) {
                                m.items.forEach { e ->
                                    if (shown < limit) {
                                        shown++
                                        ReflectRow(e, onNote = { onNote(e) }, onEdit = { onEdit(e) }, onDelete = { onDelete(e) })
                                    }
                                }
                            }
                        }
                    }
                }
                if (total > limit) QuietButton("加载更多", onMore)
            }
        }
    }
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun ReflectRow(e: OwnEntry, onNote: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    val t = appTokens()
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 8.dp)) {
        androidx.compose.material3.HorizontalDivider(color = t.lineSoftColor, thickness = 1.dp)
        Spacer(Modifier.height(4.dp))
        Row(
            Modifier.fillMaxWidth().clickable { open = !open },
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(fmtDate(e.createdAt), color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
            Spacer(Modifier.weight(1f))
            if (e.notes.isNotEmpty()) {
                Text("备注 ${e.notes.size}", color = t.inkSoftColor, fontSize = scaledSp(10), fontFamily = FontSans)
            }
            Text(if (open) "−" else "+", color = t.sealColor, fontSize = scaledSp(14), fontFamily = FontSans,
                modifier = Modifier.padding(start = 6.dp))
        }
        Spacer(Modifier.height(2.dp))
        Text(e.text, color = t.inkColor, fontSize = scaledSp(14.5), fontFamily = FontSerif,
            lineHeight = scaledSp(27), maxLines = if (open) 999 else 2,
            overflow = TextOverflow.Ellipsis)
        if (open) {
            if (e.note.isNotEmpty()) NoteLine(e.note)
            e.notes.forEach { NoteLine(it.text) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            QuietButton("加备注", onNote)
            QuietButton("编辑", onEdit)
            QuietButton("删除", onDelete)
        }
    }
}

@Composable
private fun EmptyGuide(onStart: () -> Unit) {
    val t = appTokens()
    Card(modifier = Modifier.padding(top = 14.dp), padded = 28.dp) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Text("从这里开始", color = t.inkStrongColor, fontSize = scaledSp(16), fontFamily = FontSerif, letterSpacing = 2.sp, modifier = Modifier.padding(bottom = 8.dp))
            Text("① 今日写一句鼓励，或一件难过的事\n② 抽签时它会回来，陪你一会儿\n③ 归档后进回忆区，成为第二本日记",
                color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                lineHeight = scaledSp(26), textAlign = TextAlign.Start)
            Spacer(Modifier.height(14.dp))
            PrimaryButton("去今日写一句") { onStart() }
            GhostButton("去句库看看") { com.juxia.app.state.UiState.setTab("library") }
        }
    }
}
