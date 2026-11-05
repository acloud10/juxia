// 句栖 · 回忆（时间线 / 分类 / 回访）
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Store } from '../data/Store';
import { OwnEntry, NoteItem, fmtDate, fmtMD, revisitAtFromDays } from '../model/Types';
import { ReminderService } from '../services/ReminderService';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { ArrayDataSource } from '../utils/DataSource';
import { UiState } from '../state/UiState';

class TlNote {
  id: string = '';
  at: number = 0;
  text: string = '';
  note: string = '';
  cat: string = '';
}

class MonthStat {
  key: string = '';
  label: string = '';
  resolved: number = 0;
  letgo: number = 0;
  silly: number = 0;
  tired: number = 0;
  total: number = 0;
}

@ComponentV2
export struct ArchivePage {
  @Local ui: UiState = UiState.get();
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  @Local tab: string = 'timeline';
  @Local q: string = '';
  @Local showRevisit: boolean = false;
  @Local panel: string = '';
  @Local targetId: string = '';
  @Local noteInput: string = '';
  @Local sheetOpen: boolean = false;
  @Local coverOpacity: number = 0;
  @Local items: OwnEntry[] = [];
  private tlDs: ArrayDataSource<TlNote> = new ArrayDataSource<TlNote>();
  @Local revisitDaysValue: number = 7;
  @Local revisitDaysText: string = '7';

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('ui.dataVersion')
  onData(monitor: IMonitor): void {
    this.reload();
  }

  @Monitor('sheetOpen')
  syncSheet(monitor: IMonitor): void {
    this.ui.sheetOpenArchive = this.sheetOpen;
  }

  @Monitor('ui.backRev')
  onBackReq(monitor: IMonitor): void {
    if (this.sheetOpen) {
      this.sheetOpen = false;
    }
  }

