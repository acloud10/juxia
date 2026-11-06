// 句栖 · 我的（鼓励池 / 旧事簿）
import { curves } from '@kit.ArkUI';
import { window, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Store } from '../data/Store';
import { OwnEntry, LibEntry, NoteItem, fmtDate } from '../model/Types';
import { ReminderService } from '../services/ReminderService';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { ArrayDataSource } from '../utils/DataSource';
import { UiState } from '../state/UiState';

class ReflectGroup {
  key: string = '';
  label: string = '';
  items: OwnEntry[] = [];
}

class ReflectYear {
  key: string = '';
  label: string = '';
  total: number = 0;
  months: ReflectGroup[] = [];
}

@ComponentV2
export struct MinePage {
  @Local ui: UiState = UiState.get();
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  @Event goToday: () => void = () => {};
  @Event goLibrary: () => void = () => {};
  @Local enc: OwnEntry[] = [];
  private encDs: ArrayDataSource<OwnEntry> = new ArrayDataSource<OwnEntry>();
  private wndDs: ArrayDataSource<OwnEntry> = new ArrayDataSource<OwnEntry>();
  @Local wnd: OwnEntry[] = [];
  @Local q: string = '';
  @Local panel: string = '';
  @Local targetId: string = '';
  @Local noteInput: string = '';
  @Local archCat: string = 'silly';
  @Local archNote: string = '';
  @Local withRevisit: boolean = true;
  @Local bindQuery: string = '';
  @Local showEnc: boolean = false;
  @Local showWnd: boolean = false;
  @Local showRef: boolean = true;
  @Local refSectionOpen: boolean = true;
  @Local refs: OwnEntry[] = [];
  @Local refQ: string = '';
  @Local refLimit: number = 30;
  @Local refOpenId: string = '';
  @Local refOpenMonths: string[] = [];
  @Local refOpenYears: string[] = [];
  @Local refNotesAll: boolean = false;
  private refMonthInit: boolean = false;
  @Local refText: string = '';
  @Local refEditText: string = '';
  @Local refNoteInput: string = '';
  @Local bindRev: number = 0;
  @Local sheetOpen: boolean = false;
  @Local coverOpacity: number = 0;
  @Local kbHeight: number = 0;
  private win: window.Window | null = null;

  aboutToAppear(): void {
    this.reload();
    this.bindKeyboard();
  }


  aboutToDisappear(): void {
    if (this.win !== null) {
      try {
        this.win.off('keyboardHeightChange');
      } catch (e) {
      }
      this.win = null;
    }
  }

