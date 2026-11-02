// 句栖 · 今日
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Store } from '../data/Store';
import {
  OwnEntry, LibEntry, RitualCtx, fmtDate, fmtMD, NoteItem
} from '../model/Types';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { MoodIcon } from '../components/Chrome';
import { ReminderService } from '../services/ReminderService';
import { UiState } from '../state/UiState';

@ComponentV2
export struct TodayPage {
  @Local ui: UiState = UiState.get();
  @Event startRitual: (ctx: RitualCtx) => void = () => {};
  @Event goSettings: () => void = () => {};
  @Event goLibrary: () => void = () => {};
  private get skin(): string { return this.ui.skin; }
  private set skin(v: string) { this.ui.skin = v; }
  private get dark(): boolean { return this.ui.dark; }
  private get appName(): string { return this.ui.appName; }
  private get showDays(): boolean { return this.ui.showDays; }
  @Monitor('ui.dataVersion')
  onData(monitor: IMonitor): void { this.load(); }
  @Monitor('ui.backRev')
  onBackReq(monitor: IMonitor): void {
    if (this.sheetOpen) {
      this.sheetOpen = false;
    }
  }
  @Local mood: string = '';
  @Local wrote: boolean = false;
  @Local drew: boolean = false;
  @Local choice: string = '';
  @Local seen: boolean = true;
  @Local encCount: number = 0;
  @Local woundCount: number = 0;
  @Local revisit: OwnEntry[] = [];
  @Local dayCount: number = 1;
  @Local nickname: string = '';
  @Local showGreeting: boolean = false;
  @Local inputText: string = '';
  @Local draftRestored: boolean = false;
  @Local showGuide: boolean = false;
  @Local writeOverride: string = '';
  @Local sheetOpen: boolean = false;
  @Local coverOpacity: number = 0;
  @Local sheetMode: string = '';
  @Local backupDismissed: boolean = false;
  @Local needSource: boolean = false;
  private lastText: string = '';