  private reload(): void {
    this.items = Store.get().archived();
    this.tlDs.setData(this.timelineNotes());
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private archived(): OwnEntry[] {
    return this.items;
  }

  private catName(cat: string): string {
    if (cat === 'resolved') return '已解决';
    if (cat === 'letgo') return '已放下';
    if (cat === 'silly') return '看起来很蠢';
    if (cat === 'tired') return '听腻了';
    return cat;
  }

  private match(e: OwnEntry): boolean {
    const kw: string = this.q.trim().toLowerCase();
    if (kw.length === 0) return true;
    if (e.text.toLowerCase().includes(kw)) return true;
    if (e.archNote.toLowerCase().includes(kw)) return true;
    return e.notes.some((n: NoteItem) => n.text.toLowerCase().includes(kw));
  }

  private categoryList(): OwnEntry[] {
    return this.archived().filter((e: OwnEntry) => e.archCat === this.tab && this.match(e));
  }

  private revisitList(): OwnEntry[] {
    const list: OwnEntry[] = this.archived().filter((e: OwnEntry) => e.revisitAt > 0);
    list.sort((a: OwnEntry, b: OwnEntry) => a.revisitAt - b.revisitAt);
    return list;
  }

  private notesOf(e: OwnEntry): string[] {
    const out: string[] = [];
    e.notes.forEach((n: NoteItem) => {
      out.push(n.text);
    });
    return out;
  }

  private timelineNotes(): TlNote[] {
    const out: TlNote[] = [];
    this.archived().forEach((e: OwnEntry) => {
      if (!this.match(e)) return;
      const n0 = new TlNote();
      n0.id = e.id + '-arch';
      n0.at = e.archAt;
      n0.text = e.text;
      n0.note = e.archNote;
      n0.cat = e.archCat;
      out.push(n0);
      e.notes.forEach((n: NoteItem, idx: number) => {
        const nn = new TlNote();
        nn.id = e.id + '-n' + idx;
        nn.at = n.at;
        nn.text = e.text;
        nn.note = n.text;
        nn.cat = e.archCat;
        out.push(nn);
      });
    });
    out.sort((a: TlNote, b: TlNote) => b.at - a.at);
    return out.slice(0, 60);
  }

  private months(): MonthStat[] {
    const items: OwnEntry[] = this.archived();
    const map: Map<string, MonthStat> = new Map();
    items.forEach((e: OwnEntry) => {
      const d = new Date(e.archAt);
      const key: string = `${d.getFullYear()}-${d.getMonth() + 1}`;
      if (!map.has(key)) {
        const m = new MonthStat();
        m.key = key;
        m.label = `${d.getMonth() + 1}月`;
        map.set(key, m);
      }
      const m = map.get(key) as MonthStat;
      if (e.archCat === 'resolved') m.resolved++;
      else if (e.archCat === 'letgo') m.letgo++;
      else if (e.archCat === 'silly') m.silly++;
      else if (e.archCat === 'tired') m.tired++;
      m.total++;
    });
    const keys: string[] = [];
    map.forEach((v: MonthStat, k: string) => {
      keys.push(k);
    });
    keys.sort((a: string, b: string) => {
      const pa: string[] = a.split('-');
      const pb: string[] = b.split('-');
      return (Number(pa[0]) * 12 + Number(pa[1])) - (Number(pb[0]) * 12 + Number(pb[1]));
    });
    const out: MonthStat[] = [];
    keys.slice(Math.max(0, keys.length - 6)).forEach((k: string) => {
      out.push(map.get(k) as MonthStat);
    });
    return out;
  }

  private maxMonth(): number {
    let max: number = 1;
    this.months().forEach((m: MonthStat) => {
      if (m.total > max) max = m.total;
    });
    return max;
  }

  private barH(count: number, max: number): number {
    if (count === 0) return 0;
    return Math.max(2, Math.round(count / max * 56));
  }

  private openNote(e: OwnEntry): void {
    this.panel = 'note';
    this.targetId = e.id;
    this.noteInput = '';
    this.sheetOpen = true;
  }

  private saveNote(): void {
    const text: string = this.noteInput.trim();
    if (text.length === 0) {
      this.panel = '';
      this.targetId = '';
      this.sheetOpen = false;
      return;
    }
    Store.get().addNote(this.targetId, text);
    this.panel = '';
    this.targetId = '';
    this.sheetOpen = false;
    this.reload();
    this.toast('已记下');
  }

  private openRevisit(e: OwnEntry): void {
    this.panel = 'revisit';
    this.targetId = e.id;
    let days: number = Store.get().data.settings.revisitDays;
    if (e.revisitAt > Date.now()) {
      days = Math.max(1, Math.ceil((e.revisitAt - Date.now()) / 86400000));
    }
    this.revisitDaysValue = days;
    this.revisitDaysText = `${days}`;
    this.sheetOpen = true;
  }

  private askEnableNotify(ctx: common.UIAbilityContext): void {
    try {
    this.getUIContext().showAlertDialog({
      title: '开启通知',
      message: '系统通知没有开启，回访提醒无法排进去。开启后，句栖才能在约定时间轻轻问你一次。',
      primaryButton: {
        value: '去开启',
        action: () => {
          ReminderService.enableNotifications(ctx).then((ok: boolean) => {
            if (ok) {
              ReminderService.rescheduleAll(ctx);
              this.toast('通知已开启，提醒会重新排入');
            } else {
              this.toast('仍未开启，可到系统设置里允许句栖通知');
            }
          });
        }
      },
      secondaryButton: {
        value: '稍后',
        action: () => {
          this.toast('到期打开句栖，仍会看到回访卡');
        }
      }
    });
    } catch (e) {
      console.error('juxia alert fail', String(e));
    }
  }

  private saveRevisitTime(): void {
    const days: number = Math.max(1, Math.min(3650, this.revisitDaysValue));
    const at: number = revisitAtFromDays(days, Store.get().data.settings.revisitHour, Store.get().data.settings.revisitMinute);
    Store.get().setRevisitAt(this.targetId, at);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx).then((ok: boolean) => {
      if (!ok) {
        this.askEnableNotify(ctx);
      }
    });
    this.sheetOpen = false;
    this.reload();
    this.toast(`${days} 天后轻轻问你一次`);
  }

