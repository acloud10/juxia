// 句栖 · 根页面
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { Store } from '../data/Store';
import { ReminderService } from '../services/ReminderService';
import { RitualCtx, OwnEntry, LibEntry } from '../model/Types';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { TopBar, TabIcon } from '../components/Chrome';
import { RitualOverlay } from '../components/RitualOverlay';
import { WelcomeGuide } from '../components/WelcomeGuide';
import { BgImageStyle } from '../model/BackgroundStyle';
import { TodayPage } from './TodayPage';
import { MinePage } from './MinePage';
import { LibraryPage } from './LibraryPage';
import { ArchivePage } from './ArchivePage';
import { SettingsPage } from './SettingsPage';
import { UiState } from '../state/UiState';
import { RefreshBus } from '../state/RefreshBus';
import { AppError } from '../services/AppError';
import { RestoreRecovery } from '../services/RestoreRecovery';
import { MaterialRepair } from '../services/MaterialRepair';
import { BackgroundService } from '../services/BackgroundService';

@Entry
@ComponentV2
struct Index {
  @Local ui: UiState = UiState.get();
  @Local tab: number = 0;
  @Local pageOpacity: number = 1;
  @Local ready: boolean = false;
  @Local privacyOpen: boolean = false;
  @Local guideOpen: boolean = false;
  @Local guideReplay: boolean = false;
  @Local demoActive: boolean = false;
  @Local guideStartStage: string = '';
  @Local demoBranch: string = 'sun';
  @Local demoStep: number = 0;
  @Local demoSavedReplay: boolean = false;
  private demoTimer: number = -1;
  @Local demoFinished: boolean = false;
  @Local demoSunSeen: boolean = false;
  @Local demoRainSeen: boolean = false;
  @Local bootOpacity: number = 1;
  @Local bootDone: boolean = false;
  @Local bootTextOpacity: number = 0;
  @Local bootLong: boolean = false;
  @Local bootText: string = '';
  @Local bootHoldMs: number = 1200;
  @Local bootFontScale: number = 1.25;
  @Local ritualVisible: boolean = false;
  @Local ritualCtx: RitualCtx = new RitualCtx();
  @Local bgRev: number = 0;
  @Local bgReady: boolean = false;
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get safeTop(): number { return this.ui.safeTop; }
  private get safeBottom(): number { return this.ui.safeBottom; }

  private switchTab(next: number): void {
    if (next === this.tab) return;
    this.tab = next;
    // 已挂载过的 TabContent 切回来不会重新 aboutToAppear，显式触发子页 reload。
    UiState.get().dataVersion = UiState.get().dataVersion + 1;
    if (next === 0) this.bgRev = this.bgRev + 1;
    this.pageOpacity = 0.92;
    this.getUIContext().animateTo({
      duration: 200,
      curve: curves.springCurve(0.55, 1, 0.7, 1)
    }, () => {
      this.pageOpacity = 1;
    });
  }

  @Monitor('ui.openRevisit')
  onOpenRevisit(monitor: IMonitor): void {
    this.applyOpenRevisit();
  }

  @Monitor('ui.errorRev')
  onErrorRev(monitor: IMonitor): void {
    this.flushError();
  }

  @Monitor('ui.dataVersion')
  onBgData(monitor: IMonitor): void {
    this.bgRev = this.bgRev + 1;
  }

  @Monitor('ui.bgSavedRev')
  onBgFileSaved(monitor: IMonitor): void {
    this.bgRev = this.bgRev + 1;
  }

  private flushError(): void {
    const message: string = this.ui.errorMessage;
    if (message.length === 0) return;
    const hint: string = this.ui.errorHint;
    const full: string = hint.length > 0 ? message + '\n\n' + hint : message;
    try {
      if (this.ui.errorCanOpenSettings) {
        this.getUIContext().showAlertDialog({
          title: '出了点问题',
          message: full,
          primaryButton: {
            value: '知道了',
            action: () => {
              AppError.clear();
            }
          },
          secondaryButton: {
            value: '去设置',
            action: () => {
              AppError.clear();
              this.switchTab(4);
              this.ui.settingsSection = 'data';
            }
          }
        });
      } else {
        this.getUIContext().showAlertDialog({
          title: '出了点问题',
          message: full,
          primaryButton: {
            value: '知道了',
            action: () => {
              AppError.clear();
            }
          }
        });
      }
    } catch (e) {
      this.toast(full);
      AppError.clear();
    }
  }

