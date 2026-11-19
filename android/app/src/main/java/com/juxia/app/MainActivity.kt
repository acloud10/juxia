package com.juxia.app

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.juxia.app.data.Store
import com.juxia.app.state.UiState
import com.juxia.app.ui.BackgroundCropPage
import com.juxia.app.ui.BackgroundSettingsPanel
import com.juxia.app.ui.BackgroundStack
import com.juxia.app.ui.BottomBar
import com.juxia.app.ui.RitualOverlay
import com.juxia.app.ui.ToastHost
import com.juxia.app.ui.WelcomeGuide
import com.juxia.app.ui.TopBar
import com.juxia.app.ui.appTokens
import com.juxia.app.ui.pages.ArchivePage
import com.juxia.app.ui.pages.LibraryPage
import com.juxia.app.ui.pages.MinePage
import com.juxia.app.ui.pages.SettingsPage
import com.juxia.app.ui.pages.TodayPage
import com.juxia.app.ui.scaledSp
import com.juxia.app.ui.theme.FontSans
import com.juxia.app.ui.theme.FontSerif
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// 句栖 · 主 Activity（装配层：boot 屏 → 隐私门 → 新手指引 → 五页骨架；对应 Index.ets 的编排）
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        UiState.setSystemDark(resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
        handleIntent(intent)
        setContent {
            JuxiaRoot()
        }
        // 返回分发器（Android 13+ 预测返回兼容）
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                when {
                    UiState.ritualCtx.value != null -> UiState.closeRitual()
                    UiState.bgPanelOpen.value -> UiState.setBgPanel(false)
                    UiState.cropRequest.value != null -> UiState.clearCropRequest()
                    else -> { isEnabled = false; onBackPressedDispatcher.onBackPressed(); isEnabled = true }
                }
            }
        })
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("open_revisit", false) == true) {
            UiState.setOpenRevisit(true)
        }
    }
}

@Composable
private fun JuxiaRoot() {
    val st = Store.instance
    val configuration = LocalConfiguration.current
    LaunchedEffect(configuration.uiMode) {
        UiState.setSystemDark(configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
    }
    // 安全区（px → dp）
    val density = LocalDensity.current
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.SideEffect {
        val insets = androidx.core.view.ViewCompat.getRootWindowInsets(view)
        if (insets != null) {
            val top = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.statusBars()).top
            val bottom = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.navigationBars()).bottom
            UiState.setSafeArea(
                with(density) { top.toDp().value.toInt() },
                with(density) { bottom.toDp().value.toInt() }
            )
        }
    }

    UiState.syncFromStore()
    val readyNow by Store.instance.ready.collectAsState()
    val initErr by Store.instance.initError.collectAsState()
    // 引导/隐私门写的是普通 data 字段；必须订阅全局 dataVersion 才会重算 when。
    val dataRev by UiState.dataVersion.collectAsState()
    if (dataRev < 0L) return

    // 通知权限：就绪+隐私同意后申请一次（二轮#1：privacyOk 必须是 effect 的键，
    // 否则首启时 readyNow=true 但 privacyAccepted=false 跳过，点同意后 effect 不重跑）
    val act = LocalActivity.current
    val privacyOk = st.data.settings.privacyAccepted
    LaunchedEffect(readyNow, privacyOk) {
        if (readyNow && privacyOk &&
            android.os.Build.VERSION.SDK_INT >= 33 &&
            !com.juxia.app.services.ReminderService.isNotificationEnabled(act ?: return@LaunchedEffect) &&
            !st.notifAsked()
        ) {
            act.requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 42)
            st.markNotifAsked()
        }
    }

    // 长启动门控（二轮#5：判定必须在 ready 之后做——首次组合时 data 可能还是默认值，
    // 用 mainReady 反转：ready 后按需等待，而不是用初始值的反向）
    var mainReady by remember { mutableStateOf(false) }
    LaunchedEffect(readyNow) {
        if (!readyNow) return@LaunchedEffect
        if (st.data.settings.bootLong) delay(st.data.settings.bootHoldMs)
        mainReady = true
    }

    when {
        !readyNow || !mainReady -> BootScreen(initErr)
        !st.data.settings.privacyAccepted -> PrivacyGate()
        !st.data.meta.seen -> WelcomeGuide { st.data.meta.seen = true; st.saveKv(); UiState.bump() }
        else -> MainScaffold()
    }
}


