package com.juxia.app.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.model.DAY_MS
import com.juxia.app.model.OwnEntry
import com.juxia.app.model.RitualCtx
import com.juxia.app.model.fmtMD
import com.juxia.app.services.ReminderService
import com.juxia.app.state.UiState
import com.juxia.app.ui.Blank
import com.juxia.app.ui.Card
import com.juxia.app.ui.GhostButton
import com.juxia.app.ui.Label
import com.juxia.app.ui.MoodIcons
import com.juxia.app.ui.PrimaryButton
import com.juxia.app.ui.QuietButton
import com.juxia.app.ui.appTokens
import com.juxia.app.ui.padBottom
import com.juxia.app.ui.scaledSp
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import com.juxia.app.ui.theme.argb

// 句栖 · 今日页（翻译自 TodayPage.ets；2026-11-16 全文按原版重写——此前版本系读屏转述，文案与流程有漂移，已更正）
@Composable
fun TodayPage() {
    val st = Store.instance
    val dataRev by UiState.dataVersion.collectAsState()
    val t = appTokens()
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val skin by UiState.skin.collectAsState()

    // —— 状态（与 ArkTS @State 一一对应） ——
    var mood by remember { mutableStateOf("") }
    var wrote by remember { mutableStateOf(false) }
    var drew by remember { mutableStateOf(false) }
    var choice by remember { mutableStateOf("") } // "" / write / draw
    var inputText by remember { mutableStateOf("") }
    var draftRestored by remember { mutableStateOf(false) }
    var showGuide by remember { mutableStateOf(false) }
    var sheetOpen by remember { mutableStateOf(false) }
    var sheetMode by remember { mutableStateOf("") } // write / draw / source
    var writeKind by remember { mutableStateOf("encourage") }
    var revisit by remember { mutableStateOf(listOf<OwnEntry>()) }
    var replyOpenId by remember { mutableStateOf("") }
    var replyText by remember { mutableStateOf("") }
    var encCount by remember { mutableIntStateOf(0) }
    var woundCount by remember { mutableIntStateOf(0) }
    var libCount by remember { mutableIntStateOf(0) }
    var needSource by remember { mutableStateOf(false) }
    var seen by remember { mutableStateOf(true) }
    var backupDismissed by remember { mutableStateOf(false) }
    var lastText by remember { mutableStateOf("") }

    fun load() {
        val d = st.data.day
        mood = d.mood; wrote = d.wrote; drew = d.drew
        seen = st.data.meta.seen
        backupDismissed = d.backupDismissed
        encCount = st.ownActive("encourage").size
        woundCount = st.ownActive("wound").size
        libCount = st.libPool().size
        needSource = (!st.data.settings.drawOwn || (encCount == 0 && woundCount == 0)) &&
            (!st.data.settings.drawLib || libCount == 0)
        revisit = st.revisitDue(System.currentTimeMillis())
    }

    androidx.compose.runtime.LaunchedEffect(dataRev) { load() }

    // 会话内滴答：跨过回访时刻/午夜无需退后台即刷新（60s 粒度足够）
    androidx.compose.runtime.LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(60_000)
            load()
        }
    }

    fun setMood(m: String) {
        // 对齐鸿蒙：仅心情变化时重置写/抽状态；重复点同一心情不动
        if (m != mood) {
            st.data.day.mood = m
            st.data.day.wrote = false
            st.data.day.drew = false
            choice = ""
            st.saveKv()
        }
        load()
    }
    fun primaryDrawKind(): String = if (mood == "bad") "encourage" else "wound"
    fun writeKind(): String = if (mood == "bad") "wound" else "encourage"

    fun pickOwn(kind: String): OwnEntry? {
        val pool = st.ownActive(kind)
        if (pool.isEmpty()) return null
        if (pool.size == 1) return pool[0]
        var x: OwnEntry
        var guard = 0
        do { x = pool.random(); guard++ } while (guard < 20 && x.text == lastText)
        lastText = x.text
        return x
    }
    fun pickLib(): com.juxia.app.model.LibEntry? {
        val pool = st.libPool()
        if (pool.isEmpty()) return null
        if (pool.size == 1) return pool[0]
        var x: com.juxia.app.model.LibEntry
        var guard = 0
        do { x = pool.random(); guard++ } while (guard < 20 && x.text == lastText)
        lastText = x.text
        return x
    }

    fun draw(kind: String, fallbackLib: Boolean = false) {
        if (kind == "encourage" || kind == "wound") {
            val entry = pickOwn(kind)
            if (entry == null || (!st.data.settings.drawOwn && !fallbackLib)) {
                // 自己的话不可抽 → 句库兜底或引导
                if (fallbackLib || st.data.settings.drawLib) {
                    val lib = pickLib()
                    if (lib == null) {
                        if (needSource) { sheetMode = "source"; sheetOpen = true } else UiState.showToast("句库里没有可以抽的句子")
                        return
                    }
                    UiState.startRitual(RitualCtx(type = "lib", badge = "句库 · 取一句", tag = "原文",
                        text = lib.text, source = lib.source, origin = lib.origin, todayFlow = true))
                    return
                }
                if (needSource) { sheetMode = "source"; sheetOpen = true } else UiState.showToast("还没有可以抽的句子")
                return
            }
            val badge = if (kind == "encourage") "自己的话 · 鼓励" else "自己的话 · 一件旧事"
            UiState.startRitual(RitualCtx(type = "own", badge = badge, tag = "自己写的", entry = entry, todayFlow = true))
        } else {
            val lib = pickLib()
            if (lib == null) {
                if (needSource) { sheetMode = "source"; sheetOpen = true } else UiState.showToast("句库里没有可以抽的句子")
                return
            }
            val badge = if (kind == "lib") "句库 · 收藏" else "句库 · 取一句"
            UiState.startRitual(RitualCtx(type = "lib", badge = badge, tag = "原文",
                text = lib.text, source = lib.source, origin = lib.origin, todayFlow = true))
        }
    }

    fun openSheet(mode: String) {
        if (mode == "write") {
            writeKind = writeKind()
            draftRestored = false
            sheetMode = "write"
        } else sheetMode = mode
        sheetOpen = true
    }
    fun startMoreWrite(kind: String) {
        sheetOpen = false
        writeKind = kind
        choice = "write"
        inputText = ""
        draftRestored = false
    }
    fun startMoreDraw(kind: String) {
        sheetOpen = false
        draw(kind, true)
    }
    fun queueDraft() {
        st.saveDraft("today_write_" + writeKind, inputText)
    }
    fun loadDraft() {
        if (!draftRestored) {
            val v = st.loadDraft("today_write_" + writeKind)
            if (v.isNotEmpty()) {
                inputText = v
                UiState.showToast("已恢复未保存的草稿")
            }
            draftRestored = true
        }
    }
    fun doWrite() {
        val text = inputText.trim()
        if (text.isEmpty()) { UiState.showToast("先写一句，哪怕很短"); return }
        st.addOwn(writeKind, text)
        st.data.day.wrote = true
        st.clearDraft("today_write_" + writeKind)
        st.saveKv()
        inputText = ""
        showGuide = false
        load()
        UiState.showToast(if (writeKind == "encourage") "收好了。低谷的日子，它会回来找你" else "写下来了，就已经轻了一点")
    }
    fun skipDraw() {
        st.markDrew()
        load()
        UiState.showToast("好，今天先到这儿。")
    }
    fun calm(id: String) {
        st.data.own.find { it.id == id }?.let {
            it.revisitAt = 0; it.snoozeUntil = 0
            st.addNote(id, "回访：已经平静。")
        }
        st.persist()
        ReminderService.rescheduleAll(ctx)
        load()
        UiState.showToast("它留在回忆区，安安稳稳")
    }
    fun back(id: String) {
        st.revive(id)
        ReminderService.rescheduleAll(ctx)
        load()
        UiState.showToast("回到台前了，慢慢消化，不急")
    }
    fun wait(id: String) {
        st.snoozeRevisit(id, 30)
        ReminderService.rescheduleAll(ctx)
        load()
        UiState.showToast("好，30 天后再问")
    }
    fun saveRevisitReply(id: String) {
        val text = replyText.trim()
        if (text.isEmpty()) { UiState.showToast("先写一句，再回一句话"); return }
        if (!st.addReply(id, text, "revisit")) { UiState.showToast("这句话没有保存成功，再试一次"); return }
        replyText = ""
        replyOpenId = ""
        load()
        UiState.showToast("回好了，收进句库的「回信」里")
    }
    fun goLibrary() { UiState.setTab("library") }
    fun goSettings() { UiState.setTab("settings") }
    fun catName(c: String): String = st.catLabel(c)
    fun backupNeed(): Boolean {
        return !st.data.settings.backupRemindOff &&
            (st.data.own.size + st.data.lib.size >= 3) && !backupDismissed &&
            (st.data.meta.lastBackupAt == 0L ||
                System.currentTimeMillis() - st.data.meta.lastBackupAt > 14 * DAY_MS)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = padBottom())
    ) {
        if (revisit.isNotEmpty()) Label("轻轻的回访")
        revisit.forEach { e ->
            Card(modifier = Modifier.padding(bottom = 14.dp)) {
                Text("你曾在 ${fmtMD(e.archAt)} 把这件事标记为「${catName(e.archCat)}」，约定这时轻轻问一次：",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(23))
                Text(e.text, color = t.inkStrongColor, fontSize = scaledSp(16.5), fontFamily = FontSerif,
                    lineHeight = scaledSp(32), modifier = Modifier.padding(vertical = 10.dp))
                Text("现在想起它，感觉怎么样？", color = t.inkSoftColor, fontSize = scaledSp(12.5),
                    fontFamily = FontSans, modifier = Modifier.padding(bottom = 12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    GhostButton("已经平静") { calm(e.id) }
                    GhostButton("还没好，回到台前") { back(e.id) }
                    QuietButton("再等等") { wait(e.id) }
                    QuietButton("回一句话") { replyOpenId = e.id; replyText = "" }
                }
                if (replyOpenId == e.id) {
                    Column(Modifier.padding(top = 8.dp)) {
                        com.juxia.app.ui.PaperInput(value = replyText, onChange = { replyText = it },
                            placeholder = "不用写完整，回一句话就好")
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            GhostButton("取消") { replyOpenId = ""; replyText = "" }
                            PrimaryButton("保存回信") { saveRevisitReply(e.id) }
                        }
                    }
                }
            }
        }

        if (!seen) {
            Card(padded = 30.dp, modifier = Modifier.padding(top = 14.dp)) {
                Text("开始我们的第一次树洞吧", color = t.inkStrongColor, fontSize = scaledSp(20),
                    fontFamily = FontSerif, letterSpacing = 4.sp, modifier = Modifier.padding(bottom = 14.dp))
                Text("每天可以写一句：心情好时写一句鼓励自己的，心情糟时写下那件让你难过的事。\n也可以抽一句自己的话——低谷时抽鼓励，平顺时抽旧事来消化。写和抽，没有先后。\n没有句子时，可以自己写，或从材料库加入。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(28))
                Row(Modifier.fillMaxWidth().padding(top = 18.dp), horizontalArrangement = Arrangement.Center) {
                    PrimaryButton("好，开始") {
                        st.data.meta.seen = true
                        st.saveSettings()
                        load()
                    }
                }
            }
        }

        if (needSource && seen) {
            Card(modifier = Modifier.padding(top = 0.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("第一句，可以从这里开始", color = t.inkStrongColor, fontSize = scaledSp(17),
                        fontFamily = FontSerif, letterSpacing = 2.sp)
                    Text("写一句自己的话；也可以从材料库或句库加入。",
                        color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                        lineHeight = scaledSp(23))
                    // 鸿蒙是 Flex 换行；Android 用两行避免三个按钮挤在一条线上被裁切。
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GhostButton("写一句") { openSheet("write") }
                        GhostButton("去材料库 / 句库") { goLibrary() }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GhostButton("去设置") { goSettings() }
                    }
                }
            }
        }

        if (st.data.settings.showGreeting && st.data.settings.nickname.isNotEmpty()) {
            Text("你好，${st.data.settings.nickname}", color = t.inkStrongColor, fontSize = scaledSp(17),
                fontFamily = FontSerif, modifier = Modifier.padding(vertical = 2.dp))
        }

        Label("今天，心里是什么天气")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            MoodCard("good", "今天还不错", "存一句鼓励", "可处理一件旧事", mood == "good", Modifier.weight(1f)) { setMood("good") }
            MoodCard("bad", "今天有点糟", "树洞写下来", "抽一句陪着你", mood == "bad", Modifier.weight(1f)) { setMood("bad") }
        }

        if (mood.isNotEmpty() && !wrote && !drew && choice.isEmpty()) {
            Card {
                Text("今天，想先做哪一件？", color = t.inkStrongColor, fontSize = scaledSp(15),
                    fontFamily = FontSerif, modifier = Modifier.fillMaxWidth())
                Text("写一句和抽一句，没有先后。想做哪个就点哪个。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans,
                    lineHeight = scaledSp(21),
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton("写一句", Modifier.weight(1f)) { choice = "write" }
                    GhostButton("抽一句", Modifier.weight(1f)) { choice = "draw"; draw(primaryDrawKind(), true) }
                }
                Text("不写也没关系，不抽也没关系。这里没有打卡，也没有必须完成的事。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
                    lineHeight = scaledSp(19),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
            }
            Card(padded = 18.dp, modifier = Modifier.padding(top = 12.dp, bottom = 12.dp)) {
                Text("今天，不必完成什么", color = t.inkStrongColor, fontSize = scaledSp(14),
                    fontFamily = FontSerif, modifier = Modifier.fillMaxWidth())
                Text("写一句、抽一句，都只是选项，不是任务。这里没有连续打卡，也不会催你。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans,
                    lineHeight = scaledSp(21),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
                Row(Modifier.fillMaxWidth().padding(top = 2.dp)) {
                    GhostButton("去句库随便看看") { goLibrary() }
                }
            }
        }

        if (mood.isNotEmpty() && !wrote && (choice == "write" || drew)) {
            Label(if (writeKind == "encourage") "写一句鼓励自己的话" else "把让你难过的事写下来")
            Card {
                androidx.compose.runtime.LaunchedEffect(writeKind) { loadDraft() }
                com.juxia.app.ui.PaperInput(
                    value = inputText,
                    onChange = { inputText = it; queueDraft() },
                    placeholder = if (writeKind == "encourage") "认真夸自己一句，哪怕很小" else "不用完整，不用体面，写下来就好"
                )
                if (writeKind == "encourage") {
                    QuietButton("写不出来？换个视角") { showGuide = !showGuide }
                    if (showGuide) {
                        Text("如果你的家人或朋友正处在低谷，你会说什么？",
                            color = t.sealColor, fontSize = scaledSp(13), fontFamily = FontSerif,
                            modifier = Modifier.padding(vertical = 8.dp))
                    }
                } else {
                    Text("不用着急，也不用写得好。这里没有别人，想到哪写到哪，我陪你慢慢写。",
                        color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                        modifier = Modifier.padding(top = 6.dp))
                }
                Spacer(Modifier.height(14.dp))
                if (writeKind == "encourage") {
                    PrimaryButton("收进${st.data.settings.appName}", Modifier.fillMaxWidth()) { doWrite() }
                } else {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        PrimaryButton("放进树洞", Modifier.weight(1f)) { doWrite() }
                        QuietButton("不写，先抽一句") { draw("lib", true) }
                    }
                }
            }
        }

        if (mood.isNotEmpty() && !drew && (wrote || choice == "draw")) {
            Label(if (mood == "bad") "现在，抽一句陪自己待一会儿" else "平顺的日子，适合消化一件旧事")
            Card {
                if (mood == "bad") {
                    Text(if (!st.data.settings.drawOwn) "自己的话暂时不参与抽签。可以从句库取一句。"
                         else if (encCount > 0) "从你写过的 $encCount 句鼓励里，抽一句还给今天的你。"
                         else "你的鼓励池还是空的——这次先从句库取一句给你。等你写下第一句自己的鼓励，它就会回到抽签里。",
                        color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                        lineHeight = scaledSp(24), modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (st.data.settings.drawOwn) PrimaryButton("抽签") { draw("encourage") }
                        else if (st.data.settings.drawLib) PrimaryButton("从句库抽一句") { draw("lib", true) }
                        QuietButton("再写一句") { openSheet("write") }
                    }
                } else {
                    if (woundCount > 0) {
                        Text(if (st.data.settings.drawOwn) "树洞里有 $woundCount 件还没消化的事。要不要抽一件，趁有能量时看看它？"
                             else "树洞里有 $woundCount 件还没消化的事，但自己的话暂时不参与抽签。可以去「设置」打开，或从句库取一句。",
                            color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                            lineHeight = scaledSp(24), modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (st.data.settings.drawOwn) PrimaryButton("抽一件旧事") { draw("wound") }
                            else if (st.data.settings.drawLib) PrimaryButton("从句库抽一句") { draw("lib", true) }
                            QuietButton("看了标题就有点累，今天先不处理") { skipDraw() }
                            QuietButton("再写一句") { openSheet("write") }
                        }
                    } else {
                        Text(if (st.data.settings.drawLib) "树洞是空的，没有积压的旧事——这本身就是好事。也可以从句库抽一句，给今天收个尾。"
                             else "树洞是空的，没有积压的旧事——这本身就是好事。句库暂时不参与抽签，可以再写一句。",
                            color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans,
                            lineHeight = scaledSp(24), modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (st.data.settings.drawLib) GhostButton("从句库抽一句") { draw("lib", true) }
                            QuietButton("再写一句") { openSheet("write") }
                        }
                    }
                }
            }
        }

        if (mood.isNotEmpty() && wrote && drew) {
            Card(padded = 30.dp, modifier = Modifier.padding(top = 4.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text("今天的一句话，已经收好了", color = t.inkStrongColor, fontSize = scaledSp(15.5),
                        fontFamily = FontSerif, letterSpacing = 3.sp)
                    Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        GhostButton("再抽一句") { openSheet("draw") }
                        GhostButton("再写一句") { openSheet("write") }
                    }
                }
            }
        }

        if (backupNeed()) {
            Card(padded = 18.dp, modifier = Modifier.padding(top = 10.dp)) {
                Text(if (st.data.meta.lastBackupAt > 0) "距离上次备份已超过 14 天——这里的一切只存在这台设备上（自己导出的数据除外，取决于自己存放的位置），清理数据就会消失。花一分钟做个密语备份吧。"
                     else "你还没做过备份——这里的一切只存在这台设备上（自己导出的数据除外，取决于自己存放的位置），清理数据就会全部消失。花一分钟做个密语备份吧。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans, lineHeight = scaledSp(22))
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    GhostButton("去备份") { goSettings() }
                    QuietButton("今天别再提醒") {
                        backupDismissed = true
                        st.data.day.backupDismissed = true
                        st.saveKv()
                    }
                }
            }
        }

        Blank()
    }

    // —— 底部单（write / draw / source 三模式） ——
    if (sheetOpen) {
        com.juxia.app.ui.AppSheet(onClose = { sheetOpen = false }) {
            Text(when (sheetMode) {
                    "write" -> if (wrote) "再写一句" else "写一句"
                    "source" -> "还没有可以抽的句子"
                    else -> "再抽一句"
                }, color = t.inkStrongColor, fontSize = scaledSp(18), fontFamily = FontSerif, letterSpacing = 3.sp)
            if (sheetMode == "source") {
                Text("先写一句自己的话，或去材料库/句库加入一句。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans, lineHeight = scaledSp(22))
                PrimaryButton("现在写一句", Modifier.fillMaxWidth()) { startMoreWrite("encourage") }
                GhostButton("去材料库 / 句库加入", Modifier.fillMaxWidth()) { sheetOpen = false; goLibrary() }
            } else if (sheetMode == "write") {
                Text("两种都可以写，不分今天的心情。",
                    color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
                GhostButton("写一句鼓励自己的话", Modifier.fillMaxWidth()) { startMoreWrite("encourage") }
                GhostButton("写一件放在心里的事", Modifier.fillMaxWidth()) { startMoreWrite("wound") }
            } else {
                if (mood == "bad") {
                    PrimaryButton("抽一句鼓励（自己写的）", Modifier.fillMaxWidth()) { startMoreDraw("encourage") }
                    GhostButton("从收藏/材料里取一句", Modifier.fillMaxWidth()) { startMoreDraw("lib") }
                } else {
                    PrimaryButton("抽一件旧事来消化", Modifier.fillMaxWidth()) { startMoreDraw("wound") }
                    GhostButton("从句库抽一句", Modifier.fillMaxWidth()) { startMoreDraw("lib") }
                }
            }
            QuietButton("取消") { sheetOpen = false }
        }
    }
}

@Composable
private fun MoodCard(kind: String, title: String, sub1: String, sub2: String, chosen: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val t = appTokens()
    val skin by UiState.skin.collectAsState()
    val dark by UiState.dark.collectAsState()
    val isPlain = skin == "plain"
    val shape: Shape = RoundedCornerShape(if (isPlain) 10.dp else 18.dp)
    val glow = when (kind) {
        "good" -> if (dark) Color(0x66967834) else Color(0xBFFFEEB4)
        else -> if (dark) Color(0x6646606E) else Color(0x73A8BEC6)
    }
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .shadow(
                elevation = if (isPlain) 0.dp else 30.dp,
                shape = shape,
                ambientColor = argb(t.shadowColor),
                spotColor = argb(t.shadowColor)
            )
            .clip(shape)
            .background(t.cardColor)
            .drawBehind {
                if (!isPlain) {
                    drawRect(
                        Brush.radialGradient(
                            colors = listOf(glow, t.cardColor, t.cardColor),
                            center = Offset(size.width * 0.85f, -size.height * 0.10f),
                            radius = size.maxDimension * 1.4f
                        )
                    )
                }
            }
            .border(
                width = 1.dp,
                color = if (chosen) (if (isPlain) t.sealColor else t.inkColor) else t.lineColor,
                shape = shape
            )
            .clickable(onClick = onClick)
            .heightIn(min = if (isPlain) 112.dp else 104.dp)
            .padding(
                if (isPlain) {
                    androidx.compose.foundation.layout.PaddingValues(start = 10.dp, end = 8.dp, top = 8.dp, bottom = 8.dp)
                } else {
                    androidx.compose.foundation.layout.PaddingValues(start = 12.dp, end = 10.dp, top = 10.dp, bottom = 10.dp)
                }
            )
    ) {
        // 对齐鸿蒙 MoodCard：图标在左，文字列在右。
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (isPlain) 8.dp else 10.dp)
        ) {
            MoodIcons.MoodIcon(
                good = kind == "good",
                plain = isPlain,
                sizeDp = 22.dp,
                color = if (dark) t.inkColor else t.inkSoftColor
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title, color = t.inkStrongColor,
                    fontSize = scaledSp(if (isPlain) 15.5 else 16),
                    fontFamily = FontSerif,
                    letterSpacing = if (isPlain) 2.sp else 1.sp
                )
                Text(
                    sub1, color = t.inkSoftColor, fontSize = scaledSp(10),
                    lineHeight = scaledSp(16), fontFamily = FontSans,
                    letterSpacing = if (isPlain) 0.2.sp else 1.sp
                )
                Text(
                    sub2, color = t.inkSoftColor, fontSize = scaledSp(10),
                    lineHeight = scaledSp(16), fontFamily = FontSans,
                    letterSpacing = if (isPlain) 0.2.sp else 1.sp
                )
            }
        }
    }
}
