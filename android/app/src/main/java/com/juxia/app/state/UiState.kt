package com.juxia.app.state

import com.juxia.app.model.BgImageStyle
import com.juxia.app.model.RitualCtx
import kotlinx.coroutines.flow.MutableSharedFlow
import com.juxia.app.data.Store
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// 句栖 · 全局状态（翻译自 UiState.ets：dataVersion + 系统/窗口/UI 导航态 + 背景镜像）
object UiState {
    private val _dataVersion = MutableStateFlow(0L)
    val dataVersion: StateFlow<Long> = _dataVersion

    private val _systemDark = MutableStateFlow(false)
    val systemDark: StateFlow<Boolean> = _systemDark

    private val _themeMode = MutableStateFlow("system")
    val themeMode: StateFlow<String> = _themeMode

    private val _dark = MutableStateFlow(false)
    val dark: StateFlow<Boolean> = _dark

    private val _safeTop = MutableStateFlow(0)
    val safeTop: StateFlow<Int> = _safeTop

    private val _safeBottom = MutableStateFlow(0)
    val safeBottom: StateFlow<Int> = _safeBottom

    private val _openRevisit = MutableStateFlow(false)
    val openRevisit: StateFlow<Boolean> = _openRevisit

    // 外观镜像（TopBar/背景栈读取；由 syncFromStore()/applyDark 维护）
    private val _skin = MutableStateFlow("classic")
    val skin: StateFlow<String> = _skin

    private val _appName = MutableStateFlow("句栖")
    val appName: StateFlow<String> = _appName

    private val _showDays = MutableStateFlow(true)
    val showDays: StateFlow<Boolean> = _showDays

    private val _showSeal = MutableStateFlow(true)
    val showSeal: StateFlow<Boolean> = _showSeal

    private val _dayCount = MutableStateFlow(1)
    val dayCount: StateFlow<Int> = _dayCount

    // 背景应用值（Index.applyBackground 写入；bgRev 变化触发照片重载）
    private val _bgBrightness = MutableStateFlow(1.0)
    val bgBrightness: StateFlow<Double> = _bgBrightness

    private val _bgBlur = MutableStateFlow(0)
    val bgBlur: StateFlow<Int> = _bgBlur

    private val _bgScrim = MutableStateFlow(0.0)
    val bgScrim: StateFlow<Double> = _bgScrim

    private val _bgGlow = MutableStateFlow(100)
    val bgGlow: StateFlow<Int> = _bgGlow

    private val _bgGrain = MutableStateFlow(100)
    val bgGrain: StateFlow<Int> = _bgGrain

    private val _bgDither = MutableStateFlow(0)
    val bgDither: StateFlow<Int> = _bgDither

    private val _bgRev = MutableStateFlow(0)
    val bgRev: StateFlow<Int> = _bgRev

    private val _bgSavedRev = MutableStateFlow(0)
    val bgSavedRev: StateFlow<Int> = _bgSavedRev

    private val _systemFontScale = MutableStateFlow(1.0)
    val systemFontScale: StateFlow<Double> = _systemFontScale

    // 主导航（BottomBar 写；页面 goSettings 等切换用）
    private val _tab = MutableStateFlow("today")
    val tab: StateFlow<String> = _tab

    // 抽签仪式：非空时由根页面渲染 RitualOverlay
    private val _ritualCtx = MutableStateFlow<RitualCtx?>(null)
    val ritualCtx: StateFlow<RitualCtx?> = _ritualCtx

    // 仪式动作外发：绑定/归档面板请求（MinePage 消费）
    private val _bindRequest = MutableStateFlow<String?>(null)
    val bindRequest: StateFlow<String?> = _bindRequest

    private val _archiveRequest = MutableStateFlow<String?>(null)
    val archiveRequest: StateFlow<String?> = _archiveRequest

    // 背景裁剪请求：key(四路之一) + 缓存图片路径；MainActivity 宿主裁剪页
    data class CropRequest(var key: String = "", var path: String = "")
    private val _cropRequest = MutableStateFlow<CropRequest?>(null)
    val cropRequest: StateFlow<CropRequest?> = _cropRequest
    fun setCropRequest(key: String, path: String) { _cropRequest.value = CropRequest(key, path) }
    fun clearCropRequest() { _cropRequest.value = null }

    private val _bgPanelOpen = MutableStateFlow(false)
    val bgPanelOpen: StateFlow<Boolean> = _bgPanelOpen
    fun setBgPanel(open: Boolean) { _bgPanelOpen.value = open }

    // 轻提示（ToastHost 消费）
    private val _toast = MutableSharedFlow<String>(extraBufferCapacity = 16)
    val toast: MutableSharedFlow<String> = _toast

    fun bump() {
        _dataVersion.value += 1
    }

    fun setSystemDark(d: Boolean) {
        _systemDark.value = d
        if (_themeMode.value == "system") _dark.value = d
    }

    fun setThemeMode(mode: String) {
        _themeMode.value = mode
        applyDark(mode)
    }

    fun applyDark(theme: String) {
        _dark.value = theme == "dark" || (theme == "system" && _systemDark.value)
    }

    fun setSafeArea(top: Int, bottom: Int) {
        _safeTop.value = top
        _safeBottom.value = bottom
    }

    fun setOpenRevisit(v: Boolean) {
        _openRevisit.value = v
    }

    fun syncFromStore() {
        val st = Store.instance
        _skin.value = st.data.settings.skin
        _appName.value = st.data.settings.appName
        _showDays.value = st.data.settings.showDays
        _showSeal.value = st.data.settings.showSeal
        _dayCount.value = st.dayCount()
        setThemeMode(st.data.settings.theme)
    }

    fun setSystemFontScale(v: Double) {
        _systemFontScale.value = v
    }

    fun setTab(tab: String) {
        _tab.value = tab
    }

    fun startRitual(ctx: RitualCtx) {
        _ritualCtx.value = ctx
    }

    fun closeRitual() {
        _ritualCtx.value = null
    }

    fun requestBind(id: String) { _bindRequest.value = id }
    fun consumeBind() { _bindRequest.value = null }
    fun requestArchive(id: String) { _archiveRequest.value = id }
    fun consumeArchive() { _archiveRequest.value = null }

    fun showToast(msg: String) {
        _toast.tryEmit(msg)
    }

    /** 当前皮肤/主题下生效的背景配置（Index.bgStyle 的等价物） */
    fun bgStyleFor(skin: String, dark: Boolean): BgImageStyle {
        val b = Store.instance.data.settings.background
        return if (dark) {
            if (skin == "plain" && b.darkPlain.path.isNotEmpty()) b.darkPlain else b.dark
        } else {
            if (skin == "plain" && b.lightPlain.path.isNotEmpty()) b.lightPlain else b.light
        }
    }

    /** Index.applyBackground：把背景配置镜像到应用值并触发照片重载 */
    fun applyBackground() {
        val bs = bgStyleFor(_skin.value, _dark.value)
        _bgBrightness.value = bs.brightness
        _bgBlur.value = bs.blur
        _bgScrim.value = bs.scrim
        _bgGlow.value = bs.glowValue
        _bgGrain.value = bs.grainValue
        _bgDither.value = bs.ditherValue
        _bgRev.value += 1
    }

    fun bumpBgSaved() {
        _bgSavedRev.value += 1
    }
}
