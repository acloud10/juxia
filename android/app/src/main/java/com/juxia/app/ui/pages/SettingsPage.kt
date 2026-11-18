package com.juxia.app.ui.pages

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.services.AppError
import com.juxia.app.services.BackupOps
import com.juxia.app.services.BackupService
import com.juxia.app.services.ReminderService
import com.juxia.app.state.UiState
import com.juxia.app.ui.Blank
import com.juxia.app.ui.Card
import com.juxia.app.ui.GhostButton
import com.juxia.app.ui.Label
import com.juxia.app.ui.PrimaryButton
import com.juxia.app.ui.PrivacyPolicyDialog
import com.juxia.app.ui.QuietButton
import com.juxia.app.ui.appTokens
import com.juxia.app.ui.padBottom
import com.juxia.app.ui.scaledSp
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 句栖 · 设置页（翻译自 SettingsPage.ets；备份引擎在 BackupOps，本文件只做 UI）
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsPage() {
    val st = Store.instance
    val dataVersion by UiState.dataVersion.collectAsState()
    val t = appTokens()
    val ctx = LocalContext.current
    val versionName = remember {
        try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "1.0.5"
        } catch (e: Exception) {
            "1.0.5"
        }
    }
    val scope = rememberCoroutineScope()
    val s = st.data.settings
    var hourLocal by remember { mutableStateOf(s.revisitHour) }
    var minuteLocal by remember { mutableStateOf(s.revisitMinute) }
    var bootHoldLocal by remember { mutableStateOf(s.bootHoldMs.toFloat()) }
    var bootFontLocal by remember { mutableStateOf(s.bootFontScale.toFloat()) }

    var openSection by remember { mutableStateOf(setOf("about")) }
    var pw by remember { mutableStateOf("") }
    var pw2 by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var wipeStep by remember { mutableStateOf(0) }
    var selfTestMsg by remember { mutableStateOf("") }
    var askBackupOff by remember { mutableStateOf(false) }
    var restorePlain by remember { mutableStateOf(false) }
    var askSj4Pass by remember { mutableStateOf(false) }
    var pendingSj4 by remember { mutableStateOf<java.io.File?>(null) }
    var nickInput by remember { mutableStateOf(st.data.settings.nickname) }
    var bootInput by remember { mutableStateOf(st.data.settings.bootText) }
    var showPrivacy by remember { mutableStateOf(false) }
    var restoreAsk by remember { mutableStateOf<BackupOps.BackupPayload?>(null) }
    var restoreFileName by remember { mutableStateOf("") }

    fun save() {
        st.saveSettings()
        UiState.syncFromStore()
        UiState.applyBackground()
    }

    // 修正：sj4 导出 = payload zip 字节 → AES 加密 → 写入 SAF 目标
    val exportSj4Fixed = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            try {
                BackupOps.assertFreeSpace(ctx.cacheDir, 256L * 1024 * 1024)
                val (zipFile, _) = BackupOps.buildFullZip(ctx, s.fullIncludeMaterials)
                val tmpSj4 = java.io.File.createTempFile("juxia_out", ".sj4")
                try {
                    BackupService.encryptFileToFile(zipFile, tmpSj4, pw)
                    ctx.contentResolver.openOutputStream(uri)?.use { out ->
                        tmpSj4.inputStream().buffered(64 * 1024).use { it.copyTo(out) }
                    } ?: throw java.io.IOException("无法写入所选位置")
                } finally { zipFile.delete(); tmpSj4.delete() }
                st.data.meta.lastBackupAt = System.currentTimeMillis()
                st.saveKv()
                UiState.showToast(if (s.fullIncludeMaterials) "加密备份已导出（含材料）" else "加密备份已导出（不含材料）")
            } catch (e: Exception) {
                UiState.showToast("导出失败：" + (e.message ?: ""))
            } finally {
                busy = false
            }
        }
    }
    val exportZip = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            try {
                BackupOps.assertFreeSpace(ctx.cacheDir, 256L * 1024 * 1024)
                val (zipFile, _) = BackupOps.buildFullZip(ctx, s.plainIncludeMaterials)
                try {
                    ctx.contentResolver.openOutputStream(uri)?.use { out ->
                        zipFile.inputStream().buffered(64 * 1024).use { it.copyTo(out) }
                    } ?: throw java.io.IOException("无法写入所选位置")
                } finally { zipFile.delete() }
                st.data.meta.lastBackupAt = System.currentTimeMillis()
                st.saveKv()
                UiState.showToast(if (s.plainIncludeMaterials) "完整不加密备份已导出（含材料）" else "完整不加密备份已导出（不含材料）")
            } catch (e: Exception) {
                UiState.showToast("导出失败：" + (e.message ?: ""))
            } finally {
                busy = false
            }
        }
    }
    var packPreview by remember { mutableStateOf<BackupOps.MaterialsPack?>(null) }
    val importPack = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            try {
                val packSize = querySizeOf(ctx, uri)
                if (packSize > 0) BackupOps.assertFreeSpace(ctx.cacheDir, packSize * 2)
                val tmp = streamToTempFile(ctx, uri, "juxia_pack")
                try {
                    packPreview = BackupOps.parseMaterialsPack(tmp)
                } finally { tmp.delete() }
            } catch (e: Exception) {
                UiState.showToast(e.message ?: "材料包导入失败")
            } finally {
                busy = false
            }
        }
    }
    val exportPack = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            try {
                val payload = BackupOps.buildMaterialsPayload(ctx)
                ctx.contentResolver.openOutputStream(uri)?.use { out -> out.write(payload) }
                    ?: throw java.io.IOException("无法写入所选位置")
                UiState.showToast("材料包已导出")
            } catch (e: Exception) {
                UiState.showToast("导出失败：" + (e.message ?: ""))
            } finally {
                busy = false
            }
        }
    }
    val importAny = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            try {
                val inputSize = querySizeOf(ctx, uri)
                if (inputSize > 0) BackupOps.assertFreeSpace(ctx.cacheDir, inputSize * 2)
                val tmpIn = streamToTempFile(ctx, uri, "juxia_in")
                restoreFileName = uri.lastPathSegment ?: "备份文件"
                // 不能只看扩展名：改名/无扩展名的 SJ4 也要能识别。
                val isSj4 = try {
                    java.io.RandomAccessFile(tmpIn, "r").use { f ->
                        val b = ByteArray(3)
                        f.readFully(b)
                        String(b, Charsets.US_ASCII) == "SJ4"
                    }
                } catch (e: Exception) {
                    false
                }
                restorePlain = !isSj4
                if (restorePlain) {
                    try {
                        BackupOps.assertFreeSpace(ctx.cacheDir, BackupOps.zipDecompressedSize(tmpIn))
                        restoreAsk = BackupOps.parseBackup(tmpIn)
                    } finally { tmpIn.delete() }
                } else {
                    // sj4：密语在选完文件后单独问（对齐鸿蒙"输入这个包的密语"）
                    pendingSj4 = tmpIn
                    askSj4Pass = true
                }
            } catch (e: Exception) {
                val m = e.message ?: ""
                if (m.contains("NOT_ENOUGH_SPACE")) UiState.showToast("恢复需要额外的临时空间；请清理一些存储后重试。")
                else UiState.showToast(m.ifEmpty { "导入失败" })
            } finally {
                busy = false
            }
        }
    }
    fun lastBackupGroupTitle(): String {
        val at = st.data.meta.lastBackupAt
        if (at == 0L) return "上次备份：从未"
        val days = ((System.currentTimeMillis() - at) / 86400000L).toInt()
        return if (days <= 0) "上次备份：今天" else "上次备份：$days 天前"
    }

    /** 流式落临时文件（256MB 上限），不整包进内存 */
    suspend fun streamToTemp(uri: android.net.Uri, prefix: String): java.io.File =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val tmp = java.io.File.createTempFile(prefix, ".bin")
            var total = 0L
            try {
                ctx.contentResolver.openInputStream(uri)?.use { input ->
                    tmp.outputStream().buffered(64 * 1024).use { output ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            total += n
                            if (total > 256L * 1024 * 1024) throw java.io.IOException("备份文件过大（>256MB）")
                            output.write(buf, 0, n)
                        }
                    }
                } ?: throw java.io.IOException("无法读取所选文件")
            } catch (e: Exception) {
                tmp.delete()
                throw e
            }
            tmp
        }

    fun selfTest() {
        scope.launch {
            busy = true
            selfTestMsg = "自检中…"
            try {
                val (zipFile, _) = BackupOps.buildFullZip(ctx, false)
                val parsed = try {
                    BackupOps.parseBackup(zipFile)
                } finally { zipFile.delete() }
                selfTestMsg = if (parsed.data.own.size == st.data.own.size) "备份结构自检通过。"
                              else "备份结构自检失败。数据没有通过一致性检查。"
            } catch (e: Exception) {
                selfTestMsg = "备份结构自检失败，请重启应用后再试。"
            } finally {
                busy = false
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = padBottom())
    ) {
        Section("界面与常规", "ui", openSection, { openSection = it }) {
            SettingsGroup("主题") {
                Chips(listOf("system" to "跟随系统", "light" to "日间", "dark" to "夜间"), s.theme) {
                    s.theme = it; save(); ReminderService.rescheduleAll(ctx)
                }
                // 字号
            }
            SettingsGroup("文字大小") {
                Text("字号（全局，随系统一起缩放）", color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans)
                // 对齐鸿蒙 SettingsPage.ets ScaleChip：四个预设（0.9/1.0/1.1/1.25），不是连续滑杆
                Chips(
                    listOf("0.90" to "小", "1.00" to "标准", "1.10" to "大", "1.25" to "特大"),
                    if (s.fontScaleFollow) "" else "%.2f".format(s.fontScale)
                ) {
                    s.fontScale = it.toDouble(); s.fontScaleFollow = false; save()
                }
                CheckRow("跟随系统字号", s.fontScaleFollow) { s.fontScaleFollow = it; save() }
                // 皮肤
            }
            SettingsGroup("界面") {
                Chips(listOf("classic" to "经典", "plain" to "朴素"), s.skin) { s.skin = it; save() }
                Text("经典：帘后日光，折纸取信。朴素：素纸一页，只留字。两套界面功能完全相同。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                // 背景
            }
            SettingsGroup("背景") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    GhostButton("背景与氛围光") { UiState.setBgPanel(true) }
                }
                Text("可选图片背景、亮度、模糊、遮罩、氛围光与纸纹；经典/朴素 × 明暗四路独立。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                // 抽签来源
            }
            SettingsGroup("抽签来源") {
                Text("决定「抽一句」从哪里取。至少开一个；关掉的内容仍会保留在列表里。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                CheckRow("自己的话", s.drawOwn) {
                    if (!it && !s.drawLib) UiState.showToast("至少留一个来源；想关掉它，先打开「句库收藏」")
                    else { s.drawOwn = it; save() }
                }
                CheckRow("句库收藏", s.drawLib) {
                    if (!it && !s.drawOwn) UiState.showToast("至少留一个来源；想关掉它，先打开「自己的话」")
                    else { s.drawLib = it; save() }
                }
                Text("句库收藏包括从材料收入的内容；材料原文本身不直接进抽签。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                // 仪式感
            }
            SettingsGroup("抽签仪式感") {
                Chips(listOf("full" to "完整仪式", "short" to "简短", "off" to "关闭"), s.ritualMode) { s.ritualMode = it; save() }
                Text("抽签前的折纸仪式帮助开始，不必每次完整执行——觉得成了负担就调短或关掉。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                // 回访
            }
            SettingsGroup("回访") {
                Chips(listOf("7" to "7 天", "30" to "30 天", "90" to "90 天", "180" to "180 天", "365" to "365 天"),
                    if (listOf(7, 30, 90, 180, 365).contains(s.revisitDays)) "${s.revisitDays}" else "") {
                    s.revisitDays = it.toInt(); save(); ReminderService.rescheduleAll(ctx)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                    var rvCustom by remember { mutableStateOf("") }
                    com.juxia.app.ui.PaperInput(value = rvCustom, onChange = { rvCustom = it.filter { c -> c.isDigit() }.take(4) },
                        placeholder = "自定义天数", multiLine = false)
                    GhostButton("确定这个时间") {
                        val d = rvCustom.toIntOrNull()
                        if (d == null || d < 1 || d > 3650) UiState.showToast("天数要在 1 到 3650 之间")
                        else { s.revisitDays = d; save(); ReminderService.rescheduleAll(ctx); UiState.showToast("回访约定改为 $d 天") }
                    }
                }
                Text("「已解决 / 已放下」的事，可选在若干天后轻轻问一次。如果回访时发现还没准备好，可以回到台前。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                // 回访时间
            }
            SettingsGroup("回访时间") {
                Text("每天 ${hourLocal} 时 ${"%02d".format(minuteLocal)} 分　(与当前一致)", color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Slider(value = hourLocal.toFloat(), onValueChange = {
                    hourLocal = it.toInt(); s.revisitHour = hourLocal; save()
                    st.shiftRevisitTimes(s.revisitHour, s.revisitMinute)
                    ReminderService.rescheduleAll(ctx)
                }, valueRange = 6f..23f, colors = sealSliderColors())
                Slider(value = minuteLocal.toFloat(), onValueChange = {
                    minuteLocal = (it.toInt() / 5) * 5; s.revisitMinute = minuteLocal; save()
                    st.shiftRevisitTimes(s.revisitHour, s.revisitMinute)
                    ReminderService.rescheduleAll(ctx)
                }, valueRange = 0f..55f, colors = sealSliderColors())
            }
        }

        Section("名称与启动", "name", openSection, { openSection = it }) {
            SettingsGroup("应用名") {
                Text("默认「句栖」。改名后，应用内的标题、印章、页脚与文案一起换，最多 6 个字。桌面图标名由系统在安装时确定，不会随应用内改名同步。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                Chips(listOf("句栖" to "句栖", "一息" to "一息"), if (listOf("句栖", "一息").contains(s.appName)) s.appName else "") {
                    s.appName = it; save()
                }
                com.juxia.app.ui.PaperInput(value = if (listOf("句栖", "一息").contains(s.appName)) "" else s.appName,
                    onChange = { s.appName = it.take(6); save() }, placeholder = "自定义（最多 6 字）", multiLine = false)
                QuietButton("保存名字") { s.appName = s.appName.trim().ifEmpty { "句栖" }; save(); UiState.showToast("名字已保存") }
                    QuietButton("恢复默认") { s.appName = "句栖"; save(); UiState.showToast("名字已恢复默认") }
                CheckRow("显示左上角印章", s.showSeal) { s.showSeal = it; save() }
                CheckRow("显示「相伴第 N 天」", s.showDays) { s.showDays = it; save() }
                // 称呼
            }
            SettingsGroup("称呼与问候") {
                Text("只影响应用内。今日页会显示「你好，XXX」；可以随时关掉称呼。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                com.juxia.app.ui.PaperInput(value = nickInput, onChange = { nickInput = it.take(12) },
                    placeholder = "写一个你喜欢的称呼", multiLine = false)
                Row {
                    QuietButton("保存称呼") {
                        if (nickInput.isBlank()) UiState.showToast("先在上面写一个称呼")
                        else { s.nickname = nickInput.trim(); save(); UiState.showToast("称呼已保存") }
                    }
                    if (s.nickname.isNotEmpty()) QuietButton("清除称呼") {
                        nickInput = ""; s.nickname = ""; save(); UiState.showToast("已清除称呼")
                    }
                }
                CheckRow(if (s.showGreeting) "提醒已开启" else "提醒已关闭", s.showGreeting) {
                    s.showGreeting = it; save()
                }
                CheckRow("显示省身区", s.showReflect) { s.showReflect = it; save() }
                Text("在「我的」里显示省身区。关闭后数据保留，只是不再显示入口。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                // 启动
            }
            SettingsGroup("启动") {
                Text("默认启动很快淡出。开启后停留更久，显示你写的一句话；不写就不停留。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                CheckRow("长时启动", s.bootLong) {
                    s.bootLong = it; save()
                    if (it && s.bootText.isBlank()) UiState.showToast("已开启，但文案为空，启动不会停留")
                }
            }
            SettingsGroup("停留与字号") {
                Text("停留时长　${(bootHoldLocal / 1000.0).format1()} 秒", color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Slider(value = bootHoldLocal, onValueChange = {
                    bootHoldLocal = (it / 10).toInt() * 10f
                    s.bootHoldMs = bootHoldLocal.toLong(); save()
                }, valueRange = 300f..5000f, colors = sealSliderColors())
                Text("启动字 ${"%.2f".format(bootFontLocal)}", color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Slider(value = bootFontLocal, onValueChange = {
                    bootFontLocal = ((it * 20).toInt() / 20f)
                    s.bootFontScale = bootFontLocal.toDouble(); save()
                }, valueRange = 0.8f..2.5f, colors = sealSliderColors())
                com.juxia.app.ui.PaperInput(value = bootInput, onChange = { bootInput = it.take(24) },
                    placeholder = "写一句给自己的话（最多 24 字）", multiLine = false)
                QuietButton("保存文案") {
                    s.bootText = bootInput
                    save()
                    UiState.showToast(if (bootInput.isNotEmpty()) "启动文案已保存" else "启动文案已清空")
                }
            }
        }

        Section("数据与备份", "data", openSection, { openSection = it }) {
            SettingsGroup(null) {
                Text("数据、句子关系、省身与备注、材料一起打包，再用备份密码（密语）加密成 .sj4。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
            }
            SettingsGroup("完整加密备份") {
                CheckRow(if (s.fullIncludeMaterials) "✓ 同时备份材料包" else "同时备份材料包", s.fullIncludeMaterials) {
                    s.fullIncludeMaterials = it; save()
                }
                com.juxia.app.ui.PaperInput(value = pw, onChange = { pw = it }, placeholder = "密语（导出与导入共用）", multiLine = false, password = true)
                Spacer(Modifier.height(6.dp))
                com.juxia.app.ui.PaperInput(value = pw2, onChange = { pw2 = it }, placeholder = "再输一遍", multiLine = false, password = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton(if (busy) "处理中…" else "导出 .sj4") {
                        when {
                            pw.isEmpty() || pw2.isEmpty() -> UiState.showToast("先输入密语")
                            pw != pw2 -> UiState.showToast("两次密语要一致，且不能为空")
                            BackupOps.pwTooWeak(pw) -> UiState.showToast("这句密语太常见，换一句")
                            else -> exportSj4Fixed.launch("句栖备份.sj4")
                        }
                    }
                    GhostButton("导出 .zip（不加密）") { exportZip.launch("句栖备份.zip") }
                }
                Spacer(Modifier.height(8.dp))
                GhostButton("导入备份（.sj4 / .zip）") {
                    if (pw.isEmpty()) UiState.showToast("先填密语（zip 导入可随便填）")
                    else importAny.launch(arrayOf("application/octet-stream", "application/zip", "text/plain", "application/x-zip-compressed"))
                }
                Text("数据、句子关系、省身与备注、材料一起打包成 .zip，不加密；拿到文件的人可以直接查看。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
            }
            SettingsGroup("完整不加密备份") {
                CheckRow(if (s.plainIncludeMaterials) "✓ 包含" else "不包含", s.plainIncludeMaterials) {
                    s.plainIncludeMaterials = it; save()
                }
                Text("不加密备份不需要密语，请自行保管。", color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
            }
            SettingsGroup("材料包 · 单独搬材料") {
                Text("适合只迁移材料，不动现有数据。拿到文件的人可以直接查看材料原文。",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22))
                Text("只包含材料原文，不含句子、省身、设置和关系；不加密。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    GhostButton("导出材料包") { exportPack.launch("句栖材料包.zip") }
                    GhostButton("导入材料包") { importPack.launch(arrayOf("application/zip", "application/x-zip-compressed")) }
                }
                Text(lastBackupGroupTitle(), color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
                    modifier = Modifier.padding(top = 6.dp))
            }
            SettingsGroup("备份提醒") {
                CheckRow("每 14 天提醒一次", !s.backupRemindOff) {
                    if (it) { s.backupRemindOff = false; save(); UiState.showToast("备份提醒已重新开启") }
                    else askBackupOff = true
                }
            }
            SettingsGroup("清空") {
                QuietButton("清空全部数据", ) {
                    wipeStep = 1
                }
            }
        }

        Section("关于", "about", openSection, { openSection = it }) {
            SettingsGroup(null) {
                Text(
                    "句栖 $versionName",
                    color = t.inkStrongColor, fontSize = scaledSp(15), fontFamily = FontSerif,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .combinedClickable(
                            onClick = {},
                            onLongClick = { selfTest() }
                        )
                        .padding(vertical = 6.dp)
                )
                if (selfTestMsg.isNotEmpty()) Text(selfTestMsg, color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans)
                Text("本地优先，不联网，无账号。长按版本号可自检备份链路；数据存储方式：" + if (st.usesDb()) "本地数据库" else "本地缓存",
                    color = t.inkSoftColor, fontSize = scaledSp(12.5), fontFamily = FontSans, lineHeight = scaledSp(22),
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .combinedClickable(onClick = {}, onLongClick = {
                            ReminderService.rescheduleAll(ctx, requestPermission = false)
                            val exactOk = android.os.Build.VERSION.SDK_INT < 31 ||
                                (ctx.getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager)
                                    .canScheduleExactAlarms()
                            UiState.showToast("提醒已重排：" +
                                (if (ReminderService.isNotificationEnabled(ctx)) "通知已开启" else "通知未开启") +
                                (if (exactOk) "" else "；精确提醒被限，可能略有延迟"))
                        })
                        .padding(vertical = 4.dp))
                QuietButton("新手指引 ›") {
                    st.data.meta.seen = false
                    st.saveKv()
                    UiState.setTab("today")
                    // JuxiaRoot 的 WelcomeGuide 分支依赖 dataVersion 重组。
                    UiState.bump()
                }
                Text("句栖是记录与回看的工具，不是心理治疗、诊断或危机干预服务，也不能替代专业帮助。\n如果你持续感到痛苦、影响到日常生活，或出现伤害自己的念头，请联系专业心理/精神科医生，或拨打当地心理援助热线（中国大陆 12356）。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans, lineHeight = scaledSp(19))
                Text("卸载应用会删除本机数据；导出的备份文件请自己保管。",
                    color = t.inkSoftColor, fontSize = scaledSp(11), fontFamily = FontSans,
                    modifier = Modifier.padding(top = 8.dp))
                QuietButton("隐私政策") { showPrivacy = true }
                QuietButton("开源与第三方组件") {
                    try {
                        ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/acloud10/juxia")))
                    } catch (_: Exception) {}
                }
            }
        }

        Blank()
    }

    // 恢复确认（摘要 + 确认/取消）
    restoreAsk?.let { payload ->
        AlertDialog(
            onDismissRequest = { restoreAsk?.cleanup(); restoreAsk = null },
            title = { Text("恢复完整备份？", fontFamily = FontSerif) },
            text = {
                Text("恢复会覆盖当前全部数据：句子、旧事、回忆、备注、省身、句库、设置和材料。若备份不含材料，材料库会为空。建议先导出当前备份；此操作不可撤销。",
                    fontFamily = FontSans)
            },
            confirmButton = {
                TextButton(onClick = {
                    val p = payload
                    restoreAsk = null
                    scope.launch {
                        busy = true
                        val err = BackupOps.doRestore(ctx, p)
                        if (err == null) {
                            BackupOps.pruneMissingMaterials(ctx)
                            UiState.syncFromStore()
                            UiState.applyBackground()
                            nickInput = st.data.settings.nickname
                            bootInput = st.data.settings.bootText
                            UiState.showToast("完整备份已恢复，材料与索引一并回来")
                        } else {
                            when {
                                err.startsWith("恢复完成") -> UiState.showToast("数据已经恢复；重启应用后会补完材料索引和清理。")
                                err.contains("JOURNAL_WRITE_FAILED") -> UiState.showToast("数据已恢复，但恢复日志写入失败。")
                                err.contains("MK_") || err.contains("COPY_FILE") || err.contains("NOT_ENOUGH_SPACE") ->
                                    UiState.showToast("恢复需要额外的临时空间；请清理一些存储后重试。")
                                restorePlain -> {
                                    AppError.report("完整不加密备份恢复失败。", "确认文件完整、格式正确后重试；不要删除原文件。")
                                    UiState.showToast("完整备份恢复失败。")
                                }
                                else -> UiState.showToast("完整备份恢复失败。")
                            }
                        }
                        busy = false
                    }
                }) { Text("继续恢复", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { restoreAsk?.cleanup(); restoreAsk = null }) { Text("取消") }
            }
        )
    }

    // 清空三级确认
    if (wipeStep > 0) {
        AlertDialog(
            onDismissRequest = { wipeStep = 0 },
            title = { Text(when (wipeStep) { 1 -> "清空全部数据？"; 2 -> "真的清空？"; else -> "确认清空" }, fontFamily = FontSerif) },
            text = {
                Text(when (wipeStep) {
                    1 -> "此操作不可撤销，建议先导出密语备份。"
                    2 -> "清空后所有句子、省身、备注、材料和设置都会消失，无法恢复；自定义背景会保留。"
                    else -> "所有句子、备注、回忆、材料与设置都会消失，无法找回；自定义背景会保留。"
                }, fontFamily = FontSans)
            },
            confirmButton = {
                TextButton(onClick = {
                    if (wipeStep >= 3) {
                        scope.launch {
                            busy = true
                            try { st.wipeAll(ctx) }
                            catch (e: Exception) { UiState.showToast("清空失败。") }
                            finally { busy = false }
                            UiState.syncFromStore()
                            UiState.applyBackground()
                            nickInput = st.data.settings.nickname
                            bootInput = st.data.settings.bootText
                            UiState.showToast("已清空，一切重新开始")
                        }
                        wipeStep = 0
                    } else wipeStep++
                }) { Text(if (wipeStep >= 3) "清空" else "继续", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { wipeStep = 0 }) { Text("取消") }
            }
        )
    }

    if (askBackupOff) {
        AlertDialog(
            onDismissRequest = { askBackupOff = false },
            title = { Text("彻底关闭备份提醒？", fontFamily = FontSerif) },
            text = { Text("关闭后不再提醒；数据只在这台设备上（自己导出的数据除外，取决于自己存放的位置），误删、卸载或换机都可能无法恢复。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    s.backupRemindOff = true; save(); askBackupOff = false
                    UiState.showToast("已彻底关闭备份提醒")
                }) { Text("仍然关闭", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { askBackupOff = false }) { Text("取消") }
            }
        )
    }

    // sj4 导入密语询问
    if (askSj4Pass) {
        var passLocal by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { pendingSj4?.delete(); pendingSj4 = null; askSj4Pass = false },
            title = { Text("输入这个包的密语", fontFamily = FontSerif) },
            text = {
                Column {
                    Text("请选择由句栖导出的 .sj4 文件；不要把 .zip 改名成 .sj4。",
                        fontFamily = FontSans, fontSize = scaledSp(12))
                    Spacer(Modifier.height(8.dp))
                    com.juxia.app.ui.PaperInput(value = passLocal, onChange = { passLocal = it },
                        placeholder = "密语", multiLine = false, password = true)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val f = pendingSj4 ?: return@TextButton
                    val z = java.io.File.createTempFile("juxia_zip", ".zip")
                    scope.launch {
                        busy = true
                        try {
                            BackupService.decryptToFile(f, z, passLocal)
                            BackupOps.assertFreeSpace(ctx.cacheDir, BackupOps.zipDecompressedSize(z))
                            restoreAsk = BackupOps.parseBackup(z)
                            askSj4Pass = false
                            pendingSj4 = null
                        } catch (e: com.juxia.app.services.BackupService.BackupException) {
                            UiState.showToast("密语不对，或备份文件已损坏。")
                        } catch (e: Exception) {
                            UiState.showToast("读取备份文件失败。")
                        } finally {
                            z.delete(); f.delete()
                            busy = false
                        }
                    }
                }) { Text("解密", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { pendingSj4?.delete(); pendingSj4 = null; askSj4Pass = false }) { Text("取消") }
            }
        )
    }

    // 材料包导入预览确认
    packPreview?.let { pack ->
        AlertDialog(
            onDismissRequest = { packPreview?.cleanup(); packPreview = null },
            title = { Text("导入这份材料包？", fontFamily = FontSerif) },
            text = { Text("恢复将覆盖当前全部数据；若包内不含材料，材料库会为空。", fontFamily = FontSans) },
            confirmButton = {
                TextButton(onClick = {
                    val p = pack
                    packPreview = null
                    scope.launch {
                        busy = true
                        try {
                            val (added, skipped, failed) = BackupOps.importMaterialsPack(ctx, p)
                            p.cleanup()
                            UiState.showToast(
                            "已导入 $added 份材料" +
                            (if (skipped > 0) "，跳过 $skipped 份重复" else "") +
                            (if (failed > 0) "，$failed 份失败已回滚" else ""))
                        } finally {
                            busy = false
                        }
                    }
                }) { Text("导入", color = t.sealColor) }
            },
            dismissButton = {
                TextButton(onClick = { pack.cleanup(); packPreview = null }) { Text("取消") }
            }
        )
    }

    if (showPrivacy) {
        // 对齐鸿蒙：整篇隐私政策（12 节），不是一段摘要
        PrivacyPolicyDialog { showPrivacy = false }
    }
}

@Composable
private fun sealSliderColors() = SliderDefaults.colors(
    thumbColor = appTokens().sealColor,
    activeTrackColor = appTokens().sealColor,
    inactiveTrackColor = appTokens().lineColor,
    activeTickColor = appTokens().sealColor,
    inactiveTickColor = appTokens().lineColor
)

@Composable
private fun SettingsGroup(title: String?, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        if (title != null) GroupTitle(title)
        Card(padded = 0.dp) {
            Column(Modifier.fillMaxWidth().padding(20.dp)) {
                content()
            }
        }
    }
}

@Composable
private fun GroupTitle(text: String) {
    val t = appTokens()
    Row(
        Modifier.fillMaxWidth().padding(top = 30.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text, color = t.sealColor, fontSize = scaledSp(12.5), letterSpacing = 4.sp, fontFamily = FontSerif)
        Spacer(Modifier.width(10.dp))
        androidx.compose.material3.HorizontalDivider(
            modifier = Modifier.weight(1f),
            color = t.lineColor,
            thickness = 1.dp
        )
    }
}

@Composable
private fun Section(
    title: String, key: String,
    openSet: Set<String>, onToggle: (Set<String>) -> Unit,
    content: @Composable () -> Unit
) {
    val t = appTokens()
    val open = key in openSet
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clickable {
                // 对齐鸿蒙：一次只展开一个分组。
                onToggle(if (open) emptySet() else setOf(key))
            }.padding(top = 18.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, color = t.inkStrongColor, fontSize = scaledSp(16), fontFamily = FontSerif, letterSpacing = 2.sp)
            Spacer(Modifier.weight(1f))
            Text(if (open) "收起" else "展开", color = t.inkSoftColor, fontSize = scaledSp(11.5), fontFamily = FontSans)
        }
        if (open) {
            Column(Modifier.fillMaxWidth()) {
                content()
            }
        }
    }
}

@Composable
private fun CheckRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val t = appTokens()
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        androidx.compose.foundation.layout.Box(
            Modifier
                .size(20.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(if (checked) t.sealColor else Color.Transparent)
                .border(1.dp, if (checked) t.sealColor else t.inkSoftColor, RoundedCornerShape(4.dp)),
            contentAlignment = Alignment.Center
        ) {
            if (checked) Text("✓", color = t.bgColor, fontSize = scaledSp(13), fontFamily = FontSans)
        }
        Spacer(Modifier.width(10.dp))
        Text(label, color = t.inkSoftColor, fontSize = scaledSp(12), fontFamily = FontSans)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Chips(options: List<Pair<String, String>>, selected: String, onPick: (String) -> Unit) {
    val t = appTokens()
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(vertical = 4.dp)
    ) {
        options.forEach { (k, n) ->
            val on = selected == k
            Text(
                text = n,
                color = if (on) t.sealInkColor else t.inkSoftColor,
                fontFamily = FontSans, fontSize = scaledSp(11.5), letterSpacing = 1.5.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (on) t.sealColor else t.cardColor)
                    .border(
                        width = 1.dp,
                        color = if (on) t.sealColor else t.lineColor,
                        shape = RoundedCornerShape(999.dp)
                    )
                    .clickable { onPick(k) }
                    .padding(horizontal = 18.dp, vertical = 9.dp)
            )
        }
    }
}

private fun Double.format1(): String = "%.1f".format(this)

/** SAF 文件体积查询（文件级，SettingsPage 专用） */
private fun querySizeOf(ctx: android.content.Context, uri: android.net.Uri): Long {
    var size = -1L
    try {
        ctx.contentResolver.query(uri, arrayOf("android.provider.OpenableColumns.SIZE"), null, null, null)?.use { c ->
            if (c.moveToFirst()) size = c.getLong(0)
        }
    } catch (e: Exception) { }
    return size
}

/** 流式落临时文件（256MB 上限）——文件级，SettingsPage 专用 */
private suspend fun streamToTempFile(ctx: android.content.Context, uri: android.net.Uri, prefix: String): java.io.File =
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val tmp = java.io.File.createTempFile(prefix, ".bin")
        var total = 0L
        try {
            ctx.contentResolver.openInputStream(uri)?.use { input ->
                tmp.outputStream().buffered(64 * 1024).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > 256L * 1024 * 1024) throw java.io.IOException("备份文件过大（>256MB）")
                        output.write(buf, 0, n)
                    }
                }
            } ?: throw java.io.IOException("无法读取所选文件")
        } catch (e: Exception) {
            tmp.delete()
            throw e
        }
        tmp
    }