  private applyOpenRevisit(): void {
    if (this.ui.openRevisit) {
      this.switchTab(0);
      this.ui.openRevisit = false;
    }
  }

  onBackPress(): boolean {
    if (this.ritualVisible) {
      this.ritualVisible = false;
      return true;
    }
    const anySheet: boolean = (UiState.get().sheetOpenToday) ||
      (UiState.get().sheetOpenMine) ||
      (UiState.get().sheetOpenArchive);
    if (anySheet) {
      const r: number = UiState.get().backRev;
      UiState.get().backRev = r + 1;
      return true;
    }
    if (this.tab !== 0) {
      this.switchTab(0);
      return true;
    }
    return false;
  }

  private applyFontScale(scale: number): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.getApplicationContext().setFontSizeScale(scale);
    } catch (e) {
      // 旧系统不支持时保持系统字号
    }
  }

  private ditherVP: number = 73;

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  async aboutToAppear(): Promise<void> {
    RefreshBus.register(this.refreshHandler);
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      this.ditherVP = 256 / density;
    } catch (e) {
      this.ditherVP = 73;
    }
    try {
      this.getUIContext().getFont().registerFont({
        familyName: 'JuxiaMaoken',
        familySrc: $rawfile('fonts/MaokenYingBiKaiShuJ.ttf')
      });
    } catch (e) {
      // 字体注册失败时回退到系统字体
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await Store.get().init(ctx);
    await RestoreRecovery.recover(ctx);
    const bs = this.bgStyle();
    this.ui.bgBrightness = bs.brightness;
    this.ui.bgBlur = bs.blur;
    this.ui.bgScrim = bs.scrim;
    this.ui.bgGlow = bs.glowValue;
    this.ui.bgGrain = bs.grainValue;
    this.ui.bgDither = bs.ditherValue;
    this.bgReady = true;
    this.bgRev = this.bgRev + 1;
    const b = Store.get().data.settings.background;
    const keepPaths: string[] = [b.light.path, b.dark.path, b.lightPlain.path, b.darkPlain.path]
      .filter((p: string) => p.length > 0);
    BackgroundService.cleanup(ctx, keepPaths);
    this.flushError();
    const st = Store.get();
    this.bootLong = st.data.settings.bootLong;
    this.bootText = st.data.settings.bootText;
    this.bootHoldMs = st.data.settings.bootHoldMs;
    this.bootFontScale = st.data.settings.bootFontScale;
    this.privacyOpen = !st.data.settings.privacyAccepted;
    this.guideOpen = st.data.settings.privacyAccepted && !st.data.meta.seen && !st.guideDone();
    if (this.guideOpen) this.guideReplay = false;
    const sysScale: number = ctx.config.fontSizeScale !== undefined ? ctx.config.fontSizeScale : 1.0;
    UiState.get().systemFontScale = sysScale;
    this.applyFontScale(st.data.settings.fontScaleFollow ? sysScale : st.data.settings.fontScale);
    st.rollDay();
    UiState.get().skin = st.data.settings.skin;
    UiState.get().appName = st.data.settings.appName;
    UiState.get().showDays = st.data.settings.showDays;
    UiState.get().showSeal = st.data.settings.showSeal;
    UiState.get().dayCount = st.dayCount();
    UiState.get().themeMode = st.data.settings.theme;
    st.postponeMissedRevisits();
    ReminderService.rescheduleAll(ctx, false);
    this.applyDark(st.data.settings.theme);
    this.ready = true;
    this.scheduleDayTick();
    this.fadeBoot();
    setTimeout(() => {
      MaterialRepair.run(ctx);
    }, 1200);
    if (this.ui.openRevisit) {
      this.applyOpenRevisit();
    }
  }

  private lastReschedule: number = 0;
  private refreshHandler: () => void = (): void => {
    this.bgRev = this.bgRev + 1;
  };
  private dayTimer: number = -1;

  private refreshDay(): void {
    const st = Store.get();
    st.rollDay();
    UiState.get().dayCount = st.dayCount();
  }

  private scheduleDayTick(): void {
    if (this.dayTimer >= 0) {
      clearTimeout(this.dayTimer);
      this.dayTimer = -1;
    }
    const now: number = Date.now();
    const next: Date = new Date(now);
    next.setHours(24, 0, 1, 0);
    const delay: number = Math.max(1000, next.getTime() - now);
    this.dayTimer = setTimeout(() => {
      this.refreshDay();
      this.scheduleDayTick();
    }, delay) as number;
  }

  aboutToDisappear(): void {
    RefreshBus.unregister(this.refreshHandler);
    if (this.dayTimer >= 0) {
      clearTimeout(this.dayTimer);
      this.dayTimer = -1;
    }
  }

  onPageHide(): void {
    Store.get().flush().catch((e: Error) => {
      console.error('juxia page flush fail', String(e));
    });
  }

  onPageShow(): void {
    if (!this.ready) return;
    this.refreshDay();
    this.scheduleDayTick();
    // 回到前台强制所有页重载：恢复/清空/背景保存后不依赖子页各自的 @Monitor。
    UiState.get().dataVersion = UiState.get().dataVersion + 1;
    Store.get().postponeMissedRevisits();
    const now: number = Date.now();
    if (now - this.lastReschedule < 60000) return;
    this.lastReschedule = now;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx, false);
  }

  private applyDark(theme: string): void {
    const sys: boolean = UiState.get().systemDark;
    const d: boolean = theme === 'dark' || (theme === 'system' && sys);
    UiState.get().dark = d;
  }

  private bootDark(): boolean {
    return UiState.get().systemDark;
  }

  private bootColor(): string {
    return this.bootDark() ? '#191712' : '#EDE6D3';
  }

  private fadeBoot(): void {
    const hasText: boolean = this.bootLong && this.bootText.trim().length > 0;
    if (!hasText) {
      this.dissolveBoot();
      return;
    }
    setTimeout(() => {
      this.bootTextOpacity = 1;
    }, 120);
    setTimeout(() => {
      this.dissolveBoot();
    }, this.bootHoldMs);
  }

  private dissolveBoot(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.bootDone = true;
      }
    }, () => {
      this.bootOpacity = 0;
    });
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private bgTop(): string {
    if (this.skin === 'plain') return this.t().bg;
    return this.dark ? '#201c15' : '#f3eddc';
  }

  private bgBottom(): string {
    if (this.skin === 'plain') return this.t().bg;
    return this.dark ? '#14110b' : '#e9e0cb';
  }

  private glow1(): string {
    return this.dark ? '#571e1834' : '#ccfff3c4';
  }

  private glow2(): string {
    return this.dark ? '#5c36422e' : '#8ce4e9c5';
  }

  private glow3(): string {
    return this.dark ? '#5754402e' : '#80d5c2ad';
  }

  private bgStyle(): BgImageStyle {
    const b = Store.get().data.settings.background;
    if (this.dark) {
      if (this.skin === 'plain' && b.darkPlain.path.length > 0) return b.darkPlain;
      return b.dark;
    }
    if (this.skin === 'plain' && b.lightPlain.path.length > 0) return b.lightPlain;
    return b.light;
  }

  private hasBg(): boolean {
    return this.bgStyle().path.length > 0;
  }

  private glowOpacity(): number {
    return this.ui.bgGlow / 100;
  }

  private grainOpacity(): number {
    const base: number = this.skin === 'plain' ? 0.22 : 0.5;
    const v: number = this.ui.bgGrain;
    return v <= 100 ? base * v / 100 : base * v / 400;
  }

  private startRitual(ctx: RitualCtx): void {
    this.ritualCtx = ctx;
    this.ritualVisible = true;
  }

  private gotoMine(id: string, panel: string): void {
    this.switchTab(1);
    UiState.get().mineOpenId = id;
    UiState.get().mineOpenPanel = panel;
    const rev: number = UiState.get().mineOpenRev;
    UiState.get().mineOpenRev = rev + 1;
  }

  private redrawRitual(): void {
    const old: RitualCtx = this.ritualCtx;
    const st = Store.get();
    const next = new RitualCtx();
    if (old.type === 'lib') {
      const pool = st.libPool().filter((q: LibEntry) => q.text !== old.text);
      if (pool.length === 0) {
        this.toast('句库里没有别的句子了');
        return;
      }
      const b = pool[Math.floor(Math.random() * pool.length)];
      next.type = 'lib';
      next.text = b.text;
      next.source = b.source;
      next.badge = '句库 · 收藏';
      next.tag = b.tag.length > 0 ? b.tag : '原文';
      next.origin = b.origin;
      next.todayFlow = old.todayFlow;
    } else if (old.type === 'own' && old.entry !== null) {
      const kind: string = old.entry.kind;
      const pool = st.ownActive(kind).filter((e: OwnEntry) => e.text !== old.text);
      if (pool.length === 0) {
        this.toast('这一类只有这一句');
        return;
      }
      const e = pool[Math.floor(Math.random() * pool.length)];
      next.type = 'own';
      next.entry = e;
      next.text = e.text;
      next.badge = kind === 'encourage' ? '自己的话 · 鼓励' : '自己的话 · 一件旧事';
      next.tag = '自己写的';
      next.source = '';
    } else {
      this.toast('没有可换的句子');
      return;
    }
    this.ritualVisible = false;
    setTimeout(() => {
      this.ritualCtx = next;
      this.ritualVisible = true;
    }, 80);
  }

  private readonly tabLabels: string[] = ['今日', '我的', '句库', '回忆', '设置'];

  @Builder
  TabsRow() {
    Row() {
      ForEach(this.tabLabels, (label: string, index: number) => {
        Column({ space: 4 }) {
          TabIcon({
            index: index,
            color: this.tab === index ? (this.dark ? this.t().inkSoft : '#ffffff') : this.t().inkSoft
          })
          Text(label)
            .fontFamily(FONT_SANS)
            .fontSize(10)
            .letterSpacing(2)
            .fontColor(this.tab === index ? (this.dark ? this.t().inkSoft : '#ffffff') : this.t().inkSoft)
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .justifyContent(FlexAlign.Center)
        .borderRadius(999)
        .backgroundColor(this.tab === index ? (this.dark ? Color.Transparent : this.t().ink) : Color.Transparent)
        .border({
          width: this.dark && this.tab === index ? { bottom: 1 } : 0,
          color: this.dark ? this.t().seal : Color.Transparent
        })
        .onClick(() => {
          this.switchTab(index);
        })
      }, (label: string, index: number) => `${label}${index}`)
    }
    .width('100%')
    .padding(7)
  }

  @Builder
  BottomBar() {
    Stack() {
      this.TabsRow()
    }
    .width('92%')
    .constraintSize({ maxWidth: 440 })
    .borderRadius(this.skin === 'plain' ? 12 : 999)
    .backgroundColor(this.skin === 'plain'
      ? this.t().cardSolid
      : (this.dark ? '#a62b271e' : '#a6fffdf6'))
    .backdropBlur(this.skin === 'plain' ? 0 : 18)
    .border({
      width: this.skin === 'plain' ? { top: 1 } : 1,
      color: this.skin === 'plain' ? this.t().line : (this.dark ? '#30ffffff' : '#8cffffff')
    })
    .shadow(this.skin === 'plain'
      ? { radius: 0, color: Color.Transparent }
      : { radius: 40, color: this.t().shadowLift, offsetY: 16 })
    .margin({ bottom: 14 + this.safeBottom })
  }

  @Builder
  PrivacyGate() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
      Column({ space: 12 }) {
        Text('先说清楚隐私')
          .fontFamily(FONT_SERIF)
          .fontSize(22)
          .fontColor(this.t().ink)
        Text('句栖把句子、备注、旧事和设置加密保存在本机，不上传；没有账号、广告或统计。')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .width('100%')
        Text('句栖不联网、不上传。备份由你主动导出，通知是本地提醒。')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .width('100%')
        Text('查看完整隐私政策')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .fontColor(this.t().seal)
          .width('100%')
          .margin({ top: 4 })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPage' }).catch(() => {});
          })
        Row({ space: 10 }) {
          Text('不同意')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .fontColor(this.t().inkSoft)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .border({ width: 1, color: this.t().line })
            .borderRadius(this.t().radiusBtn)
            .onClick(() => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              ctx.terminateSelf();
            })
          Text('同意并继续')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .fontColor(this.t().bg)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .backgroundColor(this.t().ink)
            .borderRadius(this.t().radiusBtn)
            .onClick(() => {
              const st = Store.get();
              st.data.settings.privacyAccepted = true;
              st.saveKv();
              this.privacyOpen = false;
              if (!st.data.meta.seen && !st.guideDone()) {
                this.guideReplay = false;
                this.guideOpen = true;
              }
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 520 })
      .padding(24)
      .backgroundColor(this.t().card)
      .borderRadius(20)
      .border({ width: 1, color: this.t().line })
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  @Monitor('ui.dataVersion')
  demoMoodChanged(monitor: IMonitor): void {
    if (!this.demoActive || this.demoStep !== 0) return;
    const mood: string = Store.get().data.day.mood;
    if (mood !== 'good' && mood !== 'bad') return;
    const branch: string = mood === 'bad' ? 'rain' : 'sun';
    Store.get().switchDemo(branch);
    this.demoBranch = branch;
    this.demoStep = 1;
    this.ui.demoBusy = true;
    this.runDemoStep();
  }

  private demoMax(): number {
    return this.demoBranch === 'rain' ? 6 : 5;
  }

  private demoArchivedId(): string {
    const list = Store.get().data.own.filter((e: OwnEntry) => e.kind === 'wound' && e.archAt > 0);
    return list.length > 0 ? list[list.length - 1].id : '';
  }

  private demoId(): string {
    const kind: string = this.demoBranch === 'rain' ? 'wound' : 'encourage';
    const list = Store.get().data.own.filter((e: OwnEntry) => e.kind === kind && e.archAt === 0);
    return list.length > 0 ? list[list.length - 1].id : '';
  }

  private demoCaption(): string {
    if (this.demoStep === 0) return '先选一条线：晴，写鼓励；雨，写旧事。';
    if (this.demoStep === 1) return this.demoBranch === 'rain' ? '雨线：把难过写进树洞。' : '晴线：写一句对自己的鼓励。';
    if (this.demoStep === 2) return this.demoBranch === 'rain' ? '抽到一句鼓励，陪着你。' : '抽到一件旧事，完善心境。';
    if (this.demoStep === 3) return '抽到之后，可以回一句话。';
    if (this.demoStep === 4) return '在「我的」里，给这句话留一条备注，也可以关联别的句子。';
    if (this.demoStep === 5) return this.demoBranch === 'rain' ? '旧事归档为「已解决 / 已放下」，约定 14 天后回访。' : '鼓励归档为「看起来很蠢 / 听腻了」，不再回访。';
    return '14 天后，回访卡回来；可以再回一句。';
  }

  private demoStepLabel(): string {
    if (this.demoStep === 0) return '开始演示';
    return this.demoBranch === 'rain' ? `雨线 · 第 ${this.demoStep} 步` : `晴线 · 第 ${this.demoStep} 步`;
  }

  private hasDemoReply(text: string): boolean {
    return Store.get().data.own.some((e: OwnEntry) =>
      e.kind === 'reply' && e.replyToId === this.demoId() && e.text === text);
  }

  private executeDemoStep(): void {
    const st = Store.get();
    const id: string = this.demoId();
    if (this.demoStep === 1) {
      st.data.own = [];
      st.data.day.mood = this.demoBranch === 'rain' ? 'bad' : 'good';
      st.data.day.wrote = false;
      st.data.day.drew = false;
      st.bump();
      this.switchTab(0);
      setTimeout(() => {
        if (!this.demoActive || this.demoStep !== 1) return;
        this.ui.demoBranch = this.demoBranch;
        this.ui.demoText = this.demoBranch === 'rain' ? '那件事，我还是会想起。' : '今天已经做得够好了。慢一点，也没有关系。';
        this.ui.demoAction = 'write';
        this.ui.demoSeq = this.ui.demoSeq + 1;
        this.ui.openWriteReq = this.ui.openWriteReq + 1;
      }, 300);
      return;
    }
    if (this.demoStep === 2) {
      st.ensureDemoCross(this.demoBranch);
      this.ui.demoBranch = this.demoBranch;
      this.ui.demoAction = 'draw';
      this.ui.demoSeq = this.ui.demoSeq + 1;
      this.switchTab(0);
      return;
    }
    if (this.demoStep === 3) {
      this.ui.demoAction = 'reply';
      this.ui.demoText = '原来那天我已经做得够好了。';
      this.ui.demoSeq = this.ui.demoSeq + 1;
      return;
    }
    if (this.demoStep === 4) {
      this.ritualVisible = false;
      if (id.length === 0) return;
      this.switchTab(1);
      setTimeout(() => {
        if (!this.demoActive || this.demoStep !== 4) return;
        this.ui.demoTarget = id;
        this.ui.demoText = '这句话，随时可以补一条备注。';
        this.ui.demoAction = 'note';
        this.ui.demoSeq = this.ui.demoSeq + 1;
      }, 180);
      return;
    }
    if (this.demoStep === 5) {
      this.ritualVisible = false;
      if (id.length === 0) return;
      this.switchTab(1);
      setTimeout(() => {
        if (!this.demoActive || this.demoStep !== 5) return;
        this.ui.demoTarget = id;
        this.ui.demoBranch = this.demoBranch;
        this.ui.demoAction = 'archive';
        this.ui.demoSeq = this.ui.demoSeq + 1;
      }, 180);
      setTimeout(() => {
        if (!this.demoActive || this.demoStep !== 5) return;
        this.switchTab(3);
      }, 4800);
      return;
    }
    if (this.demoStep === 6) {
      this.ritualVisible = false;
      const archivedId: string = this.demoArchivedId();
      if (archivedId.length === 0) return;
      const entry = st.data.own.find((e: OwnEntry) => e.id === archivedId);
      if (entry !== undefined) {
        entry.revisitAt = Date.now();
        entry.snoozeUntil = 0;
        st.bump();
      }
      this.switchTab(0);
      setTimeout(() => {
        if (!this.demoActive || this.demoStep !== 6) return;
        this.ui.demoTarget = archivedId;
        this.ui.demoText = '现在再看，它没有当时那么重了。';
        this.ui.demoAction = 'revisitToday';
        this.ui.demoSeq = this.ui.demoSeq + 1;
      }, 250);
    }
  }

  private markDemoSeen(): void {
    this.demoFinished = true;
    if (this.demoBranch === 'rain') this.demoRainSeen = true;
    else this.demoSunSeen = true;
  }

  private runDemoStep(): void {
    if (this.demoTimer >= 0) clearTimeout(this.demoTimer);
    this.executeDemoStep();
  }

  private nextDemoStep(): void {
    if (this.ui.demoBusy) return;
    if (this.demoTimer >= 0) clearTimeout(this.demoTimer);
    if (this.demoStep === 0 && Store.get().data.day.mood.length === 0) {
      return;
    }
    if (this.demoStep >= this.demoMax()) {
      this.markDemoSeen();
      return;
    }
    this.demoStep += 1;
    this.runDemoStep();
  }

  private startRealDemo(branch: string): void {
    const st = Store.get();
    if (!st.startDemo('blank')) {
      this.guideOpen = false;
      this.demoActive = false;
      return;
    }
    this.demoBranch = branch === 'blank' ? 'sun' : branch;
    this.demoStep = 0;
    this.demoSavedReplay = this.guideReplay;
    this.demoActive = true;
    this.demoFinished = false;
    this.guideOpen = false;
    this.guideStartStage = '';
    this.switchTab(0);
  }

  private finishRealDemo(): void {
    if (this.demoTimer >= 0) clearTimeout(this.demoTimer);
    const st = Store.get();
    st.endDemo();
    this.demoActive = false;
    if (this.demoSavedReplay) {
      this.guideReplay = false;
      this.switchTab(4);
      return;
    }
    this.guideReplay = false;
    this.guideOpen = true;
    this.guideStartStage = 'write';
  }

  private switchDemoBranch(): void {
    const next: string = this.demoBranch === 'rain' ? 'sun' : 'rain';
    Store.get().switchDemo(next);
    this.demoBranch = next;
    this.demoStep = 1;
    this.demoFinished = false;
    this.runDemoStep();
  }

  @Builder
  DemoFinish() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Text(this.demoBranch === 'rain' ? '雨线看完了' : '晴线看完了')
          .fontFamily(FONT_SERIF)
          .fontSize(22)
          .fontColor(this.t().inkStrong)
        Text(this.demoBranch === 'rain'
          ? '旧事归档后，14 天后会回访；回访时还能再回一句。'
          : '鼓励归档后，不再回访。')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .textAlign(TextAlign.Center)
        if (!(this.demoBranch === 'sun' ? this.demoRainSeen : this.demoSunSeen)) {
          Text('另一条也看看')
            .fontFamily(FONT_SANS)
            .fontSize(15)
            .fontColor(this.t().bg)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .borderRadius(this.t().radiusBtn)
            .backgroundColor(this.t().ink)
            .onClick(() => this.switchDemoBranch())
        }
        Row({ space: 10 }) {
          if (this.demoSavedReplay) {
            Text('退出演示')
              .fontFamily(FONT_SANS)
              .fontSize(12)
              .fontColor(this.t().inkSoft)
              .onClick(() => this.finishRealDemo())
          } else {
            Text('写我的第一句')
              .fontFamily(FONT_SANS)
              .fontSize(13)
              .fontColor(this.t().seal)
              .onClick(() => this.finishRealDemo())
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('82%')
      .padding(20)
      .borderRadius(this.t().radiusCard)
      .backgroundColor(this.t().card)
      .border({ width: 2, color: this.t().seal })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DemoBanner() {
    Column({ space: 8 }) {
      Row() {
        Text(this.demoStepLabel() + (this.demoBranch === 'rain' ? ' · 雨线' : ' · 晴线'))
          .fontFamily(FONT_SANS)
          .fontSize(12)
          .fontColor(this.t().seal)
        Blank()
        if (this.demoSavedReplay) {
          Text('退出演示')
            .fontFamily(FONT_SANS)
            .fontSize(12)
            .fontColor(this.t().inkSoft)
            .onClick(() => this.finishRealDemo())
        }
      }
      .width('100%')
      Text('演示数据 · 不会保存')
        .fontFamily(FONT_SANS)
        .fontSize(11)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Text(this.demoCaption())
        .fontFamily(FONT_SANS)
        .fontSize(14)
        .lineHeight(24)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Row({ space: 10 }) {
        Blank()
        Text(this.demoStep >= this.demoMax() ? '结束演示' : '下一步')
          .fontFamily(FONT_SANS)
          .fontSize(14)
          .fontColor(this.t().bg)
          .padding({ left: 20, right: 20, top: 9, bottom: 9 })
          .borderRadius(this.t().radiusBtn)
          .backgroundColor(this.t().ink)
          .onClick(() => this.nextDemoStep())
      }
      .width('100%')
    }
    .width('88%')
    .padding(14)
    .borderRadius(this.t().radiusCard)
    .backgroundColor(this.t().card)
    .border({ width: 1, color: this.t().seal })
    .margin({ bottom: 96 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Text(`${this.ui.dataVersion}`)
        .width(0)
        .height(0)
        .opacity(0)
      // 最底层兜底：API 26 不再设置原生窗口底色，用页面底色覆盖系统默认色。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.dark ? '#14110b' : '#F6F0E3')
      if (this.skin !== 'plain') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [[this.bgTop(), 0.0], [this.t().bg, 0.42], [this.bgBottom(), 1.0]]
          })
          .blur(!this.hasBg() ? this.ui.bgBlur * 0.5 : 0)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: this.dark
              ? [['#211e19', 0.0], ['#1b1a17', 0.55], ['#171614', 1.0]]
              : [[this.t().bg, 0.0], [this.t().bg, 1.0]]
          })
          .blur(!this.hasBg() ? this.ui.bgBlur * 0.5 : 0)
      }
      if (this.bgReady && this.hasBg() && this.bgRev >= 0) {
        Image('file://' + this.bgStyle().path)
          .id('bg-photo-' + this.bgRev + '-' + this.ui.bgSavedRev)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .brightness(Math.min(1, this.ui.bgBrightness))
          .blur(this.ui.bgBlur * 0.5)
      }
      if (this.ui.bgBrightness > 1) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#FFFFFF')
          .opacity((this.ui.bgBrightness - 1) * 0.55)
      }
      if (this.ui.bgBrightness < 1) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .opacity((1 - this.ui.bgBrightness) * 0.85)
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.dark ? '#000000' : '#F6F0E3')
        .opacity(this.ui.bgScrim)
      if (this.bgRev >= 0 && this.ui.bgGlow > 0) {
        if (this.skin !== 'plain') {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['74%', '4%'],
              radius: '78%',
              colors: [[this.glow1(), 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowOpacity())
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['8%', '92%'],
              radius: '70%',
              colors: [[this.glow2(), 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowOpacity())
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['92%', '84%'],
              radius: '68%',
              colors: [[this.glow3(), 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowOpacity())
        } else if (this.dark) {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['82%', '0%'],
              radius: '80%',
              colors: [['#22c98a5e', 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowOpacity())
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['12%', '92%'],
              radius: '70%',
              colors: [['#107a9bb0', 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowOpacity())
        }
      }
      if (this.dark && this.bgRev >= 0 && this.ui.bgDither > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundImage($r('app.media.dither'), ImageRepeat.XY)
          .backgroundImageSize({ width: this.ditherVP, height: this.ditherVP })
          .opacity(this.ui.bgDither / 100)
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundImage(this.ui.bgGrain > 100
          ? (this.dark ? $r('app.media.grain_night_visible') : $r('app.media.grain_visible'))
          : (this.dark ? $r('app.media.grain_night') : $r('app.media.grain')),
          this.dark ? ImageRepeat.NoRepeat : ImageRepeat.XY)
        .backgroundImageSize({ width: this.dark ? '100%' : 140, height: this.dark ? '100%' : 140 })
        .opacity(this.grainOpacity())
      Column() {
        TopBar()

        Stack({ alignContent: Alignment.Top }) {
          if (!this.ready) {
            Column()
              .width('100%')
              .height('100%')
          } else {
            Tabs({ index: this.tab }) {
              TabContent() {
                TodayPage({
                  startRitual: (ctx: RitualCtx) => {
                    this.startRitual(ctx);
                  },
                  goSettings: () => {
                    UiState.get().settingsSection = 'data';
                    this.switchTab(4);
                  },
                  goLibrary: () => {
                    this.switchTab(2);
                  }
                })
              }

              TabContent() {
                MinePage({
                  goToday: () => {
                    this.switchTab(0);
                  },
                  goLibrary: () => {
                    this.switchTab(2);
                  }
                })
              }

              TabContent() {
                LibraryPage({
                  startRitual: (ctx: RitualCtx) => {
                    this.startRitual(ctx);
                  }
                })
              }

              TabContent() {
                ArchivePage()
              }

              TabContent() {
                SettingsPage({
                  skin: this.skin,
                  dark: this.dark,
                  onOpenGuide: () => {
                    this.guideReplay = true;
                    this.guideOpen = true;
                  }
                })
              }
            }
            .barHeight(0)
            .scrollable(false)
            .animationDuration(200)
            .width('100%')
            .height('100%')
            .opacity(this.pageOpacity)
            .onChange((i: number) => {
              this.switchTab(i);
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeTop })

      this.BottomBar()

      if (this.ritualVisible) {
        RitualOverlay({
          ctx: this.ritualCtx,
          onClose: () => {
            this.ritualVisible = false;
          },
          onRedraw: () => {
            this.redrawRitual();
          },
          onBind: (id: string) => {
            this.ritualVisible = false;
            this.gotoMine(id, 'bind');
          },
          onArchive: (id: string) => {
            this.ritualVisible = false;
            this.gotoMine(id, 'archive');
          }
        })
      }
      if (this.demoActive && !this.demoFinished) {
        Row() {
          Text('自动演示 · 不会保存')
            .fontFamily(FONT_SANS)
            .fontSize(11.5)
            .letterSpacing(1)
            .fontColor(this.t().sealInk)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(this.t().seal)
        }
        .position({ x: 0, y: this.ui.safeTop + 8 })
        .width('100%')
        .justifyContent(FlexAlign.Center)
        this.DemoBanner()
      }
      if (this.demoActive && this.demoFinished) {
        this.DemoFinish()
      }
      if (!this.bootDone) {
        Column() {
          if (this.bootLong && this.bootText.trim().length > 0) {
            Text(this.bootText)
              .fontFamily(FONT_SERIF)
              .fontSize(16 * this.bootFontScale)
              .lineHeight(30 * this.bootFontScale)
              .letterSpacing(2)
              .fontColor(this.bootDark() ? '#E9E4D5' : '#3A3A37')
              .width('78%')
              .textAlign(TextAlign.Center)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .opacity(this.bootTextOpacity)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.bootColor())
        .backgroundImage(this.bootDark() ? $r('app.media.grain_night') : $r('app.media.grain'),
          ImageRepeat.XY)
        .backgroundImageSize({ width: 140, height: 140 })
        .opacity(this.bootOpacity)
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.ready && this.bootDone && this.privacyOpen) {
        this.PrivacyGate()
      }
      if (this.ready && this.bootDone && this.guideOpen) {
        WelcomeGuide({
          replay: this.guideReplay,
          startStage: this.guideStartStage,
          startBranch: this.demoBranch,
          onBeginDemo: () => this.startRealDemo('blank'),
          onDone: () => {
            const st = Store.get();
            if (!this.guideReplay) st.markGuideDone();
            this.guideOpen = false;
            this.guideReplay = false;
            this.guideStartStage = '';
          },
          onSkip: () => {
            const st = Store.get();
            if (!this.guideReplay) st.markGuideDone();
            this.guideOpen = false;
            this.guideReplay = false;
            this.guideStartStage = '';
          },
          onWriteAnother: () => {
            const st = Store.get();
            if (!this.guideReplay) st.markGuideDone();
            this.guideOpen = false;
            this.guideReplay = false;
            this.guideStartStage = '';
            this.switchTab(0);
            this.ui.openWriteReq = this.ui.openWriteReq + 1;
          },
          onGoMine: () => {
            const st = Store.get();
            if (!this.guideReplay) st.markGuideDone();
            this.guideOpen = false;
            this.guideReplay = false;
            this.guideStartStage = '';
            this.switchTab(1);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
  }
}


