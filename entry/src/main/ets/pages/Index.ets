// 句栖 · 根页面
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { Store } from '../data/Store';
import { ReminderService } from '../services/ReminderService';
import { RitualCtx, OwnEntry, LibEntry } from '../model/Types';
import { Tokens, getTokens, FONT_SERIF } from '../theme/Theme';
import { TopBar, TabIcon } from '../components/Chrome';
import { RitualOverlay } from '../components/RitualOverlay';
import { TodayPage } from './TodayPage';
import { MinePage } from './MinePage';
import { LibraryPage } from './LibraryPage';
import { ArchivePage } from './ArchivePage';
import { SettingsPage } from './SettingsPage';
import { UiState } from '../state/UiState';
import { AppError } from '../services/AppError';

@Entry
@ComponentV2
struct Index {
  @Local ui: UiState = UiState.get();
  @Local tab: number = 0;
  @Local pageOpacity: number = 1;
  @Local ready: boolean = false;
  @Local privacyOpen: boolean = false;
  @Local bootOpacity: number = 1;
  @Local bootDone: boolean = false;
  @Local bootTextOpacity: number = 0;
  @Local bootLong: boolean = false;
  @Local bootText: string = '';
  @Local bootHoldMs: number = 1200;
  @Local bootFontScale: number = 1.25;
  @Local ritualVisible: boolean = false;
  @Local ritualCtx: RitualCtx = new RitualCtx();
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get safeTop(): number { return this.ui.safeTop; }
  private get safeBottom(): number { return this.ui.safeBottom; }

  private switchTab(next: number): void {
    if (next === this.tab) return;
    this.tab = next;
    this.pageOpacity = 0.985;
    this.getUIContext().animateTo({
      duration: 140,
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

  private flushError(): void {
    const message: string = this.ui.errorMessage;
    if (message.length === 0) return;
    this.toast(message);
    AppError.clear();
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
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      this.ditherVP = 256 / density;
    } catch (e) {
      this.ditherVP = 73;
    }
    try {
      this.getUIContext().getFont().registerFont({
        familyName: 'JuxiaSerif',
        familySrc: $rawfile('fonts/NotoSerifSC-Sub.ttf')
      });
    } catch (e) {
      // 字体注册失败时回退到系统字体
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await Store.get().init(ctx);
    this.flushError();
    const st = Store.get();
    this.bootLong = st.data.settings.bootLong;
    this.bootText = st.data.settings.bootText;
    this.bootHoldMs = st.data.settings.bootHoldMs;
    this.bootFontScale = st.data.settings.bootFontScale;
    this.privacyOpen = !st.data.settings.privacyAccepted;
    const sysScale: number = ctx.config.fontSizeScale !== undefined ? ctx.config.fontSizeScale : 1.0;
    UiState.get().systemFontScale = sysScale;
    this.applyFontScale(st.data.settings.fontScaleFollow ? sysScale : st.data.settings.fontScale);
    st.rollDay();
    UiState.get().skin = st.data.settings.skin;
    UiState.get().appName = st.data.settings.appName;
    UiState.get().showDays = st.data.settings.showDays;
    UiState.get().dayCount = st.dayCount();
    UiState.get().themeMode = st.data.settings.theme;
    st.postponeMissedRevisits();
    ReminderService.rescheduleAll(ctx, false);
    this.applyDark(st.data.settings.theme);
    this.ready = true;
    this.fadeBoot();
    if (this.ui.openRevisit) {
      this.applyOpenRevisit();
    }
  }

  private lastReschedule: number = 0;

  onPageShow(): void {
    if (!this.ready) return;
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
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowBackgroundColor(d ? '#14110b' : '#F6F0E3');
      });
    } catch (e) {
    }
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
          .fontSize(13)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .width('100%')
        Text('句栖不联网、不上传。备份由你主动导出，通知是本地提醒。')
          .fontSize(13)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .width('100%')
        Text('查看完整隐私政策')
          .fontSize(13)
          .fontColor(this.t().seal)
          .width('100%')
          .margin({ top: 4 })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPage' }).catch(() => {});
          })
        Row({ space: 10 }) {
          Text('不同意')
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
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.skin !== 'plain') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [[this.bgTop(), 0.0], [this.t().bg, 0.42], [this.bgBottom(), 1.0]]
          })
        if (this.dark) {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['74%', '4%'],
              radius: '78%',
              colors: [[this.glow1(), 0.0], ['#00FFFFFF', 1.0]]
            })
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['8%', '92%'],
              radius: '70%',
              colors: [[this.glow2(), 0.0], ['#00FFFFFF', 1.0]]
            })
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['92%', '84%'],
              radius: '68%',
              colors: [[this.glow3(), 0.0], ['#00FFFFFF', 1.0]]
            })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['74%', '4%'],
              radius: '78%',
              colors: [[this.glow1(), 0.0], ['#00FFFFFF', 1.0]]
            })
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['8%', '92%'],
              radius: '70%',
              colors: [[this.glow2(), 0.0], ['#00FFFFFF', 1.0]]
            })
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['92%', '84%'],
              radius: '68%',
              colors: [[this.glow3(), 0.0], ['#00FFFFFF', 1.0]]
            })
        }
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
        if (this.dark) {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['82%', '0%'],
              radius: '80%',
              colors: [['#22c98a5e', 0.0], ['#00FFFFFF', 1.0]]
            })
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['12%', '92%'],
              radius: '70%',
              colors: [['#107a9bb0', 0.0], ['#00FFFFFF', 1.0]]
            })
        }
      }
      if (this.dark) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundImage($r('app.media.dither'), ImageRepeat.XY)
          .backgroundImageSize({ width: this.ditherVP, height: this.ditherVP })
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundImage(this.dark ? $r('app.media.grain_night') : $r('app.media.grain'),
          this.dark ? ImageRepeat.NoRepeat : ImageRepeat.XY)
        .backgroundImageSize({ width: this.dark ? '100%' : 140, height: this.dark ? '100%' : 140 })
        .opacity(this.skin === 'plain' ? 0.22 : 0.5)

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
                SettingsPage({ skin: this.skin, dark: this.dark })
              }
            }
            .barHeight(0)
            .scrollable(false)
            .animationDuration(0)
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
  }
}