// ---------- 启动屏（bootText/bootHoldMs/bootFontScale；颜色跟随系统深浅） ----------

@Composable
private fun BootScreen(initErr: String = "") {
    val systemDark by UiState.systemDark.collectAsState()
    val t = com.juxia.app.ui.theme.getTokens("classic", systemDark)
    val st = Store.instance
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    Box(
        Modifier
            .fillMaxSize()
            .background(t.bgColor),
        contentAlignment = Alignment.Center
    ) {
        Text(
            st.data.settings.bootText.ifEmpty { st.data.settings.appName },
            color = t.inkStrongColor,
            fontFamily = FontSerif,
            fontSize = scaledSp(28.0 * st.data.settings.bootFontScale),
            letterSpacing = 2.sp
        )
        if (initErr.isNotBlank()) {
            Text(
                "启动失败。数据没有删除。",
                color = t.inkSoftColor,
                fontFamily = FontSans,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 18.dp)
            )
            Text(
                "可重试；若仍失败，先不要清空数据。",
                color = t.inkSoftColor,
                fontFamily = FontSans,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 4.dp)
            )
            androidx.compose.material3.TextButton(onClick = {
                scope.launch { runCatching { st.init(ctx) } }
            }) { Text("重试", color = t.sealColor) }
        }
        ToastHost()
    }
}

// ---------- 隐私门（逐字翻译自 Index.ets PrivacyGate） ----------
@Composable
private fun PrivacyGate() {
    val t = appTokens()
    val ctx = LocalContext.current
    val st = Store.instance
    var showPolicy by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(t.bgColor).padding(horizontal = 24.dp)) {
        Column(
            Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(t.cardColor)
                .padding(24.dp)
        ) {
            Text("先说清楚隐私", color = t.inkStrongColor, fontFamily = FontSerif, fontSize = 20.sp,
                letterSpacing = 2.sp)
            Spacer(Modifier.height(14.dp))
            Text("句栖把句子、备注、旧事和设置加密保存在本机，不上传；没有账号、广告或统计。",
                color = t.inkColor, fontFamily = FontSans, fontSize = 13.sp, lineHeight = 23.sp)
            Text("句栖不联网、不上传。备份由你主动导出，通知是本地提醒。",
                color = t.inkColor, fontFamily = FontSans, fontSize = 13.sp, lineHeight = 23.sp,
                modifier = Modifier.padding(top = 10.dp))
            Text("句栖不是心理治疗、诊断或危机干预服务，也不能替代专业帮助。\n如果你持续感到痛苦、影响到日常生活，或出现伤害自己的念头，请联系专业心理/精神科医生，或拨打当地心理援助热线（中国大陆 12356）。",
                color = t.inkSoftColor, fontFamily = FontSans, fontSize = 12.sp, lineHeight = 21.sp,
                modifier = Modifier.padding(top = 10.dp))
            Text("查看完整隐私政策", color = t.sealColor, fontFamily = FontSans, fontSize = 12.sp,
                modifier = Modifier
                    .padding(top = 12.dp)
                    .clickable { showPolicy = true })
            Spacer(Modifier.height(18.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "不同意并退出",
                    color = t.inkSoftColor, fontFamily = FontSans, fontSize = 13.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(t.radiusBtn.dp))
                        .clickable { (ctx as? ComponentActivity)?.finish() }
                        .padding(horizontal = 18.dp, vertical = 11.dp)
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "同意并继续",
                    color = t.bgColor, fontFamily = FontSans, fontSize = 13.5.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(t.radiusBtn.dp))
                        .background(t.inkColor)
                        .clickable {
                            st.data.settings.privacyAccepted = true
                            st.saveSettings()
                            UiState.bump()
                        }
                        .padding(horizontal = 22.dp, vertical = 11.dp)
                )
            }
        }
    }
    if (showPolicy) {
        // 对齐鸿蒙 PrivacyPage：整篇 12 节政策
        com.juxia.app.ui.PrivacyPolicyDialog { showPolicy = false }
    }
}

// ---------- 主骨架：背景栈 + 顶栏 + 页面 + 底部导航 + 仪式 + 面板 + Toast ----------