  private async bindKeyboard(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.win = await window.getLastWindow(ctx);
      this.win.on('keyboardHeightChange', (h: number) => {
        this.kbHeight = h / display.getDefaultDisplaySync().densityPixels;
      });
    } catch (e) {
      console.error('juxia keyboard bind fail', String(e));
    }
  }

  @Monitor('ui.dataVersion')
  onData(monitor: IMonitor): void {
    this.reload();
  }

  @Monitor('sheetOpen')
  syncSheet(monitor: IMonitor): void {
    this.ui.sheetOpenMine = this.sheetOpen;
  }

  @Monitor('ui.backRev')
  onBackReq(monitor: IMonitor): void {
    if (this.sheetOpen) {
      this.sheetOpen = false;
    }
  }

  @Monitor('ui.mineOpenRev')
  onOpenRequest(monitor: IMonitor): void {
    const id: string = this.ui.mineOpenId;
    const panel: string = this.ui.mineOpenPanel;
    if (id.length === 0 || panel.length === 0) return;
    const e = Store.get().data.own.find((x: OwnEntry) => x.id === id);
    this.ui.mineOpenId = '';
    this.ui.mineOpenPanel = '';
    if (e === undefined) return;
    this.targetId = id;
    this.panel = panel;
    if (panel === 'bind') {
      this.bindQuery = '';
    } else if (panel === 'archive') {
      this.archCat = e.kind === 'wound' ? 'resolved' : 'silly';
      this.archNote = '';
      this.withRevisit = true;
    }
    this.sheetOpen = true;
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private reload(): void {
    const st = Store.get();
    this.enc = st.ownActive('encourage');
    this.wnd = st.ownActive('wound');
    this.refs = st.reflects();
    this.showRef = st.data.settings.showReflect;
    if (!this.refMonthInit) {
      const now: string = this.monthKeyOf(Date.now());
      this.refOpenYears = [now.slice(0, 4)];
      this.refOpenMonths = [now];
      this.refMonthInit = true;
    }
    this.encDs.setData(this.filtered('encourage'));
    this.wndDs.setData(this.filtered('wound'));
  }

  private filteredReflects(): OwnEntry[] {
    const kw: string = this.refQ.trim().toLowerCase();
    if (kw.length === 0) return this.refs;
    return this.refs.filter((e: OwnEntry) => {
      if (e.text.toLowerCase().includes(kw)) return true;
      return e.notes.some((n: NoteItem) => n.text.toLowerCase().includes(kw));
    });
  }

  private refShown(): OwnEntry[] {
    return this.filteredReflects().slice(0, this.refLimit);
  }

  // 省身分组的键：固定 YYYY-MM，与展示用的中文日期解耦
  private monthKeyOf(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
  }

  private refYearGroups(): ReflectYear[] {
    const out: ReflectYear[] = [];
    this.refShown().forEach((e: OwnEntry) => {
      const key: string = this.monthKeyOf(e.createdAt);
      const yearKey: string = key.slice(0, 4);
      let yi: number = out.findIndex((y: ReflectYear) => y.key === yearKey);
      if (yi < 0) {
        const y: ReflectYear = new ReflectYear();
        y.key = yearKey;
        y.label = `${yearKey} 年`;
        out.push(y);
        yi = out.length - 1;
      }
      const y: ReflectYear = out[yi];
      let mi: number = y.months.findIndex((m: ReflectGroup) => m.key === key);
      if (mi < 0) {
        const m: ReflectGroup = new ReflectGroup();
        m.key = key;
        m.label = `${Number(key.slice(5, 7))} 月`;
        y.months.push(m);
        mi = y.months.length - 1;
      }
      y.months[mi].items.push(e);
      y.total++;
    });
    return out;
  }

  private isYearOpen(key: string): boolean {
    if (this.refQ.trim().length > 0) return true;
    return this.refOpenYears.includes(key);
  }

  private toggleYear(key: string): void {
    if (this.refOpenYears.includes(key)) {
      this.refOpenYears = this.refOpenYears.filter((x: string) => x !== key);
    } else {
      this.refOpenYears = this.refOpenYears.concat([key]);
    }
  }

  private isMonthOpen(key: string): boolean {
    if (this.refQ.trim().length > 0) return true;
    return this.refOpenMonths.includes(key);
  }

  private toggleMonth(key: string): void {
    if (this.refOpenMonths.includes(key)) {
      this.refOpenMonths = this.refOpenMonths.filter((x: string) => x !== key);
    } else {
      this.refOpenMonths = this.refOpenMonths.concat([key]);
    }
  }

  private latestNote(e: OwnEntry): string {
    return e.notes.length > 0 ? e.notes[e.notes.length - 1].text : '';
  }

  private filtered(kind: string): OwnEntry[] {
    const kw: string = this.q.trim().toLowerCase();
    const list: OwnEntry[] = kind === 'encourage' ? this.enc : this.wnd;
    if (kw.length === 0) return list;
    return list.filter((e: OwnEntry) => {
      if (e.text.toLowerCase().includes(kw)) return true;
      if (e.notes.some((n: NoteItem) => n.text.toLowerCase().includes(kw))) return true;
      if (e.foot.some((f: string) => f.toLowerCase().includes(kw))) return true;
      return this.boundNames(e).some((n: string) => n.toLowerCase().includes(kw));
    });
  }

  private boundNames(e: OwnEntry): string[] {
    const out: string[] = [];
    if (e.kind === 'encourage') {
      e.bindIds.forEach((id: string) => {
        const w = Store.get().data.own.find((x: OwnEntry) => x.id === id);
        if (w) out.push(w.text);
      });
    } else {
      Store.get().data.own.forEach((x: OwnEntry) => {
        if (x.kind === 'encourage' && x.bindIds.includes(e.id)) out.push(x.text);
      });
    }
    Store.get().data.lib.forEach((l: LibEntry) => {
      if (l.bindIds.includes(e.id)) out.push(l.text);
    });
    return out;
  }

  private catName(cat: string): string {
    if (cat === 'resolved') return '已解决';
    if (cat === 'letgo') return '已放下';
    if (cat === 'silly') return '看起来很蠢';
    if (cat === 'tired') return '听腻了';
    return cat;
  }

  private confirmDeleteEntry(e: OwnEntry): void {
    this.getUIContext().showAlertDialog({
      title: '删除这句话？',
      message: '连同它的备注、关联关系一起删除，无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          Store.get().removeOwn(e.id);
          this.closePanel();
          this.reload();
          this.toast('已删除' );
        }
      }
    });
  }

  private confirmDeleteNote(): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条备注？',
      message: '只删除这条备注，不删除原句；无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          const id: string = this.targetId;
          if (Store.get().removeLatestNote(id)) {
            Store.get().clearDraft('note_' + id);
            this.noteInput = '';
            this.closePanel();
            this.reload();
            this.toast('备注已删除' );
          }
        }
      }
    });
  }

  private openNote(e: OwnEntry): void {
    this.panel = 'note';
    this.targetId = e.id;
    const draft: string = Store.get().loadDraft('note_' + e.id);
    this.noteInput = draft.length > 0 ? draft : this.latestNote(e);
    this.sheetOpen = true;
  }

  private openBind(e: OwnEntry): void {
    this.panel = 'bind';
    this.targetId = e.id;
    this.bindQuery = '';
    this.sheetOpen = true;
  }

  private openArchive(e: OwnEntry): void {
    this.panel = 'archive';
    this.targetId = e.id;
    this.archCat = e.kind === 'wound' ? 'resolved' : 'silly';
    this.archNote = '';
    this.withRevisit = true;
    this.sheetOpen = true;
  }

  private closePanel(): void {
    this.panel = '';
    this.targetId = '';
    this.sheetOpen = false;
  }

  private currentEntry(): OwnEntry {
    const e = Store.get().data.own.find((x: OwnEntry) => x.id === this.targetId);
    return e === undefined ? new OwnEntry() : e;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  private saveNote(): void {
    const ok: boolean = Store.get().setNote(this.targetId, this.noteInput.trim());
    Store.get().clearDraft('note_' + this.targetId);
    this.closePanel();
    this.reload();
    this.toast(ok ? '备注已保存' : '这条已经不在台前了' );
  }

  private doArchive(): void {
    const e = Store.get().data.own.find((x: OwnEntry) => x.id === this.targetId);
    if (!e) {
      this.closePanel();
      this.toast('这条已经不在台前了' );
      return;
    }
    const days: number = (e.kind === 'wound' && this.withRevisit) ? Store.get().data.settings.revisitDays : 0;
    Store.get().archiveOwn(e.id, this.archCat, this.archNote.trim(), days);
    if (e.kind === 'wound' && days > 0) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ReminderService.rescheduleAll(ctx).then((ok: boolean) => {
        if (!ok) {
          this.toast('系统通知没排进去；到期打开句栖仍会看到回访卡' );
        }
      });
    }
    this.closePanel();
    this.reload();
    this.toast('已收进回忆区' );
  }

  private candidates(e: OwnEntry): OwnEntry[] {
    if (e.kind === 'encourage') return this.wnd;
    return this.enc;
  }

  private isBound(e: OwnEntry, other: OwnEntry): boolean {
    if (e.kind === 'encourage') return e.bindIds.includes(other.id);
    return other.bindIds.includes(e.id);
  }

  private toggleBind(e: OwnEntry, other: OwnEntry): void {
    let bound: boolean = false;
    if (e.kind === 'encourage') {
      bound = Store.get().toggleBind(e.id, other.id);
    } else {
      bound = Store.get().toggleBind(other.id, e.id);
    }
    this.bindRev++;
    this.reload();
    this.toast(bound ? '已关联' : '已解除关联' );
  }

  private toggleShowReflect(): void {
    const next: boolean = !this.showRef;
    this.showRef = next;
    Store.get().data.settings.showReflect = next;
    Store.get().saveKv();
  }

  private openReflectWrite(): void {
    this.panel = 'reflectWrite';
    this.refText = '';
    this.sheetOpen = true;
  }

  private saveReflect(): void {
    if (!Store.get().addReflect(this.refText)) {
      this.toast('先写一句再保存' );
      return;
    }
    const list: OwnEntry[] = Store.get().reflects();
    if (list.length > 0) this.refOpenId = list[0].id;
    this.refText = '';
    this.closePanel();
    this.reload();
    this.toast('已记下这条省身' );
  }

  private openReflectNote(e: OwnEntry): void {
    this.panel = 'reflectNote';
    this.targetId = e.id;
    this.refNoteInput = '';
    this.sheetOpen = true;
  }

  private saveReflectNote(): void {
    const body: string = this.refNoteInput.trim();
    if (body.length === 0) return;
    Store.get().addNote(this.targetId, body);
    this.refNoteInput = '';
    this.closePanel();
    this.reload();
    this.toast('备注已加上' );
  }

  private openReflectEdit(e: OwnEntry): void {
    this.panel = 'reflectEdit';
    this.targetId = e.id;
    this.refEditText = e.text;
    this.sheetOpen = true;
  }

  private saveReflectEdit(): void {
    if (!Store.get().updateOwnText(this.targetId, this.refEditText)) {
      this.toast('正文不能为空' );
      return;
    }
    this.closePanel();
    this.reload();
    this.toast('省身已更新' );
  }

  private deleteReflect(e: OwnEntry): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条省身？',
      message: '连同它的备注一起删除，无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          Store.get().removeOwn(e.id);
          this.refOpenId = '';
          this.reload();
          this.toast('已删除' );
        }
      }
    });
  }

  private totalCount(kind: string): number {
    return kind === 'encourage' ? this.enc.length : this.wnd.length;
  }

  private bindRows(e: OwnEntry): OwnEntry[] {
    const kw: string = this.bindQuery.trim().toLowerCase();
    const list: OwnEntry[] = this.candidates(e);
    if (kw.length === 0) return list;
    return list.filter((x: OwnEntry) => x.text.toLowerCase().includes(kw));
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
  OutlineButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(this.t().ink)
      .fontFamily(FONT_SANS)
      .backgroundColor(this.t().card)
      .border({ width: 1, color: this.t().line })
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
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
      .margin({ top: 8 })
  }

  @Builder
  NotePanel() {
    Column({ space: 0 }) {
      TextArea({ placeholder: '备注：此刻想留下的一句话', text: this.noteInput })
        .height(90)
        .fontSize(15)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .padding(12)
        .onChange((v: string) => {
          this.noteInput = v;
          Store.get().saveDraft('note_' + this.targetId, v);
        })
      Row() {
        this.SolidButton('保存', () => {
          this.saveNote();
        })
        if (this.latestNote(this.currentEntry()).length > 0) {
          this.QuietButton('删除这条', () => {
            this.confirmDeleteNote();
          })
        }
        this.QuietButton('取消', () => {
          this.closePanel();
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
  BindPanel(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.kind === 'encourage' ? '这句话曾陪我度过哪件事' : '哪句话曾陪你度过这件事')
        .fontSize(13.5)
        .letterSpacing(1)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
        .margin({ bottom: 6 })
      Text('可关联多件，再点一次解除。两边是同一根线。')
        .fontSize(11.5)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ bottom: 8 })
      if (this.candidates(e).length > 6) {
        TextInput({ text: this.bindQuery, placeholder: '搜索' })
          .height(38)
          .fontSize(13)
          .fontColor(this.t().ink)
          .placeholderColor(this.t().inkSoft)
          .backgroundColor(this.t().inputBg)
          .borderRadius(this.t().radiusInput)
          .border({ width: 1, color: this.t().line })
          .onChange((v: string) => {
            this.bindQuery = v;
          })
          .margin({ bottom: 6 })
      }
      if (this.candidates(e).length === 0) {
        Text(e.kind === 'encourage' ? '树洞还是空的。先写一件难过的事，再回来关联。' : '鼓励池还是空的。先写一句鼓励，再回来关联。')
          .fontSize(12)
          .lineHeight(21)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .padding({ top: 10, bottom: 10 })
      }
      ForEach(this.bindRows(e), (x: OwnEntry) => {
        Row() {
          Text(x.text.length > 22 ? x.text.slice(0, 22) + '…' : x.text)
            .fontSize(13.5)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().ink)
            .layoutWeight(1)
          Text(this.isBound(e, x) ? '解除关联' : '关联')
            .fontSize(12)
            .fontColor(this.isBound(e, x) ? this.t().inkSoft : this.t().bg)
            .backgroundColor(this.isBound(e, x) ? this.t().card : this.t().ink)
            .border({ width: this.isBound(e, x) ? 1 : 0, color: this.t().line })
            .borderRadius(999)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .onClick(() => {
              this.toggleBind(e, x);
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .border({ width: { top: 1 }, color: this.t().lineSoft })
      }, (x: OwnEntry) => `${x.id}-${this.bindRev}`)
      Row() {
        this.QuietButton('完成', () => {
          this.closePanel();
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 10 })
  }

  @Builder
  ArchivePanel(e: OwnEntry) {
    Column({ space: 0 }) {
      Text('不再参与抽签')
        .fontSize(14)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
        .margin({ bottom: 6 })
      Text('标记后不再被抽到，分门别类收进回忆区。')
        .fontSize(11.5)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ bottom: 10 })
      Row({ space: 6 }) {
        if (e.kind === 'wound') {
          this.CatChip('resolved', '已解决')
          this.CatChip('letgo', '已放下')
        } else {
          this.CatChip('silly', '看起来很蠢')
          this.CatChip('tired', '听腻了')
        }
      }
      .width('100%')
      .margin({ bottom: 8 })
      TextArea({ placeholder: e.kind === 'wound' ? '备注：为什么解决了 / 放下了？' : '备注：为什么听腻了 / 觉得蠢？', text: this.archNote })
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
          this.archNote = v;
        })
      if (e.kind === 'wound') {
        Row({ space: 8 }) {
          Text(this.withRevisit ? '✓' : '')
            .fontSize(12)
            .fontColor(this.t().sealInk)
            .backgroundColor(this.withRevisit ? this.t().seal : this.t().card)
            .border({ width: 1, color: this.withRevisit ? Color.Transparent : this.t().line })
            .borderRadius(4)
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
          Text(`${Store.get().data.settings.revisitDays} 天后轻轻问我一次（归档后可在回忆里单独改天数）`)
            .fontSize(12.5)
            .fontColor(this.t().inkSoft)
        }
        .width('100%')
        .margin({ top: 8 })
        .onClick(() => {
          this.withRevisit = !this.withRevisit;
        })
      }
      Row() {
        this.SolidButton('收进回忆区', () => {
          this.doArchive();
        })
        this.QuietButton('取消', () => {
          this.closePanel();
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
  CatChip(cat: string, label: string) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1)
      .fontColor(this.archCat === cat ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.archCat === cat ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.archCat === cat ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .onClick(() => {
        this.archCat = cat;
      })
  }

  @Builder
  EntryRow(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontSize(16.5)
        .lineHeight(33)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Text(fmtDate(e.createdAt))
          .fontSize(10.5)
          .letterSpacing(1)
          .fontColor(this.t().inkSoft)
        ForEach(this.boundNames(e), (n: string, idx: number) => {
          Text(e.kind === 'encourage' ? `曾陪我度过「${n.length > 12 ? n.slice(0, 12) + '…' : n}」` : `有「${n.length > 12 ? n.slice(0, 12) + '…' : n}」陪着`)
            .fontSize(10.5)
            .fontColor(this.t().inkSoft)
        }, (n: string, idx: number) => `${e.id}-bind-${idx}-${this.bindRev}`)
      }
      .width('100%')
      .margin({ top: 6 })
      if (this.latestNote(e).length > 0) {
        this.NoteLine(this.latestNote(e))
      }
      ForEach(e.foot, (f: string, idx: number) => {
        this.NoteLine(f)
      }, (f: string, idx: number) => `${e.id}-foot-${idx}`)
      Flex({ wrap: FlexWrap.Wrap }) {
        this.QuietButton('加备注', () => {
          this.openNote(e);
        })
        if (e.kind === 'encourage') {
          this.QuietButton('关联旧事', () => {
            this.openBind(e);
          })
          this.QuietButton('不再参与抽签', () => {
            this.openArchive(e);
          })
        } else {
          this.QuietButton('关联鼓励', () => {
            this.openBind(e);
          })
          this.QuietButton('标记已解决 / 已放下', () => {
            this.openArchive(e);
          })
        }
        this.QuietButton('删除', () => {
          this.confirmDeleteEntry(e);
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 10 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  @Builder
  EmptyGuide() {
    Column({ space: 8 }) {
      Text('从这里开始')
        .fontSize(14)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text('① 今日写一句鼓励，或一件难过的事\n② 抽签时它会回来，陪你一会儿\n③ 归档后进回忆区，成为第二本日记')
        .fontSize(12)
        .lineHeight(23)
        .fontColor(this.t().inkSoft)
        .width('100%')
      Row({ space: 8 }) {
        this.SolidButton('去今日写一句', () => {
          this.goToday();
        })
        this.OutlineButton('去句库看看', () => {
          this.goLibrary();
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 12 })
  }

  @Builder
  ListSection(kind: string, title: string, empty: string) {
    Column({ space: 0 }) {
      Row() {
        Text(title)
          .fontSize(14)
          .letterSpacing(1.5)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
        Text(`${this.totalCount(kind)} ${kind === 'encourage' ? '句' : '件'}`)
          .fontSize(10)
          .fontColor(this.t().inkSoft)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(999)
          .padding({ left: 9, right: 9, top: 2, bottom: 2 })
          .margin({ left: 8 })
        Blank()
        Text(kind === 'encourage'
          ? (this.showEnc ? '−' : '＋')
          : (this.showWnd ? '−' : '＋'))
          .fontSize(16)
          .fontColor(this.t().seal)
      }
      .width('100%')
      .padding({ top: 14, bottom: 8 })
      .onClick(() => {
        if (kind === 'encourage') {
          this.showEnc = !this.showEnc;
        } else {
          this.showWnd = !this.showWnd;
        }
      })

      if (kind === 'encourage' ? this.showEnc : this.showWnd) {
        if (this.filtered(kind).length === 0) {
          Column({ space: 6 }) {
            Text(this.q.length > 0 ? '没有找到' : (kind === 'encourage' ? '还一句都没有' : '树洞是空的'))
              .fontSize(14)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
            Text(this.q.length > 0 ? '换个词试试。' : empty)
              .fontSize(12)
              .lineHeight(22)
              .fontColor(this.t().inkSoft)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 22, bottom: 26 })
        } else {
          LazyForEach(kind === 'encourage' ? this.encDs : this.wndDs, (e: OwnEntry) => {
            this.EntryRow(e)
          }, (e: OwnEntry) => e.id)
        }
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 2, bottom: 8 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }

  @Builder
  ReflectSection() {
    Column({ space: 0 }) {
      Row() {
        Text('省身')
          .fontSize(14)
          .letterSpacing(1.5)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
        Text(`${this.refs.length} 条`)
          .fontSize(10)
          .fontColor(this.t().inkSoft)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(999)
          .padding({ left: 9, right: 9, top: 2, bottom: 2 })
          .margin({ left: 8 })
        Blank()
        Text(this.refSectionOpen ? '−' : '＋')
          .fontSize(16)
          .fontColor(this.t().seal)
      }
      .width('100%')
      .padding({ top: 14, bottom: 8 })
      .onClick(() => {
        this.refSectionOpen = !this.refSectionOpen;
      })

      if (this.refSectionOpen) {
        this.SolidButton('写一条省身', () => {
          this.openReflectWrite();
        })
        Row({ space: 6 }) {
          TextInput({ text: this.refQ, placeholder: '搜索省身正文或备注' })
            .layoutWeight(1)
            .height(38)
            .fontSize(12.5)
            .fontColor(this.t().ink)
            .placeholderColor(this.t().inkSoft)
            .backgroundColor(this.t().inputBg)
            .borderRadius(this.t().radiusInput)
            .border({ width: 1, color: this.t().line })
            .onChange((v: string) => {
              this.refQ = v;
              this.refLimit = 30;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 8 })
        if (this.filteredReflects().length === 0) {
          Text(this.refQ.length > 0 ? '没有找到。换个词，或清空搜索。' : '省身不是任务。想写的时候再写。')
            .fontSize(12.5)
            .lineHeight(23)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .padding({ top: 12, bottom: 16 })
        } else {
          ForEach(this.refYearGroups(), (y: ReflectYear) => {
            Column({ space: 0 }) {
              Row() {
                Text(y.label)
                  .fontSize(12)
                  .letterSpacing(1.5)
                  .fontFamily(FONT_SERIF)
                  .fontColor(this.t().inkStrong)
                Text(`${y.total} 条`)
                  .fontSize(9.5)
                  .fontColor(this.t().inkSoft)
                  .margin({ left: 6 })
                Blank()
                Text(this.isYearOpen(y.key) ? '−' : '＋')
                  .fontSize(13)
                  .fontColor(this.t().seal)
              }
              .width('100%')
              .padding({ top: 12, bottom: 2 })
              .onClick(() => {
                this.toggleYear(y.key);
              })
              if (this.isYearOpen(y.key)) {
                ForEach(y.months, (g: ReflectGroup) => {
                  Column({ space: 0 }) {
                    Row() {
                      Text(g.label)
                        .fontSize(11)
                        .letterSpacing(1.5)
                        .fontColor(this.t().inkSoft)
                      Text(`${g.items.length} 条`)
                        .fontSize(9.5)
                        .fontColor(this.t().inkSoft)
                        .margin({ left: 6 })
                      Blank()
                      Text(this.isMonthOpen(g.key) ? '−' : '＋')
                        .fontSize(13)
                        .fontColor(this.t().seal)
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 4, left: 8 })
                    .onClick(() => {
                      this.toggleMonth(g.key);
                    })
                    if (this.isMonthOpen(g.key)) {
                      ForEach(g.items, (e: OwnEntry) => {
                        this.ReflectRow(e)
                      }, (e: OwnEntry) => `${e.id}-${e.notes.length}`)
                    }
                  }
                  .width('100%')
                }, (g: ReflectGroup) => g.key)
              }
            }
            .width('100%')
          }, (y: ReflectYear) => y.key)
          if (this.filteredReflects().length > this.refShown().length) {
            Text(`加载更多（还有 ${this.filteredReflects().length - this.refShown().length} 条）`)
              .fontSize(12)
              .fontColor(this.t().seal)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 10 })
              .onClick(() => {
                this.refLimit += 30;
              })
          }
        }
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 2, bottom: 8 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 12 })
  }

  @Builder
  ReflectRow(e: OwnEntry) {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Text(fmtDate(e.createdAt))
          .fontSize(11)
          .fontColor(this.t().inkSoft)
        Blank()
        if (e.notes.length > 0) {
          Text(`备注 ${e.notes.length}`)
            .fontSize(10)
            .fontColor(this.t().inkSoft)
        }
        Text(this.refOpenId === e.id ? '−' : '＋')
          .fontSize(14)
          .fontColor(this.t().seal)
      }
      .width('100%')
      .onClick(() => {
        this.refOpenId = this.refOpenId === e.id ? '' : e.id;
        this.refNotesAll = false;
      })
      Text(e.text)
        .fontSize(14.5)
        .lineHeight(27)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .wordBreak(WordBreak.BREAK_ALL)
        .width('100%')
        .maxLines(this.refOpenId === e.id ? 999 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      if (this.refOpenId === e.id) {
        if (e.notes.length > 0) {
          Column({ space: 0 }) {
            ForEach(e.notes.slice(0, this.refNotesAll ? e.notes.length : 3), (n: NoteItem) => {
              Column({ space: 2 }) {
                Text(fmtDate(n.at))
                  .fontSize(10)
                  .fontColor(this.t().inkSoft)
                Text(n.text)
                  .fontSize(12)
                  .lineHeight(21)
                  .fontColor(this.t().ink)
                  .wordBreak(WordBreak.BREAK_ALL)
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: 6, bottom: 4 })
              .border({ width: { top: 1 }, color: this.t().lineSoft })
            }, (n: NoteItem) => `${n.at}-${n.text}`)
            if (e.notes.length > 3) {
              Text(this.refNotesAll ? '收起备注' : `查看全部 ${e.notes.length} 条备注`)
                .fontSize(11.5)
                .fontColor(this.t().seal)
                .padding({ top: 6, bottom: 2 })
                .onClick(() => {
                  this.refNotesAll = !this.refNotesAll;
                })
            }
          }
          .width('100%')
          .margin({ top: 8 })
        }
        Row({ space: 2 }) {
          this.QuietButton('加备注', () => {
            this.openReflectNote(e);
          })
          this.QuietButton('编辑', () => {
            this.openReflectEdit(e);
          })
          this.QuietButton('删除', () => {
            this.deleteReflect(e);
          })
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  @Builder
  ReflectWritePanel() {
    Column({ space: 10 }) {
      Text('写一条省身')
        .fontSize(17)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      TextArea({ text: this.refText, placeholder: '今天，你想省察什么？' })
        .height(160)
        .fontSize(14)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.refText = v;
        })
      Row({ space: 8 }) {
        this.QuietButton('取消', () => {
          this.closePanel();
        })
        this.SolidButton('保存', () => {
          this.saveReflect();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
  }

  @Builder
  ReflectNotePanel() {
    Column({ space: 10 }) {
      Text('加备注')
        .fontSize(17)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text(this.currentEntry().text)
        .fontSize(12)
        .lineHeight(21)
        .fontColor(this.t().inkSoft)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      TextArea({ text: this.refNoteInput, placeholder: '此刻补充一句……' })
        .height(120)
        .fontSize(14)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.refNoteInput = v;
        })
      Row({ space: 8 }) {
        this.QuietButton('取消', () => {
          this.closePanel();
        })
        this.SolidButton('保存备注', () => {
          this.saveReflectNote();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
  }

  @Builder
  ReflectEditPanel() {
    Column({ space: 10 }) {
      Text('编辑省身')
        .fontSize(17)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      TextArea({ text: this.refEditText })
        .height(160)
        .fontSize(14)
        .fontColor(this.t().ink)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.refEditText = v;
        })
      Row({ space: 8 }) {
        this.QuietButton('取消', () => {
          this.closePanel();
        })
        this.SolidButton('保存修改', () => {
          this.saveReflectEdit();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
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
          this.closePanel();
        })
      Column() {
        if (this.panel === 'note') {
          this.NotePanel()
        }
        if (this.panel === 'bind') {
          this.BindPanel(this.currentEntry())
        }
        if (this.panel === 'archive') {
          this.ArchivePanel(this.currentEntry())
        }
        if (this.panel === 'reflectWrite') {
          this.ReflectWritePanel()
        }
        if (this.panel === 'reflectNote') {
          this.ReflectNotePanel()
        }
        if (this.panel === 'reflectEdit') {
          this.ReflectEditPanel()
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 20 })
      .backgroundColor(this.t().bg)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .margin({ left: 10, right: 10, bottom: this.kbHeight > 0 ? this.kbHeight : 0 })
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
        this.Label('我的话 · 未导出时只有这台设备看得到')
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
          this.encDs.setData(this.filtered('encourage'));
          this.wndDs.setData(this.filtered('wound'));
            if (v.trim().length > 0) {
              this.showEnc = true;
              this.showWnd = true;
            }
          })
          .margin({ bottom: 12 })

        this.ListSection('encourage', '鼓励池',
          '还一句都没有。下一个心情不错的日子，写一句留给低谷时的自己。')

        this.ListSection('wound', '旧事簿',
          '树洞是空的。难过的事写下来，就已经轻了一点。')

        if (this.showRef) {
          this.ReflectSection()
        }

        if (this.enc.length === 0 && this.wnd.length === 0 && this.refs.length === 0 && this.q.length === 0) {
          this.EmptyGuide()
        }

        Blank()

        Text('鼓励与旧事可以互相关联；旧事归档时会自动给鼓励留下注脚')
          .fontSize(11.5)
          .lineHeight(22)
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