  @Monitor('sheetOpen')
  syncSheet(monitor: IMonitor): void {
    this.ui.sheetOpenToday = this.sheetOpen;
  }

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const st = Store.get();
    st.rollDay();
    this.mood = st.data.day.mood;
    this.wrote = st.data.day.wrote;
    this.drew = st.data.day.drew;
    this.seen = st.data.meta.seen;
    this.encCount = st.ownActive('encourage').length;
    this.woundCount = st.ownActive('wound').length;
    this.needSource = (!st.data.settings.drawOwn || (this.encCount === 0 && this.woundCount === 0)) &&
      (!st.data.settings.drawLib || st.libPool().length === 0);
    this.revisit = st.revisitDue();
    this.dayCount = st.dayCount();
    this.nickname = st.data.settings.nickname;
    this.showGreeting = st.data.settings.showGreeting;
    this.backupDismissed = st.data.day.backupDismissed;
    UiState.get().dayCount = this.dayCount;
    UiState.get().showDays = st.data.settings.showDays;
    this.ui.skin = st.data.settings.skin;
    if (this.inputText.length === 0) {
      const d: string = st.loadDraft(this.writeKind());
      if (d.length > 0) {
        this.inputText = d;
        this.draftRestored = true;
      }
    }
  }

  private queueDraft(): void {
    const kind: string = this.writeKind();
    if (this.inputText.length === 0) {
      Store.get().clearDraft(kind);
    } else {
      Store.get().saveDraft(kind, this.inputText);
    }
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private padBottom(): number {
    return 140;
  }

  private writeKind(): string {
    if (this.writeOverride.length > 0) return this.writeOverride;
    return this.mood === 'bad' ? 'wound' : 'encourage';
  }

  private setMood(m: string): void {
    if (m !== this.mood) {
      Store.get().data.day.mood = m;
      Store.get().data.day.wrote = false;
      Store.get().data.day.drew = false;
      this.writeOverride = '';
      this.choice = '';
      Store.get().saveKv();
    }
    this.load();
  }

  private openSheet(mode: string): void {
    this.sheetMode = mode;
    this.sheetOpen = true;
  }

  private startMoreWrite(kind: string): void {
    this.sheetOpen = false;
    this.writeOverride = kind;
    this.choice = 'write';
    Store.get().data.day.wrote = false;
    Store.get().data.day.drew = false;
    Store.get().saveKv();
    this.load();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  private startMoreDraw(kind: string): void {
    this.sheetOpen = false;
    setTimeout(() => {
      this.draw(kind, false);
    }, 120);
  }

  private saveOwn(): void {
    const text: string = this.inputText.trim();
    if (text.length === 0) {
      this.toast('先写一句，哪怕很短');
      return;
    }
    const kind: string = this.writeKind();
    Store.get().addOwn(kind, text);
    Store.get().clearDraft(kind);
    Store.get().data.day.drew = false;
    Store.get().saveKv();
    this.inputText = '';
    this.draftRestored = false;
    this.writeOverride = '';
    this.toast(kind === 'encourage' ? '收好了。低谷的日子，它会回来找你' : '写下来了，就已经轻了一点');
    this.load();
  }

  private pickLib(list: LibEntry[]): LibEntry | null {
    if (list.length === 0) return null;
    let e: LibEntry = list[Math.floor(Math.random() * list.length)];
    if (list.length > 1 && e.text === this.lastText) {
      e = list[Math.floor(Math.random() * list.length)];
    }
    this.lastText = e.text;
    return e;
  }

  private pickOwn(list: OwnEntry[]): OwnEntry | null {
    if (list.length === 0) return null;
    let e: OwnEntry = list[Math.floor(Math.random() * list.length)];
    if (list.length > 1 && e.text === this.lastText) {
      e = list[Math.floor(Math.random() * list.length)];
    }
    this.lastText = e.text;
    return e;
  }

  private primaryDrawKind(): string {
    if (this.mood === 'bad') return 'encourage';
    return this.woundCount > 0 ? 'wound' : 'lib';
  }

  private draw(kind: string, todayFlow: boolean = false): void {
    const st = Store.get();
    const ownOn: boolean = st.data.settings.drawOwn;
    const libOn: boolean = st.data.settings.drawLib;
    if (kind === 'encourage') {
      const pool: OwnEntry[] = ownOn ? st.ownActive('encourage') : [];
      if (pool.length > 0) {
        const e = this.pickOwn(pool);
        if (e === null) return;
        const ctx = new RitualCtx();
        ctx.type = 'own';
        ctx.entry = e;
        ctx.text = e.text;
        ctx.badge = '自己的话 · 鼓励';
        ctx.tag = '自己写的';
        ctx.source = `写于 ${fmtDate(e.createdAt)}`;
        this.startRitual(ctx);
      } else if (libOn) {
        this.drawLib(todayFlow, true);
      } else {
        this.openSheet('source');
      }
      return;
    }
    if (kind === 'wound') {
      const pool: OwnEntry[] = ownOn ? st.ownActive('wound') : [];
      if (pool.length === 0) {
        if (libOn) {
          this.drawLib(todayFlow, true);
        } else {
          this.openSheet('source');
        }
        return;
      }
      const e = this.pickOwn(pool);
      if (e === null) return;
      const ctx = new RitualCtx();
      ctx.type = 'own';
      ctx.entry = e;
      ctx.text = e.text;
      ctx.badge = '自己的话 · 一件旧事';
      ctx.tag = '自己写的';
      ctx.source = `写于 ${fmtDate(e.createdAt)}`;
      this.startRitual(ctx);
      return;
    }
    if (!libOn) {
      this.openSheet('source');
      return;
    }
    this.drawLib(todayFlow, false);
  }

  private drawLib(todayFlow: boolean, fromEncourage: boolean): void {
    const st = Store.get();
    if (!st.data.settings.drawLib) {
      this.openSheet('source');
      return;
    }
    const pool: LibEntry[] = st.libPool();
    if (pool.length > 0) {
      const q = this.pickLib(pool);
      if (q === null) return;
      const ctx = new RitualCtx();
      ctx.type = 'lib';
      ctx.text = q.text;
      ctx.source = q.source;
      ctx.badge = fromEncourage ? '句库 · 借一句' : '句库 · 收藏';
      ctx.tag = q.tag.length > 0 ? q.tag : '原文';
      ctx.origin = q.origin;
      ctx.todayFlow = todayFlow;
      this.startRitual(ctx);
      return;
    }
    const ownEnc: OwnEntry[] = st.ownActive('encourage');
    if (ownEnc.length > 0) {
      const e = this.pickOwn(ownEnc);
      if (e === null) return;
      const ctx = new RitualCtx();
      ctx.type = 'own';
      ctx.entry = e;
      ctx.text = e.text;
      ctx.badge = '自己的话 · 鼓励';
      ctx.tag = '自己写的';
      ctx.source = `写于 ${fmtDate(e.createdAt)}`;
      ctx.todayFlow = todayFlow;
      this.startRitual(ctx);
      return;
    }
    this.openSheet('source');
  }

  private skipDraw(): void {
    Store.get().markDrew();
    this.toast('好，今天只负责开心');
    this.load();
  }

  private backupNeed(): boolean {
    const st = Store.get();
    if (st.data.settings.backupRemindOff) return false;
    const total: number = st.data.own.length + st.data.lib.length;
    if (total < 3 || this.backupDismissed) return false;
    const last: number = st.data.meta.lastBackupAt;
    return last === 0 || Date.now() - last > 14 * 86400000;
  }

  private calm(id: string): void {
    const e = Store.get().data.own.find((x: OwnEntry) => x.id === id);
    if (e === null || e === undefined) return;
    e.revisitAt = 0;
    e.snoozeUntil = 0;
    e.notes.push(new NoteItem(Date.now(), '回访：已经平静。'));
    Store.get().saveSettings();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.load();
  }

  private back(id: string): void {
    Store.get().revive(id);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.load();
    this.toast('回到台前了，慢慢消化，不急');
  }

  private wait(id: string): void {
    const e = Store.get().data.own.find((x: OwnEntry) => x.id === id);
    if (e === null || e === undefined) return;
    const until: number = Date.now() + 30 * 86400000;
    e.revisitAt = until;
    e.snoozeUntil = until;
    Store.get().saveSettings();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.load();
    this.toast('好，30 天后再问');
  }

  @Builder
  Label(text: string) {
    Row({ space: 12 }) {
      Text(text)
        .fontSize(10.5)
        .letterSpacing(3)
        .fontColor(this.t().inkSoft)
        .fontFamily(FONT_SANS)
      Divider()
        .layoutWeight(1)
        .color(this.t().line)
    }
    .width('100%')
    .margin({ top: 26, bottom: 10 })
  }

  @Builder
  PrimaryButton(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .letterSpacing(1.4)
      .fontColor(this.t().bg)
      .fontFamily(FONT_SANS)
      .backgroundColor(this.t().ink)
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
      .margin({ right: 8, bottom: 8 })
      .onClick(action)
  }

  @Builder
  GhostButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .letterSpacing(1.2)
      .fontColor(this.t().ink)
      .fontFamily(FONT_SANS)
      .backgroundColor(this.t().card)
      .border({ width: 1, color: this.t().line })
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 20, right: 20, top: 11, bottom: 11 })
      .margin({ right: 8, bottom: 8 })
      .onClick(action)
  }

  @Builder
  QuietButton(label: string, action: () => void) {
    Text(label)
      .fontSize(12.5)
      .letterSpacing(1)
      .fontColor(this.t().inkSoft)
      .fontFamily(FONT_SANS)
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .margin({ right: 8, bottom: 8 })
      .onClick(action)
  }

  private moodGlow(kind: string): string {
    if (kind === 'good') return this.dark ? '#66967834' : '#bfffeeb4';
    return this.dark ? '#6646606e' : '#73a8bec6';
  }

  @Builder
  ChoiceButton(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(this.t().bg)
      .backgroundColor(this.t().ink)
      .borderRadius(this.t().radiusBtn)
      .height(44)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .onClick(action)
  }

  @Builder
  QuietTodayCard() {
    Column({ space: 8 }) {
      Text('今天，不必完成什么')
        .fontSize(14)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text('写一句、抽一句，都只是选项，不是任务。这里没有连续打卡，也不会催你。')
        .fontSize(12)
        .lineHeight(21)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Row({ space: 8 }) {
        this.GhostButton('去句库随便看看', () => {
          this.goLibrary();
        })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 12, bottom: 12 })
  }

  @Builder
  ChoiceCard() {
    Column({ space: 10 }) {
      Text('今天，想先做哪一件？')
        .fontSize(15)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text('写一句和抽一句，没有先后。想做哪个就点哪个。')
        .fontSize(12)
        .lineHeight(21)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Row({ space: 10 }) {
        this.ChoiceButton('写一句', () => {
          this.choice = 'write';
        })
        this.ChoiceButton('抽一句', () => {
          this.choice = 'draw';
          this.draw(this.primaryDrawKind(), true);
        })
      }
      .width('100%')
      .margin({ top: 4 })
      Text('不写也没关系，不抽也没关系。这里没有打卡，也没有必须完成的事。')
        .fontSize(11)
        .lineHeight(19)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 24, bottom: 12 })
  }

  @Builder
  MoodCard(kind: string, title: string, sub: string) {
    Row({ space: this.skin === 'plain' ? 8 : 10 }) {
      MoodIcon({
        kind: kind,
        plain: this.skin === 'plain',
        color: this.dark ? this.t().ink : this.t().inkSoft
      })
      Column({ space: 4 }) {
        Text(title)
          .fontSize(this.skin === 'plain' ? 15.5 : 16)
          .letterSpacing(this.skin === 'plain' ? 2 : 1)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
          .width('100%')
        Text(sub)
          .fontSize(10)
          .lineHeight(16)
          .letterSpacing(this.skin === 'plain' ? 0.2 : 1)
          .fontColor(this.t().inkSoft)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: this.skin === 'plain' ? 112 : 104 })
    .alignItems(VerticalAlign.Center)
    .padding(this.skin === 'plain' ? { left: 10, right: 8, top: 8, bottom: 8 } : { left: 12, right: 10, top: 10, bottom: 10 })
    .backgroundColor(this.skin === 'plain' ? this.t().card : this.t().card)
    .radialGradient(this.skin === 'plain' ? {
      center: ['50%', '50%'],
      radius: '100%',
      colors: [[this.t().card, 0.0], [this.t().card, 1.0]]
    } : {
      center: ['85%', '-10%'],
      radius: '140%',
      colors: [[this.moodGlow(kind), 0.0], [this.t().card, 0.62]]
    })
    .borderRadius(this.skin === 'plain' ? 10 : 22)
    .border({
      width: this.mood === kind ? (this.skin === 'plain' ? 1 : 1) : 1,
      color: this.mood === kind ? (this.skin === 'plain' ? this.t().seal : this.t().ink) : this.t().line
    })
    .shadow(this.skin === 'plain' ? { radius: 0, color: Color.Transparent } :
      { radius: 30, color: this.t().shadowColor, offsetY: 10 })
    .onClick(() => {
      this.setMood(kind);
    })
  }

  @Builder
  WriteCard() {
    Column({ space: 0 }) {
      if (this.writeKind() === 'encourage') {
        TextArea({ placeholder: '认真夸自己一句，哪怕很小', text: this.inputText })
          .height(96)
          .fontSize(16)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().ink)
          .placeholderColor(this.t().inkSoft)
          .backgroundColor(this.t().inputBg)
          .borderRadius(this.t().radiusInput)
          .border({ width: 1, color: this.t().line })
          .padding(13)
          .onChange((v: string) => {
            if (v !== this.inputText) {
              this.draftRestored = false;
            }
            this.inputText = v;
            this.queueDraft();
          })
        if (this.draftRestored) {
          Text('已恢复未保存的草稿')
            .fontSize(11)
            .fontColor(this.t().seal)
            .width('100%')
            .margin({ top: 6 })
        }
        Row({ space: 4 }) {
          Text('写不出来？换个视角')
            .fontSize(12.5)
            .fontColor(this.t().seal)
            .onClick(() => {
              this.showGuide = !this.showGuide;
            })
        }
        .width('100%')
        .margin({ top: 6 })
        if (this.showGuide) {
          Text('如果你的家人或朋友正处在低谷，你会说什么？')
            .fontSize(13)
            .lineHeight(24)
            .fontColor(this.t().ink)
            .width('100%')
            .padding({ left: 12, top: 6, bottom: 6 })
            .border({ width: { left: 2 }, color: this.t().seal })
            .margin({ top: 6 })
        }
        Row() {
          this.PrimaryButton(`收进${this.appName}`, () => {
            this.saveOwn();
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 14 })
      } else {
        TextArea({ placeholder: '不用完整，不用体面，写下来就好', text: this.inputText })
          .height(110)
          .fontSize(16)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().ink)
          .placeholderColor(this.t().inkSoft)
          .backgroundColor(this.t().inputBg)
          .borderRadius(this.t().radiusInput)
          .border({ width: 1, color: this.t().line })
          .padding(13)
          .onChange((v: string) => {
            if (v !== this.inputText) {
              this.draftRestored = false;
            }
            this.inputText = v;
            this.queueDraft();
          })
        if (this.draftRestored) {
          Text('已恢复未保存的草稿')
            .fontSize(11)
            .fontColor(this.t().seal)
            .width('100%')
            .margin({ top: 6 })
        }
        Text('不用着急，也不用写得好。这里没有别人，想到哪写到哪，我陪你慢慢写。')
          .fontSize(12.5)
          .lineHeight(23)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ top: 8 })
        Row() {
          this.PrimaryButton('放进树洞', () => {
            this.saveOwn();
          })
          this.QuietButton('不写，先抽一句', () => {
            this.draw(this.writeKind() === 'encourage' ? 'encourage' : 'lib', true);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 14 })
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .shadow(this.skin === 'plain' ? { radius: 0, color: Color.Transparent } :
      { radius: 30, color: this.t().shadowColor, offsetY: 10 })
  }

  @Builder
  RevisitCard(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(`你曾在 ${fmtMD(e.archAt)} 把这件事标记为「${this.catName(e.archCat)}」，约定这时轻轻问一次：`)
        .fontSize(12.5)
        .lineHeight(23)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Text(e.text)
        .fontSize(16.5)
        .lineHeight(32)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
        .margin({ top: 10, bottom: 8 })
      Text('现在想起它，感觉怎么样？')
        .fontSize(12.5)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ bottom: 12 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.GhostButton('已经平静', () => {
          this.calm(e.id);
        })
        this.GhostButton('还没好，回到台前', () => {
          this.back(e.id);
        })
        this.QuietButton('再等等', () => {
          this.wait(e.id);
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1.5, color: this.t().seal, style: BorderStyle.Dashed })
    .margin({ bottom: 14 })
  }

  private catName(cat: string): string {
    if (cat === 'resolved') return '已解决';
    if (cat === 'letgo') return '已放下';
    if (cat === 'silly') return '看起来很蠢';
    if (cat === 'tired') return '听腻了';
    return cat;
  }

  @Builder
  WriteLabel() {
    Row({ space: 12 }) {
      Text(this.writeKind() === 'encourage' ? '写一句鼓励自己的话' : '把让你难过的事写下来')
        .fontSize(10.5)
        .letterSpacing(3)
        .fontColor(this.t().inkSoft)
        .fontFamily(FONT_SANS)
      Divider()
        .layoutWeight(1)
        .color(this.t().line)
    }
    .width('100%')
    .margin({ top: 26, bottom: 10 })
  }

  @Builder
  DrawLabel() {
    Row({ space: 12 }) {
      Text(this.mood === 'bad' ? '现在，抽一句陪自己待一会儿' : '平顺的日子，适合消化一件旧事')
        .fontSize(10.5)
        .letterSpacing(3)
        .fontColor(this.t().inkSoft)
        .fontFamily(FONT_SANS)
      Divider()
        .layoutWeight(1)
        .color(this.t().line)
    }
    .width('100%')
    .margin({ top: 26, bottom: 10 })
  }

  @Builder
  SheetAction(label: string, primary: boolean, action: () => void) {
    Text(label)
      .width('100%')
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontFamily(FONT_SERIF)
      .fontColor(primary ? this.t().bg : this.t().ink)
      .backgroundColor(primary ? this.t().ink : this.t().card)
      .border({ width: 1, color: primary ? Color.Transparent : this.t().line })
      .borderRadius(this.t().radiusBtn)
      .padding({ top: 13, bottom: 13 })
      .onClick(action)
  }

  @Builder
  TodaySheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.sheetOpen = false;
        })
      Column({ space: 10 }) {
      Text(this.sheetMode === 'write' ? '再写一句' : (this.sheetMode === 'source' ? '还没有可以抽的句子' : '再抽一句'))
        .fontSize(18)
        .letterSpacing(3)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      if (this.sheetMode === 'source') {
        Text('先写一句自己的话，或去材料库/句库加入一句。')
          .fontSize(12)
          .lineHeight(22)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ bottom: 4 })
        this.SheetAction('现在写一句', true, () => {
          this.startMoreWrite('encourage');
        })
        this.SheetAction('去材料库 / 句库加入', false, () => {
          this.sheetOpen = false;
          this.goLibrary();
        })
      } else if (this.sheetMode === 'write') {
        Text('两种都可以写，不分今天的心情。')
          .fontSize(12)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ bottom: 4 })
        this.SheetAction('写一句鼓励自己的话', false, () => {
          this.startMoreWrite('encourage');
        })
        this.SheetAction('写一件放在心里的事', false, () => {
          this.startMoreWrite('wound');
        })
      } else {
        if (this.mood === 'bad') {
          this.SheetAction('抽一句鼓励（自己写的）', true, () => {
            this.startMoreDraw('encourage');
          })
          this.SheetAction('从收藏/材料里借一句', false, () => {
            this.startMoreDraw('lib');
          })
        } else {
          this.SheetAction('抽一件旧事来消化', true, () => {
            this.startMoreDraw('wound');
          })
          this.SheetAction('从句库抽一句', false, () => {
            this.startMoreDraw('lib');
          })
        }
      }
      this.SheetAction('取消', false, () => {
        this.sheetOpen = false;
      })
    }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 24 })
      .backgroundColor(this.t().bg)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .margin({ left: 10, right: 10, bottom: 10 })
      .constraintSize({ maxHeight: '86%' })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .opacity(this.coverOpacity)
  }

  build() {
    Scroll() {
      Column() {
        if (this.revisit.length > 0) {
          this.Label('轻轻的回访')
        }
        ForEach(this.revisit, (e: OwnEntry) => {
          this.RevisitCard(e)
        }, (e: OwnEntry) => e.id)

        if (!this.seen) {
          Column({ space: 0 }) {
            Text('开始我们的第一次树洞吧')
              .fontSize(20)
              .letterSpacing(4)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
              .margin({ bottom: 14 })
            Text('每天可以写一句：心情好时写一句鼓励自己的，心情糟时写下那件让你难过的事。\n也可以抽一句自己的话——低谷时抽鼓励，平顺时抽旧事来消化。写和抽，没有先后。\n没有句子时，可以自己写，或从材料库加入。')
              .fontSize(12.5)
              .lineHeight(28)
              .fontColor(this.t().inkSoft)
              .width('100%')
            Row() {
              this.PrimaryButton('好，开始', () => {
                Store.get().data.meta.seen = true;
                Store.get().saveSettings();
                this.load();
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 18 })
          }
          .width('100%')
          .padding({ left: 22, right: 22, top: 34, bottom: 30 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 14 })
        }

        if (this.needSource && this.seen) {
          Column({ space: 10 }) {
            Text('第一句，可以从这里开始')
              .fontSize(17)
              .letterSpacing(2)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
              .width('100%')
            Text('写一句自己的话；也可以从材料库或句库加入。')
              .fontSize(12.5)
              .lineHeight(23)
              .fontColor(this.t().inkSoft)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.GhostButton('写一句', () => {
                this.openSheet('write');
              })
              this.GhostButton('去材料库 / 句库', () => {
                this.goLibrary();
              })
              this.GhostButton('去设置', () => {
                this.goSettings();
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 12 })
        }

        if (this.showGreeting && this.nickname.length > 0) {
          Text(`你好，${this.nickname}`)
            .fontSize(17)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().inkStrong)
            .width('100%')
            .margin({ top: 2, bottom: 2 })
        }

        this.Label('今天，心里是什么天气')

        Row({ space: 14 }) {
          this.MoodCard('good', '今天还不错', '存一句鼓励 · 可处理一件旧事')
          this.MoodCard('bad', '今天有点糟', '树洞写下来 · 抽一句陪着你')
        }
        .width('100%')

        if (this.mood.length > 0 && !this.wrote && !this.drew && this.choice.length === 0) {
          this.ChoiceCard()
          this.QuietTodayCard()
        }

        if (this.mood.length > 0 && !this.wrote && (this.choice === 'write' || this.drew)) {
          this.WriteLabel()
          this.WriteCard()
        }

        if (this.mood.length > 0 && !this.drew && (this.wrote || this.choice === 'draw')) {
          this.DrawLabel()
          Column({ space: 0 }) {
            if (this.mood === 'bad') {
              Text(!Store.get().data.settings.drawOwn
                ? '自己的话暂时不参与抽签。可以从句库取一句。'
                : (this.encCount > 0
                  ? `从你写过的 ${this.encCount} 句鼓励里，抽一句还给今天的你。`
                  : '你的鼓励池还是空的——这次先从句库借一句给你。等你写下第一句自己的鼓励，它就会回到抽签里。'))
                .fontSize(12.5)
                .lineHeight(24)
                .fontColor(this.t().inkSoft)
                .width('100%')
                .margin({ bottom: 12 })
              Flex({ wrap: FlexWrap.Wrap }) {
                if (Store.get().data.settings.drawOwn) {
                  this.PrimaryButton('抽签', () => {
                    this.draw('encourage');
                  })
                } else if (Store.get().data.settings.drawLib) {
                  this.PrimaryButton('从句库抽一句', () => {
                    this.draw('lib', true);
                  })
                }
                this.QuietButton('再写一句', () => {
                  this.openSheet('write');
                })
              }
              .width('100%')
            } else {
              if (this.woundCount > 0) {
                Text(Store.get().data.settings.drawOwn
                  ? `树洞里有 ${this.woundCount} 件还没消化的事。要不要抽一件，趁有能量时看看它？`
                  : `树洞里有 ${this.woundCount} 件还没消化的事，但自己的话暂时不参与抽签。可以去「设置」打开，或从句库取一句。`)
                  .fontSize(12.5)
                  .lineHeight(24)
                  .fontColor(this.t().inkSoft)
                  .width('100%')
                  .margin({ bottom: 12 })
                Flex({ wrap: FlexWrap.Wrap }) {
                  if (Store.get().data.settings.drawOwn) {
                    this.PrimaryButton('抽一件旧事', () => {
                      this.draw('wound');
                    })
                  } else if (Store.get().data.settings.drawLib) {
                    this.PrimaryButton('从句库抽一句', () => {
                      this.draw('lib', true);
                    })
                  }
                  this.QuietButton('看了标题就有点累，今天先不处理', () => {
                    this.skipDraw();
                  })
                  this.QuietButton('再写一句', () => {
                    this.openSheet('write');
                  })
                }
                .width('100%')
              } else {
                Text(Store.get().data.settings.drawLib
                  ? '树洞是空的，没有积压的旧事——这本身就是好事。也可以从句库抽一句，给今天收个尾。'
                  : '树洞是空的，没有积压的旧事——这本身就是好事。句库暂时不参与抽签，可以再写一句。')
                  .fontSize(12.5)
                  .lineHeight(24)
                  .fontColor(this.t().inkSoft)
                  .width('100%')
                  .margin({ bottom: 12 })
                Flex({ wrap: FlexWrap.Wrap }) {
                  if (Store.get().data.settings.drawLib) {
                    this.GhostButton('从句库抽一句', () => {
                      this.draw('lib', true);
                    })
                  }
                  this.QuietButton('再写一句', () => {
                    this.openSheet('write');
                  })
                }
                .width('100%')
              }
            }
          }
          .width('100%')
          .padding(20)
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .shadow(this.skin === 'plain' ? { radius: 0, color: Color.Transparent } :
            { radius: 30, color: this.t().shadowColor, offsetY: 10 })
        }

        if (this.mood.length > 0 && this.wrote && this.drew) {
          Column({ space: 0 }) {
            Text('今天的一句话，已经收好了')
              .fontSize(15.5)
              .letterSpacing(3)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
            Row({ space: 10 }) {
              this.GhostButton('再抽一句', () => {
                this.openSheet('draw');
              })
              this.GhostButton('再写一句', () => {
                this.openSheet('write');
              })
            }
            .margin({ top: 16 })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 30, bottom: 30 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 4 })
        }

        if (this.backupNeed()) {
          Column({ space: 0 }) {
            Text(Store.get().data.meta.lastBackupAt > 0
              ? '距离上次备份已超过 14 天——这里的一切只存在这台设备上，清理数据就会消失。花一分钟做个密语备份吧。'
              : '你还没做过备份——这里的一切只存在这台设备上，清理数据就会全部消失。花一分钟做个密语备份吧。')
              .fontSize(12)
              .lineHeight(22)
              .fontColor(this.t().inkSoft)
              .width('100%')
            Row({ space: 4 }) {
              this.GhostButton('去备份', () => {
                this.goSettings();
              })
              this.QuietButton('今天别再提醒', () => {
                this.backupDismissed = true;
                Store.get().data.day.backupDismissed = true;
                Store.get().saveKv();
              })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line, style: BorderStyle.Dashed })
          .margin({ top: 10 })
        }

        Blank()

      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 4, bottom: this.padBottom() })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .bindContentCover($$this.sheetOpen, this.TodaySheet(), { modalTransition: ModalTransition.NONE, onAppear: () => {
      this.coverOpacity = 0;
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 220, curve: curves.springCurve(0.6, 1, 1, 1) }, () => {
          this.coverOpacity = 1;
        });
      }, 16);
    }, onDisappear: () => {
      this.coverOpacity = 0;
    } })
  }
}