@Composable
private fun MainScaffold() {
    val st = Store.instance
    UiState.dataVersion.collectAsState()
    val tab by UiState.tab.collectAsState()
    val ritual by UiState.ritualCtx.collectAsState()
    val bgPanel by UiState.bgPanelOpen.collectAsState()
    val t = appTokens()
    val ctx = LocalContext.current

    // 对齐 Index.onPageHide：退后台时冲刷写队列
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP) {
                kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                    try { Store.instance.flush() } catch (e: Exception) {}
                }
            }
            // 跨午夜/后台过夜失鲜修复：回前台时滚日期、补记打开、刷新外观、强制重建
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
                    try {
                        Store.instance.rollDay()          // recordOpen → 新一天进 openDays
                        UiState.syncFromStore()           // dayCount/日期行刷新
                        UiState.bump()                    // 全页重算（回访到期、倒计时）
                    } catch (e: Exception) {}
                }
            }
        }.also { obs ->
            lifecycleOwner.lifecycle.addObserver(obs)
        }
    }
    val readyNow2 by Store.instance.ready.collectAsState()
    LaunchedEffect(readyNow2) {
        if (readyNow2) {
            UiState.syncFromStore()   // 冷启动：DB 设置刷入外观镜像（JuxiaRoot 那次读的还是默认值）
            UiState.applyBackground()
            st.postponeMissedRevisits(System.currentTimeMillis())
            com.juxia.app.services.ReminderService.rescheduleAll(ctx) // 幂等：running/queued 合并
        }
    }
    // 对齐鸿蒙 Index.scheduleDayTick：跨午夜自动滚日期。
    // 鸿蒙有这条，安卓原先只在 ON_RESUME 滚，用户一直开着不动会停在昨天。
    LaunchedEffect(readyNow2) {
        if (!readyNow2) return@LaunchedEffect
        while (true) {
            val now = System.currentTimeMillis()
            val next = java.util.Calendar.getInstance().apply {
                timeInMillis = now
                set(java.util.Calendar.HOUR_OF_DAY, 24)   // 24 点自动前进到次日 00:00
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 1)
                set(java.util.Calendar.MILLISECOND, 0)
            }
            kotlinx.coroutines.delay((next.timeInMillis - now).coerceAtLeast(1000L))
            try {
                Store.instance.rollDay()
                UiState.syncFromStore()
                UiState.bump()
            } catch (_: Exception) {}
        }
    }
    LaunchedEffect(tab) {
        UiState.applyBackground()
    }
    // 通知点按回访 → 今日页
    val openRevisit by UiState.openRevisit.collectAsState()
    LaunchedEffect(openRevisit) {
        if (openRevisit) {
            UiState.setOpenRevisit(false)
            UiState.setTab("today")
        }
    }

    // 对齐鸿蒙 Index.applyFontScale：应用字号是全局字号缩放，不只是个别 scaledSp。
    val baseDensity = LocalDensity.current
    val targetFontScale = if (st.data.settings.fontScaleFollow) {
        baseDensity.fontScale
    } else {
        st.data.settings.fontScale.toFloat()
    }
    CompositionLocalProvider(
        LocalDensity provides Density(baseDensity.density, targetFontScale)
    ) {
    BackgroundStack {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            TopBar()
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (tab) {
                    "today" -> TodayPage()
                    "mine" -> MinePage()
                    "library" -> LibraryPage()
                    "archive" -> ArchivePage()
                    else -> SettingsPage()
                }
            }
            BottomBar()
        }

        ritual?.let { r ->
            RitualOverlay(
                ctx = r,
                onClose = { UiState.closeRitual() },
                onBind = { id ->
                    UiState.closeRitual()
                    UiState.setTab("mine")
                    UiState.requestBind(id)
                },
                onArchive = { id ->
                    UiState.closeRitual()
                    UiState.setTab("mine")
                    UiState.requestArchive(id)
                }
            )
        }

        if (bgPanel) {
            BackgroundSettingsPanel(onClose = { UiState.setBgPanel(false) })
        }

        val cropReq by UiState.cropRequest.collectAsState()
        cropReq?.let { req ->
            BackgroundCropPage(
                srcPath = req.path,
                cropKey = req.key,
                onClose = { UiState.clearCropRequest() }
            )
        }

            ToastHost()
        }
    }
}