  private soon(e: OwnEntry): void {
    const now: number = Date.now();
    const target = Store.get().data.own.find((x: OwnEntry) => x.id === e.id);
    if (!target) return;
    target.revisitAt = now;
    target.snoozeUntil = 0;
    Store.get().saveSettings();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.reload();
    this.toast('已排进今天的回访');
  }

  private cancelRevisit(e: OwnEntry): void {
    Store.get().clearRevisit(e.id);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.reload();
    this.toast('已取消这次回访');
  }

  private revive(e: OwnEntry): void {
    Store.get().revive(e.id);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.reload();
    this.toast('回来了，它重新参与抽签');
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
    .margin({ top: 24, bottom: 10 })
  }

  @Builder
  Chip(label: string, value: string, action: () => void) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1)
      .fontColor(this.tab === value ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.tab === value ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.tab === value ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .margin({ right: 6, bottom: 6 })
      .onClick(action)
  }

  @Builder
  QuietButton(label: string, action: () => void) {
    Text(label)
      .fontSize(12.5)
      .fontColor(this.t().inkSoft)
      .fontFamily(FONT_SANS)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .margin({ right: 4 })
      .onClick(action)
  }

  @Builder
  SolidButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(this.t().bg)
      .fontFamily(FONT_SANS)
      .backgroundColor(this.t().ink)
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .margin({ right: 8 })
      .onClick(action)
  }

  @Builder
  NoteLine(text: string) {
    Text(text)
      .fontSize(13)
      .lineHeight(24)
      .fontColor(this.t().ink)
      .width('100%')
      .padding({ left: 12, top: 3, bottom: 3 })
      .border({ width: { left: 2 }, color: this.t().seal })
      .margin({ top: 6 })
  }

  @Builder
  NotePanel() {
    Column({ space: 0 }) {
      TextArea({ placeholder: '此刻想起它，是什么感觉？', text: this.noteInput })
        .height(80)
        .fontSize(14)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .padding(12)
        .onChange((v: string) => {
          this.noteInput = v;
        })
      Row() {
        this.SolidButton('记下', () => {
          this.saveNote();
        })
        this.QuietButton('取消', () => {
          this.panel = '';
          this.targetId = '';
          this.sheetOpen = false;
        })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 10 })
  }

  @Builder
  RevisitCard(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontSize(15.5)
        .lineHeight(31)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Text(e.revisitAt <= Date.now() ? '已到期' : `还有 ${Math.ceil((e.revisitAt - Date.now()) / 86400000)} 天`)
          .fontSize(10.5)
          .fontColor(e.revisitAt <= Date.now() ? this.t().sealInk : this.t().inkSoft)
          .backgroundColor(e.revisitAt <= Date.now() ? this.t().seal : this.t().card)
          .border({ width: 1, color: e.revisitAt <= Date.now() ? Color.Transparent : this.t().line })
          .borderRadius(999)
          .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        Text(fmtMD(e.revisitAt))
          .fontSize(11)
          .fontColor(this.t().inkSoft)
        this.QuietButton('提前到今天', () => {
          this.soon(e);
        })
        this.QuietButton('取消回访', () => {
          this.cancelRevisit(e);
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  @Builder
  ArchiveCard(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontSize(16.5)
        .lineHeight(33)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text(`${fmtDate(e.archAt)} 标记为「${this.catName(e.archCat)}」`)
        .fontSize(10.5)
        .letterSpacing(1)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ top: 4 })
      if (e.archNote.length > 0) {
        this.NoteLine(`${fmtMD(e.archAt)}  ${e.archNote}`)
      }
      ForEach(this.notesOf(e), (n: string) => {
        this.NoteLine(n)
      }, (n: string) => n)
      if (e.kind === 'wound' && (e.archCat === 'resolved' || e.archCat === 'letgo')) {
        Text(e.revisitAt > 0
          ? `回访：${fmtMD(e.revisitAt)} 轻轻问一次${e.snoozeUntil > Date.now() ? `（再等等到 ${fmtMD(e.snoozeUntil)}）` : ''}`
          : '未设回访')
          .fontSize(10.5)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ top: 6 })
      }
      Row({ space: 2 }) {
        this.QuietButton('加备注', () => {
          this.openNote(e);
        })
        if (e.kind === 'wound') {
          this.QuietButton(e.revisitAt > 0 ? '改回访天数' : '设置回访天数', () => {
            this.openRevisit(e);
          })
        }
        this.QuietButton('复活回台前', () => {
          this.revive(e);
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ bottom: 12 })
  }

  @Builder
  LegendItem(color: string, label: string) {
    Row({ space: 5 }) {
      Column().width(8).height(8).borderRadius(3).backgroundColor(color)
      Text(label).fontSize(10.5).fontColor(this.t().inkSoft)
    }
    .margin({ right: 14, bottom: 4 })
  }

  @Builder
  Timeline() {
    Column({ space: 0 }) {
      Text('每月收进回忆区的句子数，按类别堆叠；下面的时间线是这些句子留下的备注——你的第二本日记。')
        .fontSize(12.5)
        .lineHeight(23)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Row({ space: 10 }) {
        ForEach(this.months(), (m: MonthStat) => {
          Column({ space: 0 }) {
            Text(`${m.total}`)
              .fontSize(9)
              .fontColor(this.t().inkSoft)
            Column({ space: 0 }) {
              if (m.tired > 0) {
                Column().width('100%').height(this.barH(m.tired, this.maxMonth())).backgroundColor('#b8434a')
              }
              if (m.silly > 0) {
                Column().width('100%').height(this.barH(m.silly, this.maxMonth())).backgroundColor('#c9a86a')
              }
              if (m.letgo > 0) {
                Column().width('100%').height(this.barH(m.letgo, this.maxMonth())).backgroundColor('#8fa3b8')
              }
              if (m.resolved > 0) {
                Column().width('100%').height(this.barH(m.resolved, this.maxMonth())).backgroundColor('#7a9b76')
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            .backgroundColor(this.t().lineSoft)
            .borderRadius({ topLeft: 4, topRight: 4 })
            Text(m.label)
              .fontSize(9)
              .fontColor(this.t().inkSoft)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
        }, (m: MonthStat) => m.key)
      }
      .width('100%')
      .height(100)
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 12 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.LegendItem('#7a9b76', '已解决')
        this.LegendItem('#8fa3b8', '已放下')
        this.LegendItem('#c9a86a', '看起来很蠢')
        this.LegendItem('#b8434a', '听腻了')
      }
      .width('100%')
      .margin({ top: 8 })
      Divider().color(this.t().line).margin({ top: 10, bottom: 6 })

      LazyForEach(this.tlDs, (n: TlNote) => {
        Column({ space: 0 }) {
          Text(`${fmtDate(n.at)} · ${this.catName(n.cat)}`)
            .fontSize(10)
            .letterSpacing(1.5)
            .fontColor(this.t().inkSoft)
            .width('100%')
          Text(n.text)
            .fontSize(15)
            .lineHeight(30)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().inkStrong)
            .width('100%')
            .margin({ top: 2 })
          if (n.note.length > 0) {
            Text(n.note)
              .fontSize(13)
              .lineHeight(24)
              .fontColor(this.t().ink)
              .width('100%')
              .margin({ top: 2 })
          }
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .border({ width: { top: 1 }, color: this.t().lineSoft })
      }, (n: TlNote) => n.id)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }

  @Builder
  RevisitPanel() {
    Column({ space: 8 }) {
      Text('多少天后再问一次')
        .fontSize(16)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text(`默认 ${Store.get().data.settings.revisitDays} 天，可单独改。从今天起算，天数会随着时间减少，到点由系统提醒你；通知排不进去时，到期打开句栖也会看到回访卡。`)
        .fontSize(11.5)
        .lineHeight(20)
        .fontColor(this.t().inkSoft)
        .width('100%')
      TextInput({ text: this.revisitDaysText, placeholder: '输入天数' })
        .type(InputType.Number)
        .height(42)
        .fontSize(14)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.revisitDaysText = v;
          const n: number = Number(v);
          if (n >= 1 && n <= 3650) this.revisitDaysValue = n;
        })
      Row({ space: 8 }) {
        this.SolidButton('保存天数', () => {
          this.saveRevisitTime();
        })
        this.QuietButton('取消', () => {
          this.sheetOpen = false;
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
  }

  @Builder
  SheetContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.sheetOpen = false;
          this.panel = '';
          this.targetId = '';
        })
      Column() {
        if (this.panel === 'note') {
          this.NotePanel()
        }
        if (this.panel === 'revisit') {
          this.RevisitPanel()
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 20 })
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
        this.Label('回忆区 · 分门别类，不再被抽到')

        Row() {
          Text('回访一览')
            .fontSize(14)
            .letterSpacing(1.5)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().inkStrong)
          Text(`${this.revisitList().length} 件`)
            .fontSize(10)
            .fontColor(this.t().inkSoft)
            .backgroundColor(this.t().card)
            .border({ width: 1, color: this.t().line })
            .borderRadius(999)
            .padding({ left: 9, right: 9, top: 2, bottom: 2 })
            .margin({ left: 8 })
          Blank()
          Text(this.showRevisit ? '−' : '＋')
            .fontSize(16)
            .fontColor(this.t().seal)
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 14 })
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })
        .onClick(() => {
          this.showRevisit = !this.showRevisit;
        })

        if (this.showRevisit) {
          Column({ space: 0 }) {
            if (this.revisitList().length === 0) {
              Text('还没有约定回访。把一件旧事标记为「已解决 / 已放下」时，可以约一个时间。')
                .fontSize(12.5)
                .lineHeight(24)
                .fontColor(this.t().inkSoft)
                .width('100%')
            } else {
              ForEach(this.revisitList(), (e: OwnEntry) => {
                this.RevisitCard(e)
              }, (e: OwnEntry) => `${e.id}-${e.revisitAt}`)
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 6, bottom: 8 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 10 })
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          this.Chip('时间线', 'timeline', () => {
            this.tab = 'timeline';
          })
          this.Chip('已解决', 'resolved', () => {
            this.tab = 'resolved';
          })
          this.Chip('已放下', 'letgo', () => {
            this.tab = 'letgo';
          })
          this.Chip('看起来很蠢', 'silly', () => {
            this.tab = 'silly';
          })
          this.Chip('听腻了', 'tired', () => {
            this.tab = 'tired';
          })
        }
        .width('100%')
        .margin({ top: 16, bottom: 6 })

        TextInput({ text: this.q, placeholder: '搜索：句子或备注' })
          .height(42)
          .fontSize(14)
          .fontColor(this.t().ink)
          .placeholderColor(this.t().inkSoft)
          .backgroundColor(this.t().inputBg)
          .borderRadius(this.t().radiusInput)
          .border({ width: 1, color: this.t().line })
          .onChange((v: string) => {
            this.q = v;
          })
          .margin({ bottom: 12 })

        if (this.tab === 'timeline') {
          this.Timeline()
        } else {
          if (this.categoryList().length === 0) {
            Column({ space: 6 }) {
              Text(this.q.length > 0 ? '没有找到' : '这一类还没有句子')
                .fontSize(14)
                .fontFamily(FONT_SERIF)
                .fontColor(this.t().inkStrong)
              Text(this.q.length > 0 ? '换个词试试。' : '空着也挺好。')
                .fontSize(12)
                .lineHeight(22)
                .fontColor(this.t().inkSoft)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ top: 40, bottom: 40 })
              .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
              .borderRadius(this.t().radiusCard)
              .border({ width: 1, color: this.t().line })
          } else {
            ForEach(this.categoryList(), (e: OwnEntry) => {
              this.ArchiveCard(e)
            }, (e: OwnEntry) => `${e.id}-${e.archAt}-${e.notes.length}-${e.revisitAt}`)
          }
        }

        Blank()

        Text('回忆区只保留自己的话；句库条目用排除名单管理')
          .fontSize(11.5)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 22 })
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 4, bottom: 140 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .bindContentCover($$this.sheetOpen, this.SheetContent(), { modalTransition: ModalTransition.NONE, onAppear: () => {
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








