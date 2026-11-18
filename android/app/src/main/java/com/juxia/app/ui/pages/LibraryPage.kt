package com.juxia.app.ui.pages

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.MaterialEntry
import com.juxia.app.model.OwnEntry
import com.juxia.app.model.fmtDate
import com.juxia.app.services.MaterialIndexer
import com.juxia.app.services.MaterialRepair
import com.juxia.app.state.UiState
import com.juxia.app.ui.Blank
import com.juxia.app.ui.Card
import com.juxia.app.ui.GhostButton
import com.juxia.app.ui.Label
import com.juxia.app.ui.PrimaryButton
import com.juxia.app.ui.QuietButton
import com.juxia.app.ui.appTokens
import com.juxia.app.ui.padBottom
import com.juxia.app.ui.scaledSp
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

// 句栖 · 句库页（翻译自 LibraryPage.ets：收藏/回信区/材料库/排除名单/找一句/关联）
// 对齐鸿蒙：内置句库已在 1.0.4 移除，不再有 builtin 来源
private fun originName(o: String): String = when (o) {
    "api" -> "一言"
    "ai" -> "AI"
    "material" -> "材料"
    "own" -> "自己的话"
    else -> "句库"
}

@Composable
fun LibraryPage() {
    val st = Store.instance
    val dataVersion by UiState.dataVersion.collectAsState()
    val t = appTokens()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var qLib by remember { mutableStateOf("") }
    var qReply by remember { mutableStateOf("") }
    var qDis by remember { mutableStateOf("") }
    var replyLimit by remember { mutableIntStateOf(20) }
    var disLimit by remember { mutableIntStateOf(20) }
    var findPick by remember { mutableStateOf("") }
    var findKw by remember { mutableStateOf("") }
    var findText by remember { mutableStateOf("") }
    var findName by remember { mutableStateOf("") }
    var lastFind by remember { mutableStateOf("") }
    var findRunning by remember { mutableStateOf(false) }
    var matName by remember { mutableStateOf("") }
    var matText by remember { mutableStateOf("") }
    var matEditId by remember { mutableStateOf("") }
    var matBusy by remember { mutableStateOf(false) }
    var matProgress by remember { mutableIntStateOf(-1) } // -1 空闲
    var previewId by remember { mutableStateOf("") }
    var previewName by remember { mutableStateOf("") }
    var previewItems by remember { mutableStateOf(listOf<String>()) }
    var previewPick by remember { mutableStateOf(setOf<String>()) }
    var previewBusy by remember { mutableStateOf(false) }
    var relLibId by remember { mutableStateOf("") }
    var matQuery by remember { mutableStateOf("") }
    var relRev by remember { mutableIntStateOf(0) }

    fun replies(): List<OwnEntry> = st.data.own.filter { it.kind == "reply" }.sortedByDescending { it.createdAt }
    fun replySource(r: OwnEntry): String {
        if (r.replyToId.isEmpty()) return "原句已删除"
        val src = st.data.own.find { it.id == r.replyToId }
        return if (src == null) "原句已删除" else src.text
    }
    fun replyKindLabel(r: OwnEntry): String {
        if (r.replyToId.isEmpty()) return ""
        val src = st.data.own.find { it.id == r.replyToId }
        return when (src?.kind) {
            "wound" -> "回的是旧事"
            "encourage" -> "回的是鼓励"
            else -> ""
        }
    }

    fun replyFromLabel(r: OwnEntry): String = when (r.replyFrom) {
        "revisit" -> "回访回信"
        "draw" -> "抽签回信"
        else -> "回信"
    }

    fun replySourceLabel(r: OwnEntry): String {
        val src = st.data.own.find { it.id == r.replyToId }
        return when (src?.kind) {
            "encourage" -> "回的是鼓励"
            "wound" -> "回的是旧事"
            else -> "回的是"
        }
    }
    var replyDeleteTarget by remember { mutableStateOf<OwnEntry?>(null) }
    fun filteredReplies(): List<OwnEntry> {
        val k = qReply.trim().lowercase()
        if (k.isEmpty()) return replies()
        return replies().filter { it.text.lowercase().contains(k) || replySource(it).lowercase().contains(k) }
    }
    fun filteredLibs(): List<com.juxia.app.model.LibEntry> {
        val k = qLib.trim().lowercase()
        val all = st.data.lib
        if (k.isEmpty()) return all
        return all.filter { it.text.lowercase().contains(k) || it.source.lowercase().contains(k) || it.tag.lowercase().contains(k) }
    }
    fun filteredDislikes(): List<com.juxia.app.model.DislikeEntry> {
        val k = qDis.trim().lowercase()
        val all = st.data.dislikes.sortedByDescending { it.at }
        if (k.isEmpty()) return all
        return all.filter { it.text.lowercase().contains(k) || it.source.lowercase().contains(k) }
    }
    fun inDislikes(text: String): Boolean = st.data.dislikes.any { it.text == text }

    /** 文本材料存入：重名同首行去重 → 入库 → 建索引 */
    fun saveMaterialText() {
        val name = matName.trim()
        val text = matText.trim()
        if (name.isEmpty() || text.isEmpty()) { UiState.showToast("材料名和文本都要填"); return }
        if (matBusy) return
        val firstLine = text.lines().firstOrNull { it.isNotBlank() } ?: ""
        if (st.data.materials.any { it.name == name && it.text.isNotEmpty() &&
                (it.text.lines().firstOrNull { l -> l.isNotBlank() } ?: "") == firstLine }) {
            UiState.showToast("这份材料已经在库里了")
            return
        }
        matBusy = true
        scope.launch {
            try {
                val m = st.addMaterial(name, text)
                matProgress = 100
                st.reindexMaterial(m.id, text)
                matName = ""; matText = ""
                UiState.showToast("请稍等，正在保存…")
                UiState.showToast("已存入材料库")
            } catch (e: Exception) {
                UiState.showToast("保存失败，请重试")
            } finally {
                matBusy = false; matProgress = -1
            }
        }
    }

    /** 对齐鸿蒙 findOne：材料洗牌取前 8 份逐份搜，纯文本材料内存兜底，先中先得 */
    fun runFind() {
        if (findRunning) return
        findRunning = true
        scope.launch {
            try {
                val all = st.data.materials
                val list = (if (findPick.isNotEmpty()) all.filter { it.id == findPick } else all.toList()).toMutableList()
                if (list.isEmpty()) { UiState.showToast("没有可用的材料"); return@launch }
                for (i in list.size - 1 downTo 1) {
                    val j = (0..i).random()
                    val tmp = list[i]; list[i] = list[j]; list[j] = tmp
                }
                val kws = findKw.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
                // 对齐鸿蒙：排除名单同样约束材料检索，否则"不喜欢"在这里等于没生效
                val dis = st.dislikedSet()
                var foundText = ""
                var foundName = ""
                for (i in 0 until minOf(list.size, 8)) {
                    val m = list[i]
                    var sents = st.searchMaterial(kws, m.id)
                    if (sents.isEmpty() && m.text.isNotEmpty()) {
                        sents = com.juxia.app.utils.splitSentences(m.text).filter { s ->
                            kws.isEmpty() || kws.all { it in s }
                        }
                    }
                    sents = sents.filter { it.isNotEmpty() && !dis.contains(it) }
                    if (sents.isEmpty()) continue
                    var pick = sents.random()
                    // 对齐鸿蒙：避免连着两次抽到同一句
                    if (sents.size > 1 && pick == lastFind) pick = sents.random()
                    foundText = pick
                    foundName = "摘自《" + m.name.trimStart('《').trimEnd('》') + "》"
                    break
                }
                if (foundText.isNotEmpty()) lastFind = foundText
                if (foundText.isEmpty()) {
                    if (findPick.isNotEmpty()) UiState.showToast("这份材料里没有可抽取的句子")
                    else UiState.showToast("没有找到同时含「${findKw.trim()}」的句子，换个关键词试试")
                } else {
                    findText = foundText
                    findName = foundName
                }
            } finally {
                findRunning = false
            }
        }
    }

    /** 材料编辑保存：改名/正文 + 重建索引 */
    suspend fun doSaveEdit() {
        val name = matName.trim()
        val text = matText.trim()
        if (name.isEmpty() || text.isEmpty()) { UiState.showToast("材料名和文本都要填"); return }
        matBusy = true
        try {
            st.updateMaterial(matEditId, name, text)
            st.reindexMaterial(matEditId, text)
            matEditId = ""; matName = ""; matText = ""
            UiState.showToast("已保存")
        } catch (e: Exception) {
            UiState.showToast("保存失败，请重试")
        } finally {
            matBusy = false
        }
    }

    /** 文件导入：复制（带进度）→ .indexing 标记 → 流式索引 → 失败整份回滚 */
    fun importFile(uri: android.net.Uri) {
        if (matBusy) return
        matBusy = true
        matProgress = 0
        scope.launch {
            var m: com.juxia.app.model.MaterialEntry? = null
            var dest = ""
            try {
                val stamp = System.currentTimeMillis()
                val dir = java.io.File(ctx.filesDir, "materials")
                dir.mkdirs()
                dest = java.io.File(dir, "mat_$stamp.txt").absolutePath
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    ctx.contentResolver.openInputStream(uri)?.use { input ->
                        java.io.File(dest).outputStream().buffered(64 * 1024).use { output ->
                            val buf = ByteArray(64 * 1024)
                            var total = 0L
                            var last = 0
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                output.write(buf, 0, n)
                                total += n
                                val p = minOf(99, (total / (1024 * 20)).toInt())
                                if (p != last) { last = p; matProgress = p }
                            }
                        }
                    } ?: throw java.io.IOException("open failed")
                }
                val size = java.io.File(dest).length()
                if (size <= 0L || size > 64L * 1024 * 1024) throw java.io.IOException("size")
                com.juxia.app.services.MaterialRepair.mark(dest)
                m = st.addMaterialFile(uri.lastPathSegment ?: "材料", dest, size)
                matProgress = 100
                val ok = st.indexMaterial(m!!.id)
                if (!ok) throw java.io.IOException("index failed")
                com.juxia.app.services.MaterialRepair.clear(dest)
                UiState.showToast("已导入并完成索引")
            } catch (e: Exception) {
                val indexed = m != null
                try { m?.let { st.deleteMaterial(it.id) } } catch (_: Exception) {}
                try { if (dest.isNotEmpty()) java.io.File(dest).delete() } catch (_: Exception) {}
                UiState.showToast(if (indexed) "索引失败" else "导入失败，请重试")
            } finally {
                matBusy = false; matProgress = -1
            }
        }
    }

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) importFile(uri)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = padBottom())
    ) {
        // 找一句
        Label("取一句")
        Card {
            Text("从我的材料找一句", color = t.inkStrongColor, fontSize = scaledSp(15.5), fontFamily = FontSerif,
                modifier = Modifier.padding(bottom = 8.dp))
            Text("收藏和材料检索都可以取一句；应用不自带句子，内容由你自己加入。",
                color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(24))
            Spacer(Modifier.height(8.dp))
            Text((if (findPick.isEmpty()) "全部材料" else "材料：" + (st.data.materials.find { it.id == findPick }?.name ?: "")) + (if (st.data.materials.isEmpty()) "\n材料库还是空的，先粘贴一段文本" else ""),
                color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
            Spacer(Modifier.height(4.dp))
            com.juxia.app.ui.PaperInput(value = findKw, onChange = { findKw = it },
                placeholder = "关键词（可空）", multiLine = false)
            Text("关键词用空格隔开，表示全部包含；留空则随机抽一句。",
                color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
                modifier = Modifier.padding(top = 4.dp))
            Text("一、断句：空行分隔句子；单个换行按空格处理；段内句号不再单独切。\n二、长度：不按字数判断是不是句子；长句在卡片里可以滚动查看。\n三、关键词：多个词用空格隔开 = 必须全部出现。\n四、原则：全程在本机完成，不联网、不改写，抽出来的一定是原文，并注明材料名。",
                color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans,
                lineHeight = scaledSp(18), modifier = Modifier.padding(top = 6.dp))
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GhostButton("选材料") {
                    val ids = listOf("") + st.data.materials.map { it.id }
                    val idx = ids.indexOf(findPick)
                    findPick = ids[(idx + 1) % ids.size]
                }
                PrimaryButton(if (findRunning) "正在取…" else "找一句") { runFind() }
            }
            if (findText.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text(findText, color = t.inkStrongColor, fontSize = scaledSp(16), fontFamily = FontSerif, lineHeight = scaledSp(30))
                Spacer(Modifier.height(4.dp))
                // 对齐鸿蒙：「摘自《材料名》 · 原文检索」
                Text("$findName · 原文检索", color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans, letterSpacing = 2.sp)
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton("收入句库") {
                        if (st.addLib(findText, findName, "material", "原文 · 材料检索")) UiState.showToast("已收入句库")
                        else UiState.showToast("句库里已有这句")
                    }
                    GhostButton("再找一句") { runFind() }
                    QuietButton("不喜欢") {
                        st.addDislike(findText, findName, "material")
                        findText = ""
                        UiState.showToast("已加入排除名单")
                    }
                }
            }
        }

        // 我的收藏
        Label("我的收藏")
        com.juxia.app.ui.PaperInput(value = qLib, onChange = { qLib = it },
            placeholder = "搜索：句子、出处或标签", multiLine = false)
        Spacer(Modifier.height(8.dp))
        val libs = filteredLibs()
        if (libs.isEmpty()) {
            Column {
                Text(if (qLib.isNotEmpty()) "换个词试试。"
                     else if (st.data.lib.isEmpty()) "还没有收藏。去材料库找一句；也可以自己写。"
                     else "还没有收藏", color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans)

            }
        } else {
            Card(padded = 0.dp) {
                Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                    libs.forEach { e ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                            Text(e.text, color = t.inkStrongColor, fontSize = scaledSp(16), fontFamily = FontSerif,
                                lineHeight = scaledSp(32))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    if (e.source.isNotEmpty()) e.source else "无出处",
                                    color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans,
                                    letterSpacing = 1.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(e.tag, color = t.sealColor, fontSize = scaledSp(10), fontFamily = FontSans,
                                    letterSpacing = 1.sp, maxLines = 1,
                                    modifier = Modifier
                                        .background(t.sealSoftColor, RoundedCornerShape(999.dp))
                                        .padding(horizontal = 9.dp, vertical = 2.dp))
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                QuietButton("移出句库") {
                                    st.removeLib(e.id)
                                    UiState.showToast("已移出句库")
                                }
                                QuietButton("不喜欢") {
                                    st.addDislike(e.text, e.source, e.origin)
                                    UiState.showToast("已加入排除名单，句库里的这条也一并移出了")
                                }
                                QuietButton("关联") { relLibId = e.id; relRev++ }
                            }
                        }
                    }
                }
            }
        }

        // 回信区
        Label("回信区 ${replies().size}")
        com.juxia.app.ui.PaperInput(value = qReply, onChange = { qReply = it; replyLimit = 20 },
            placeholder = "搜索回信或原句", multiLine = false)
        Spacer(Modifier.height(8.dp))
        val reps = filteredReplies()
        if (reps.isEmpty()) {
            Text("还没有回信。抽到自己的句子时，可以回一句话。",
                color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans)
        } else {
            Card(padded = 0.dp) {
                Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                    reps.take(replyLimit).forEach { r ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                            Text(r.text, color = t.inkStrongColor, fontSize = scaledSp(14.5), fontFamily = FontSerif,
                                lineHeight = scaledSp(28))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(replyFromLabel(r), color = t.sealInkColor, fontSize = scaledSp(9.5),
                                    fontFamily = FontSans, maxLines = 1,
                                    modifier = Modifier
                                        .background(t.sealColor, RoundedCornerShape(999.dp))
                                        .padding(horizontal = 8.dp, vertical = 2.dp))
                                Spacer(Modifier.width(6.dp))
                                if (replySource(r).isNotEmpty()) {
                                    Text("${replySourceLabel(r)}：${replySource(r)}",
                                        color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans,
                                        lineHeight = scaledSp(21), maxLines = 2, overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f))
                                } else {
                                    Text("原句已删除", color = t.inkSoftColor, fontSize = scaledSp(11),
                                        fontFamily = FontSans, modifier = Modifier.weight(1f))
                                }
                                Text("删除", color = t.sealColor, fontSize = scaledSp(11), fontFamily = FontSans,
                                    modifier = Modifier
                                        .clickable { replyDeleteTarget = r }
                                        .padding(start = 8.dp, top = 4.dp, bottom = 4.dp))
                            }
                            Text(listOf(replyKindLabel(r), fmtDate(r.createdAt)).filter { it.isNotEmpty() }.joinToString(" · "),
                                color = t.inkSoftColor, fontSize = scaledSp(10), fontFamily = FontSans)
                        }
                    }
                    if (reps.size > replyLimit) QuietButton("加载更多") { replyLimit += 20 }
                }
            }
        }

        // 材料库
        Label("材料库")
        Card {
            Text("支持 UTF-8 / UTF-16 / GB18030 的 .txt 和 Markdown（.md / .markdown）文本。可以直接导入原始文本；句栖会按空行分句入库。",
                color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans, lineHeight = scaledSp(22))
            Text("材料只存在本机。检索时只抽原文并注明材料名，不编造。没有固定大小上限，但大文件（数 MB 以上）导入与检索都会明显变慢，建议拆成多份。",
                color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans, lineHeight = scaledSp(20),
                modifier = Modifier.padding(top = 6.dp))
            Text("材料只存在本机。检索时只抽原文并注明材料名，不编造。没有固定大小上限，但大文件（数 MB 以上）导入与检索都会明显变慢，建议拆成多份。",
                color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans, lineHeight = scaledSp(20),
                modifier = Modifier.padding(top = 6.dp))
            Spacer(Modifier.height(8.dp))
            if (matProgress >= 0) {
                Text(if (matProgress < 100) "正在复制文件… $matProgress%" else "请稍等，正在建立句子索引…",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
            }
            com.juxia.app.ui.PaperInput(value = matName, onChange = { matName = it },
                placeholder = "材料名", multiLine = false)
            Spacer(Modifier.height(6.dp))
            com.juxia.app.ui.PaperInput(value = matText, onChange = { matText = it },
                placeholder = "粘贴文本（或选择 .txt / .md 文件）")
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton(if (matBusy) "请稍等，正在保存…" else (if (matEditId.isNotEmpty()) "保存修改" else "存入材料库"), Modifier.weight(1f)) {
                        if (matEditId.isNotEmpty()) { scope.launch { doSaveEdit() } } else saveMaterialText() }
                    if (matEditId.isNotEmpty()) QuietButton("取消编辑") { matEditId = ""; matName = ""; matText = "" }
                }
                GhostButton("选择 .txt / .md 文件") { filePicker.launch(arrayOf("text/*", "text/markdown", "application/octet-stream")) }
            }
            Spacer(Modifier.height(8.dp))
            com.juxia.app.ui.PaperInput(value = matQuery, onChange = { matQuery = it },
                placeholder = "搜索材料：名称或内容", multiLine = false)
            Spacer(Modifier.height(6.dp))
            val matShown = st.data.materials.filter {
                matQuery.isEmpty() || it.name.contains(matQuery) || it.text.contains(matQuery)
            }
            if (matShown.isEmpty()) {
                Text(if (matQuery.isNotEmpty()) "没有找到。换个词，或清空搜索。" else "材料库还是空的。把你的摘抄、某本书的文本粘贴进来，或选择一个 .txt / .md 文件。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
            }
            matShown.forEach { m ->
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f).clickable {
                        previewId = m.id; previewName = m.name; previewPick = emptySet()
                        scope.launch {
                            previewBusy = true
                            previewItems = st.materialSentences(m.id)
                            previewBusy = false
                        }
                    }) {
                        Text(m.name, color = t.inkStrongColor, fontSize = scaledSp(14.5), fontFamily = FontSerif)
                        Text(if (m.path.isNotEmpty()) "文件材料 · 已建立句子索引" else "${m.text.length} 字",
                            color = t.inkSoftColor, fontSize = scaledSp(10.5), fontFamily = FontSans)
                    }
                    QuietButton("预览") {
                        previewId = m.id; previewName = m.name; previewPick = emptySet()
                        scope.launch {
                            previewBusy = true
                            previewItems = st.materialSentences(m.id)
                            previewBusy = false
                        }
                    }
                    QuietButton("编辑") {
                        matEditId = m.id
                        matName = m.name
                        matText = if (m.path.isNotEmpty()) runCatching { com.juxia.app.services.MaterialIndexer.readText(m.path) }.getOrDefault("") else m.text
                    }
                    QuietButton("删除") {
                        scope.launch {
                            st.deleteMaterial(m.id)
                            if (m.path.isNotEmpty()) try { File(m.path).delete() } catch (_: Exception) {}
                            UiState.showToast("已删除")
                        }
                    }
                }
            }
            // 预览挑选
            if (previewId.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text("材料收藏句子", color = t.inkStrongColor, fontSize = scaledSp(13), fontFamily = FontSerif)
                Text(previewName, color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                if (previewBusy) Text("正在读取句子…", color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Column(Modifier.heightIn(max = 260.dp).verticalScroll(rememberScrollState())) {
                    previewItems.take(200).forEach { s ->
                        val picked = s in previewPick
                        val disabled = st.data.lib.any { it.text == s } || inDislikes(s)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .clickable(enabled = !disabled) {
                                    previewPick = if (picked) previewPick - s else previewPick + s
                                }
                                .padding(vertical = 6.dp)
                        ) {
                            Checkbox(checked = picked, enabled = !disabled, onCheckedChange = {
                                previewPick = if (it) previewPick + s else previewPick - s
                            })
                            Text(s, color = if (disabled) t.inkSoftColor else t.inkColor,
                                fontSize = scaledSp(13.5), fontFamily = FontSerif,
                                maxLines = 2, overflow = TextOverflow.Ellipsis)
                            if (disabled) Text(
                                if (st.data.lib.any { it.text == s }) "已在句库" else "已在排除名单",
                                color = t.inkSoftColor, fontSize = scaledSp(10), fontFamily = FontSans)
                        }
                    }
                }
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton(if (previewBusy) "收藏中…" else "收藏选中") {
                        var added = 0
                        previewPick.forEach { s ->
                            if (st.addLib(s, "摘自《${previewName.trimStart('《').trimEnd('》')}》", "material", "材料收藏")) added++
                        }
                        previewId = ""
                        UiState.showToast(if (added > 0) "已材料收藏 $added 句" else "这些句子已在句库里")
                    }
                    if (previewItems.isEmpty() && !previewBusy) {
                        Text("这份材料还没有切出句子。", color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
                    }
                    QuietButton("全选") { previewPick = previewItems.take(200).toSet() }
                    QuietButton("清空选择") { previewPick = emptySet() }
                }
            }
        }

        // 排除名单
        Label("排除名单")
        com.juxia.app.ui.PaperInput(value = qDis, onChange = { qDis = it; disLimit = 20 },
            placeholder = "搜索排除名单", multiLine = false)
        Spacer(Modifier.height(8.dp))
        val dis = filteredDislikes()
        if (dis.isEmpty()) {
            Text("还没有排除任何句子。点「不喜欢」会记到这里，不再出现在抽签与收藏里。",
                color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans)
        } else {
            Card(padded = 0.dp) {
                Column(Modifier.heightIn(max = 260.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                    dis.take(disLimit).forEach { dd ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                            Text(dd.text, color = t.inkStrongColor, fontSize = scaledSp(14.5), fontFamily = FontSerif, lineHeight = scaledSp(27))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(originName(dd.origin), color = t.inkSoftColor, fontSize = scaledSp(10), fontFamily = FontSans)
                                Spacer(Modifier.padding(6.dp))
                                QuietButton("撤销排除") {
                                    st.removeDislike(dd.text)
                                    UiState.showToast("已撤销排除，它又能出现了")
                                }
                            }
                        }
                    }
                    if (dis.size > disLimit) QuietButton("加载更多") { disLimit += 20 }
                }
            }
        }

        Text("句库数据只存在这台设备上（自己导出的数据除外，取决于自己存放的位置）",
            color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
            modifier = Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 8.dp))
        Blank()
    }

    // 关联面板
    if (relLibId.isNotEmpty()) {
        val libEntry = st.data.lib.find { it.id == relLibId }
        com.juxia.app.ui.AppSheet(onClose = { relLibId = "" }) {
            Text("关联到自己的话", color = t.inkStrongColor, fontSize = scaledSp(17), fontFamily = FontSerif)
            Spacer(Modifier.height(8.dp))
            Text(libEntry?.text ?: "", color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSerif,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text("这条收藏可以同时关联自己的鼓励和旧事。点一下切换。",
                color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
            val relCand = st.data.own.filter { it.kind != "reply" && !it.isArchived() }
            if (relCand.isEmpty()) {
                Text("你还没有写过鼓励或旧事，先去今日页写一句。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
            }
            Spacer(Modifier.height(10.dp))
            relRev.let { }
            relCand.forEach { o ->
                val bound = libEntry?.bindIds?.contains(o.id) == true
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(o.text.take(18) + if (o.text.length > 18) "…" else "",
                        color = t.inkColor, fontSize = scaledSp(14), fontFamily = FontSerif)
                    if (libEntry != null) {
                        if (bound) PrimaryButton("解绑") { st.toggleLibBind(libEntry.id, o.id); relRev++ }
                        else GhostButton("绑定") { st.toggleLibBind(libEntry.id, o.id); relRev++ }
                    }
                }
            }
        }
    }

    // 回信删除确认
    replyDeleteTarget?.let { r ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { replyDeleteTarget = null },
            title = { Text("删除这条回信？", fontFamily = FontSerif) },
            text = { Text("只会删除这条回信，不会删除它回的原句。删除后无法恢复。", fontFamily = FontSans) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    st.removeOwn(r.id)
                    replyDeleteTarget = null
                    UiState.showToast("回信已删除")
                }) { Text("删除", color = t.sealColor) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { replyDeleteTarget = null }) { Text("取消") }
            }
        )
    }
}
