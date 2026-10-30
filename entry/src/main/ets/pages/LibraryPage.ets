// 句栖 · 句库

import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { Store } from '../data/Store';
import { LibEntry, DislikeEntry, MaterialEntry, RitualCtx, OwnEntry, fmtDate } from '../model/Types';
import { MaterialIndexer } from '../services/MaterialIndexer';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { ArrayDataSource } from '../utils/DataSource';
import { splitSentences } from '../utils/TextSplit';
import { UiState } from '../state/UiState';

@ComponentV2
export struct LibraryPage {
  @Local ui: UiState = UiState.get();
  @Event startRitual: (ctx: RitualCtx) => void = () => {};
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  @Local libs: LibEntry[] = [];
  private libDs: ArrayDataSource<LibEntry> = new ArrayDataSource<LibEntry>();
  private matDs: ArrayDataSource<MaterialEntry> = new ArrayDataSource<MaterialEntry>();
  private matPreviewDs: ArrayDataSource<string> = new ArrayDataSource<string>();
  @Local dislikes: DislikeEntry[] = [];
  @Local qLib: string = '';
  @Local qDis: string = '';
  @Local showLib: boolean = true;
  @Local showMaterials: boolean = false;
  @Local showMatRules: boolean = false;
  @Local showDislikes: boolean = false;
  @Local showReplies: boolean = false;
  @Local replies: OwnEntry[] = [];
  @Local matName: string = '';
  @Local matText: string = '';
  @Local matEditId: string = '';
  @Local matQuery: string = '';
  @Local matCount: number = 0;
  @Local matIndexing: boolean = false;
  @Local matSaving: boolean = false;
  @Local matProgress: string = '';
  @Local matPreviewOpen: boolean = false;
  @Local matPreviewName: string = '';
  @Local matPreviewLoading: boolean = false;
  @Local matPreviewItems: string[] = [];
  @Local matPick: string[] = [];
  @Local matPreviewBusy: boolean = false;
  @Local showFind: boolean = false;
  @Local findPick: string = '';
  @Local findKw: string = '';
  @Local findText: string = '';
  @Local findName: string = '';
  @Local relLibId: string = '';
  @Local relRev: number = 0;
  private lastFind: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('ui.dataVersion')
  onData(monitor: IMonitor): void {
    this.reload();
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private reload(): void {
    const st = Store.get();
    this.libs = st.data.lib.slice();
    this.dislikes = st.data.dislikes.slice();
    this.replies = st.data.own
      .filter((e: OwnEntry) => e.kind === 'reply')
      .sort((a: OwnEntry, b: OwnEntry) => b.createdAt - a.createdAt);
    this.matCount = st.data.materials.length;
    this.libDs.setData(this.filteredLibs());
    this.matDs.setData(this.materials());
  }

  private refreshLibDs(): void {
    this.libDs.setData(this.filteredLibs());
  }

  private refreshMatDs(): void {
    this.matDs.setData(this.materials());
  }

  private filteredLibs(): LibEntry[] {
    const kw: string = this.qLib.trim().toLowerCase();
    if (kw.length === 0) return this.libs;
    return this.libs.filter((e: LibEntry) =>
      e.text.toLowerCase().includes(kw) || e.source.toLowerCase().includes(kw) || e.tag.toLowerCase().includes(kw));
  }

  private filteredDislikes(): DislikeEntry[] {
    const kw: string = this.qDis.trim().toLowerCase();
    const list: DislikeEntry[] = this.dislikes.slice();
    list.sort((a: DislikeEntry, b: DislikeEntry) => b.at - a.at);
    if (kw.length === 0) return list;
    return list.filter((d: DislikeEntry) =>
      d.text.toLowerCase().includes(kw) || d.source.toLowerCase().includes(kw));
  }

  private dislikeLib(e: LibEntry): void {
    Store.get().addDislike(e.text, e.source, e.origin);
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: '已加入排除名单，句库里的这条也一并移出了' });
  }

  private removeLib(e: LibEntry): void {
    Store.get().removeLib(e.id);
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: '已移出句库' });
  }

  private undoDislike(d: DislikeEntry): void {
    Store.get().data.dislikes = Store.get().data.dislikes.filter((x: DislikeEntry) => x.text !== d.text);
    Store.get().saveSettings();
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: '已撤销排除，它又能出现了' });
  }

  // ---------- 材料库 ----------
  private materials(): MaterialEntry[] {
    const kw: string = this.matQuery.trim();
    const list: MaterialEntry[] = Store.get().data.materials;
    if (kw.length === 0) return list;
    return list.filter((m: MaterialEntry) => m.name.includes(kw) || m.text.includes(kw));
  }

  private startEdit(m: MaterialEntry): void {
    this.matEditId = m.id;
    this.matName = m.name;
    this.matText = m.text;
  }

  private cancelEdit(): void {
    this.matEditId = '';
    this.matName = '';
    this.matText = '';
  }

  private async saveMaterial(): Promise<void> {
    if (this.matSaving) return;
    const name: string = this.matName.trim();
    const text: string = this.matText.trim();
    if (name.length === 0 || text.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '材料名和文本都要填' });
      return;
    }
    const editing: boolean = this.matEditId.length > 0;
    if (!editing) {
      const dup: boolean = Store.get().data.materials.some((m: MaterialEntry) => m.name === name && m.text === text);
      if (dup) {
        this.getUIContext().getPromptAction().showToast({ message: '这份材料已经在库里了' });
        return;
      }
    }
    this.matSaving = true;
    this.matProgress = '请稍等，正在建立句子索引…';
    let createdId: string = '';
    try {
      let id: string = this.matEditId;
      if (editing) {
        Store.get().updateMaterial(id, name, text);
      } else {
        const m: MaterialEntry = Store.get().addMaterial(name, text);
        id = m.id;
        createdId = m.id;
      }
      await Store.get().reindexMaterial(id, text);
      this.getUIContext().getPromptAction().showToast({ message: editing ? '已保存' : '已存入材料库' });
      this.cancelEdit();
      this.reload();
    } catch (e) {
      if (createdId.length > 0) {
        // 索引失败时把刚建的材料撤回，避免留下“有记录、搜不到”的半成品
        Store.get().deleteMaterial(createdId);
        this.reload();
      }
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    } finally {
      this.matSaving = false;
      this.matProgress = '';
    }
  }

  private removeMaterial(m: MaterialEntry): void {
    if (m.path.length > 0) {
      try {
        fs.unlinkSync(m.path);
      } catch (e) {
      }
    }
    Store.get().deleteMaterial(m.id);
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: '已删除' });
  }

  private materialTitle(name: string): string {
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  private materialSize(m: MaterialEntry): string {
    if (m.path.length > 0) {
      if (m.size >= 1024 * 1024) return `${Math.round(m.size / 1024 / 1024)} MB`;
      return `${Math.max(1, Math.round(m.size / 1024))} KB`;
    }
    return `${m.text.length} 字`;
  }

  private materialBrief(m: MaterialEntry): string {
    if (m.path.length > 0) return '文件材料 · 已建立句子索引';
    return m.text.length > 46 ? m.text.slice(0, 46) + '…' : m.text;
  }

  private previewInLib(text: string): boolean {
    return Store.get().data.lib.some((e: LibEntry) => e.text === text);
  }

  private previewExcluded(text: string): boolean {
    return Store.get().dislikedSet().has(text);
  }

  private async openMaterialPreview(m: MaterialEntry): Promise<void> {
    this.matPreviewOpen = true;
    this.matPreviewLoading = true;
    this.matPreviewBusy = false;
    this.matPreviewName = m.name;
    this.matPreviewItems = [];
    this.matPick = [];
    const raw: string[] = await Store.get().materialSentences(m.id, 0);
    const seen: Set<string> = new Set<string>();
    const items: string[] = [];
    raw.forEach((t: string) => {
      if (t.length === 0 || seen.has(t)) return;
      seen.add(t);
      items.push(t);
    });
    const picks: string[] = [];
    items.forEach((t: string) => {
      if (!this.previewInLib(t) && !this.previewExcluded(t)) picks.push(t);
    });
    this.matPreviewItems = items;
    this.matPick = picks;
    this.matPreviewDs.setData(items);
    this.matPreviewLoading = false;
  }

  private togglePreview(text: string): void {
    if (this.previewInLib(text) || this.previewExcluded(text)) return;
    const row: number = this.matPreviewItems.indexOf(text);
    const i: number = this.matPick.indexOf(text);
    if (i >= 0) {
      this.matPick = this.matPick.filter((x: string) => x !== text);
    } else {
      this.matPick = this.matPick.concat([text]);
    }
    this.matPreviewDs.notifyChange(row);
  }

  private selectAllPreview(): void {
    this.matPick = this.matPreviewItems.filter((t: string) =>
      !this.previewInLib(t) && !this.previewExcluded(t));
    this.matPreviewDs.notifyAll();
  }

  private clearPreview(): void {
    this.matPick = [];
    this.matPreviewDs.notifyAll();
  }

  private collectPreview(): void {
    if (this.matPreviewBusy || this.matPick.length === 0) return;
    this.matPreviewBusy = true;
    let added: number = 0;
    this.matPick.forEach((t: string) => {
      if (Store.get().addLib(t, `摘自《${this.matPreviewName}》`, 'material', '材料收藏')) added++;
    });
    this.matPreviewBusy = false;
    this.matPreviewOpen = false;
    this.reload();
    this.getUIContext().getPromptAction().showToast({
      message: added > 0 ? `已材料收藏 ${added} 句` : '这些句子已在句库里'
    });
  }

  private async importTxt(): Promise<void> {
    let srcFile: fs.File | null = null;
    let dstFile: fs.File | null = null;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docPicker = new picker.DocumentViewPicker(ctx);
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.txt', '.md', '.markdown'];
      const uris: string[] = await docPicker.select(opt);
      if (!uris || uris.length === 0) return;
      srcFile = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(srcFile.fd);
      const dir: string = ctx.filesDir + '/materials';
      try {
        fs.mkdirSync(dir);
      } catch (e) {
      }
      let fileName: string = '材料';
      const segs: string[] = uris[0].split('/');
      if (segs.length > 0) fileName = segs[segs.length - 1];
      const q: number = fileName.indexOf('?');
      if (q > 0) fileName = fileName.slice(0, q);
      try {
        fileName = decodeURIComponent(fileName);
      } catch (e) {
      }
      const dot: number = fileName.lastIndexOf('.');
      const isMarkdown: boolean = dot > 0 &&
        (fileName.slice(dot).toLowerCase() === '.md' || fileName.slice(dot).toLowerCase() === '.markdown');
      if (dot > 0) fileName = fileName.slice(0, dot);
      const dst: string = dir + '/' + Date.now().toString(36) + '.txt';
      dstFile = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const m: MaterialEntry = Store.get().addMaterialFile(fileName, dst, stat.size);
      this.reload();
      this.matIndexing = true;
      this.matProgress = '正在复制文件…';
      this.getUIContext().getPromptAction().showToast({ message: `已导入《${fileName}》，正在建立句子索引…` });
      const buf = new ArrayBuffer(64 * 1024);
      let copied: number = 0;
      let n: number = 0;
      while ((n = fs.readSync(srcFile.fd, buf)) > 0) {
        fs.writeSync(dstFile.fd, buf.slice(0, n));
        copied += n;
        this.matProgress = `正在复制 ${Math.min(100, Math.round(copied / Math.max(1, stat.size) * 100))}%`;
        await new Promise<void>((resolve) => {
          setTimeout(() => resolve(), 0);
        });
      }
      fs.closeSync(dstFile);
      dstFile = null;
      this.matProgress = '正在建立句子索引…';
      const count: number = await MaterialIndexer.indexFile(m.id, dst, isMarkdown);
      this.matProgress = `已索引 ${count} 句`;
      this.getUIContext().getPromptAction().showToast({ message: `《${fileName}》已入库，可以检索了` });
      this.matIndexing = false;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请换一个 .txt / .md 文件' });
    } finally {
      this.matIndexing = false;
      if (srcFile !== null) fs.closeSync(srcFile);
      if (dstFile !== null) fs.closeSync(dstFile);
    }
  }

  private lastBreak(s: string): number {
    let last: number = -1;
    const marks: string = '。！？!?；;…\n';
    for (let i = s.length - 1; i >= 0; i--) {
      if (marks.indexOf(s.charAt(i)) >= 0) {
        last = i;
        break;
      }
    }
    if (last < 0 && s.length > 40000) {
      last = s.length - 1;
    }
    return last;
  }

  private async findOne(): Promise<void> {
    const all: MaterialEntry[] = Store.get().data.materials;
    let list: MaterialEntry[] = this.findPick.length > 0
      ? all.filter((m: MaterialEntry) => m.id === this.findPick)
      : all.slice();
    if (list.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可用的材料' });
      return;
    }
    const kws: string[] = this.findKw.trim().split(/\s+/).filter((k: string) => k.length > 0);
    for (let i = list.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const t: MaterialEntry = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    const dis: Set<string> = Store.get().dislikedSet();
    let foundText: string = '';
    let foundName: string = '';
    for (let i = 0; i < Math.min(list.length, 8); i++) {
      const m: MaterialEntry = list[i];
      let sents: string[] = await Store.get().searchMaterial(kws, m.id);
      if (sents.length === 0 && m.text.length > 0) {
        sents = splitSentences(m.text)
          .filter((s: string) => kws.length === 0 || kws.every((k: string) => s.includes(k)));
      }
      // 排除名单同样约束材料检索，否则「不喜欢」在这里等于没生效
      sents = sents.filter((s: string) => s.length > 0 && !dis.has(s));
      if (sents.length === 0) continue;
      let pick: string = sents[Math.floor(Math.random() * sents.length)];
      if (sents.length > 1 && pick === this.lastFind) {
        pick = sents[Math.floor(Math.random() * sents.length)];
      }
      foundText = pick;
      foundName = m.name;
      break;
    }
    if (foundText.length > 0) {
      this.lastFind = foundText;
      this.findText = foundText;
      this.findName = foundName;
      return;
    }
    this.findText = '';
    this.getUIContext().getPromptAction().showToast({
      message: this.findKw.trim().length > 0
        ? `没有找到同时含「${this.findKw.trim()}」的句子，换个关键词试试`
        : '这份材料里没有可抽取的句子'
    });
  }

  private saveFound(): void {
    if (this.findText.length === 0) return;
    const ok: boolean = Store.get().addLib(this.findText, `摘自《${this.findName}》`, 'material', '原文 · 材料检索');
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: ok ? '已收入句库' : '句库里已有这句' });
  }

  private dislikeFound(): void {
    if (this.findText.length === 0) return;
    Store.get().addDislike(this.findText, `摘自《${this.findName}》`, 'material');
    this.findText = '';
    this.reload();
    this.getUIContext().getPromptAction().showToast({ message: '已加入排除名单' });
  }

  private originName(o: string): string {
    if (o === 'material') return '材料';
    if (o === 'own') return '自己的话';
    return '句库';
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
  SectionHeader(title: string, count: string, open: boolean, action: () => void) {
    Row() {
      Text(title)
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Text(count)
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        .margin({ left: 8 })
      Blank()
      Text(open ? '−' : '＋')
        .fontSize(16)
        .fontColor(this.t().seal)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .onClick(action)
  }

  @Builder
  FavHeader() {
    Row() {
      Text('我的收藏')
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Text(`${this.filteredLibs().length} 句`)
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        .margin({ left: 8 })
      Blank()
      Text(this.showLib ? '−' : '＋')
        .fontSize(16)
        .fontColor(this.t().seal)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .onClick(() => {
      this.showLib = !this.showLib;
    })
  }

  @Builder
  ReplyHeader() {
    Row() {
      Text('回信')
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Text(`${this.replies.length} 句`)
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        .margin({ left: 8 })
      Blank()
      Text(this.showReplies ? '−' : '＋')
        .fontSize(16)
        .fontColor(this.t().seal)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .onClick(() => {
      this.showReplies = !this.showReplies;
    })
  }

  private replySource(e: OwnEntry): string {
    const p: OwnEntry | undefined = Store.get().data.own.find((x: OwnEntry) => x.id === e.replyToId);
    return p === undefined ? '' : p.text;
  }

  @Builder
  ReplyRow(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontSize(14.5)
        .lineHeight(28)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .width('100%')
      if (this.replySource(e).length > 0) {
        Text(`回的是：${this.replySource(e)}`)
          .fontSize(11.5)
          .lineHeight(21)
          .fontColor(this.t().inkSoft)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
      }
      Text(fmtDate(e.createdAt))
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 10 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  @Builder
  MaterialHeader() {
    Column() {
      Row() {
        Text('材料库')
          .fontSize(14)
          .letterSpacing(1.5)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
        Text(`${this.matCount} 份`)
          .fontSize(10)
          .fontColor(this.t().inkSoft)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(999)
          .padding({ left: 9, right: 9, top: 2, bottom: 2 })
          .margin({ left: 8 })
        Text('?')
          .fontSize(10)
          .fontColor(this.t().seal)
          .border({ width: 1, color: this.t().seal })
          .borderRadius(999)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .margin({ left: 6 })
          .onClick(() => {
            this.showMatRules = !this.showMatRules;
          })
        Blank()
        Text(this.showMaterials ? '−' : '＋')
          .fontSize(16)
          .fontColor(this.t().seal)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: this.showMatRules ? 4 : 14 })
      .onClick(() => {
        this.showMaterials = !this.showMaterials;
      })
      if (this.matIndexing) {
        Text(this.matProgress)
          .fontSize(11.5)
          .fontColor(this.t().seal)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 8 })
      }
      if (this.showMatRules) {
        Text('一、断句：空行分隔句子；单个换行按空格处理；段内句号不再单独切。\n二、长度：不按字数判断是不是句子；长句在卡片里可以滚动阅读。\n三、关键词：留空随机；多个词用空格隔开，必须全部出现。\n四、范围：默认全部材料随机挑一份，也可以先选定某一份。\n五、原则：全程本机，不改写，抽出的一定是原文并注明材料名。\n六、批量收藏：材料行点「预览」，可逐句选择；已在句库、已在排除名单的不默认选，同一材料内重复只留一条。\n七、格式：支持 .txt 和 Markdown（.md / .markdown）；Markdown 会先去掉标记再分句。')
          .fontSize(11.5)
          .lineHeight(21)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 14 })
      }
    }
    .width('100%')
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }

  @Builder
  DislikeHeader() {
    Row() {
      Text('排除名单')
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Text(`${this.dislikes.length} 条`)
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        .margin({ left: 8 })
      Blank()
      Text(this.showDislikes ? '−' : '＋')
        .fontSize(16)
        .fontColor(this.t().seal)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .onClick(() => {
      this.showDislikes = !this.showDislikes;
    })
  }

  @Builder
  Chip(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.2)
      .fontColor(active ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(active ? this.t().seal : this.t().card)
      .border({ width: 1, color: active ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .margin({ right: 6, bottom: 6 })
      .onClick(action)
  }

  @Builder
  GhostButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(this.t().ink)
      .fontFamily(FONT_SANS)
      .backgroundColor(this.t().card)
      .border({ width: 1, color: this.t().line })
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 18, right: 18, top: 11, bottom: 11 })
      .margin({ right: 8, bottom: 8 })
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
  SearchBox(placeholder: string, value: string, onChange: (v: string) => void) {
    TextInput({ text: value, placeholder: placeholder })
      .height(42)
      .fontSize(14)
      .fontColor(this.t().ink)
      .placeholderColor(this.t().inkSoft)
      .backgroundColor(this.t().inputBg)
      .borderRadius(this.t().radiusInput)
      .border({ width: 1, color: this.t().line })
      .onChange(onChange)
      .margin({ bottom: 10 })
  }

  private relEnc(): OwnEntry[] {
    return Store.get().ownActive('encourage');
  }

  private relWnd(): OwnEntry[] {
    return Store.get().ownActive('wound');
  }

  private relOn(ownId: string): boolean {
    const e: LibEntry | undefined = Store.get().data.lib.find((x: LibEntry) => x.id === this.relLibId);
    return e !== undefined ? e.bindIds.includes(ownId) : false;
  }

  private toggleRel(ownId: string): void {
    Store.get().toggleLibBind(this.relLibId, ownId);
    this.relRev++;
  }

  @Builder
  RelRow(x: OwnEntry) {
    Row({ space: 8 }) {
      Text(x.kind === 'encourage' ? '鼓励' : '旧事')
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      Text(x.text)
        .fontSize(12.5)
        .lineHeight(20)
        .fontColor(this.t().ink)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.relOn(x.id) ? '已关联' : '关联')
        .fontSize(11)
        .fontColor(this.relOn(x.id) ? this.t().seal : this.t().inkSoft)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
    .onClick(() => {
      this.toggleRel(x.id);
    })
  }

  @Builder
  RelPanel(e: LibEntry) {
    Column({ space: 0 }) {
      Text('这条收藏可以同时关联自己的鼓励和旧事。点一下切换。')
        .fontSize(11)
        .lineHeight(19)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ top: 4, bottom: 2 })
      if (this.relEnc().length === 0 && this.relWnd().length === 0) {
        Text('你还没有写过鼓励或旧事，先去今日页写一句。')
          .fontSize(12)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ top: 6, bottom: 6 })
      } else {
        ForEach(this.relEnc(), (x: OwnEntry) => {
          this.RelRow(x)
        }, (x: OwnEntry) => `e-${x.id}-${this.relRev}`)
        ForEach(this.relWnd(), (x: OwnEntry) => {
          this.RelRow(x)
        }, (x: OwnEntry) => `w-${x.id}-${this.relRev}`)
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 6 })
  }

  @Builder
  LibRow(e: LibEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontSize(16)
        .lineHeight(32)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Row({ space: 6 }) {
        Text(e.source.length > 0 ? e.source : '无出处')
          .fontSize(10.5)
          .letterSpacing(1)
          .fontColor(this.t().inkSoft)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(e.tag)
          .fontSize(10)
          .letterSpacing(1)
          .fontColor(this.t().seal)
          .backgroundColor(this.t().sealSoft)
          .borderRadius(999)
          .padding({ left: 9, right: 9, top: 2, bottom: 2 })
          .flexShrink(0)
      }
      .width('100%')
      .margin({ top: 4 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.QuietButton('移出句库', () => {
          this.removeLib(e);
        })
        this.QuietButton('不喜欢', () => {
          this.dislikeLib(e);
        })
        this.QuietButton('关联', () => {
          this.relLibId = this.relLibId === e.id ? '' : e.id;
          this.relRev++;
        })
        if (e.bindIds.length > 0) {
          Text(`已关联 ${e.bindIds.length}`)
            .fontSize(10.5)
            .fontColor(this.t().seal)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        }
      }
      .width('100%')
      .margin({ top: 4 })
      if (this.relLibId === e.id) {
        this.RelPanel(e)
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 6 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  @Builder
  MaterialList() {
    if (this.matCount === 0) {
      Text('材料库还是空的。把你的摘抄、某本书的文本粘贴进来，或选择一个 .txt / .md 文件。')
        .fontSize(12.5)
        .lineHeight(24)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ top: 8, bottom: 8 })
    } else {
      TextInput({ text: this.matQuery, placeholder: '搜索材料：名称或内容' })
        .height(40)
        .fontSize(13.5)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.matQuery = v;
          this.refreshMatDs();
        })
        .margin({ top: 6, bottom: 6 })
      LazyForEach(this.matDs, (m: MaterialEntry) => {
        Column({ space: 0 }) {
          Row() {
            Text(this.materialTitle(m.name))
              .fontSize(14.5)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.materialSize(m))
              .fontSize(10)
              .fontColor(this.t().inkSoft)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: this.t().line })
              .borderRadius(999)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .margin({ left: 8 })
              .flexShrink(0)
            this.QuietButton('预览', () => {
              this.openMaterialPreview(m);
            })
            if (m.path.length === 0) {
              this.QuietButton('编辑', () => {
                this.startEdit(m);
              })
            }
            this.QuietButton('删除', () => {
              this.removeMaterial(m);
            })
          }
          .width('100%')
          Text(this.materialBrief(m))
            .fontSize(12)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .padding({ top: 10, bottom: 6 })
        .border({ width: { top: 1 }, color: this.t().lineSoft })
      }, (m: MaterialEntry) => m.id)
    }
  }

  @Builder
  MatPreview() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          if (!this.matPreviewBusy) this.matPreviewOpen = false;
        })
      Column({ space: 8 }) {
        Row() {
          Text('材料收藏句子')
            .fontSize(16)
            .letterSpacing(1.5)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().inkStrong)
          Blank()
          Text('×')
            .fontSize(22)
            .fontColor(this.t().inkSoft)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              if (!this.matPreviewBusy) this.matPreviewOpen = false;
            })
        }
        .width('100%')
        Text(this.matPreviewName)
          .fontSize(11.5)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.matPreviewLoading) {
          Text('正在读取句子…')
            .fontSize(12.5)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .padding({ top: 20, bottom: 20 })
        } else {
          Row({ space: 4 }) {
            Text(`已选 ${this.matPick.length} / 共 ${this.matPreviewItems.length} 句`)
              .fontSize(11)
              .fontColor(this.t().seal)
            Blank()
            this.QuietButton('全选', () => {
              this.selectAllPreview();
            })
            this.QuietButton('清空', () => {
              this.clearPreview();
            })
          }
          .width('100%')
          if (this.matPreviewItems.length === 0) {
            Text('这份材料还没有切出句子。')
              .fontSize(12.5)
              .fontColor(this.t().inkSoft)
              .width('100%')
              .padding({ top: 18, bottom: 18 })
              .layoutWeight(1)
          } else {
            List({ space: 0 }) {
              LazyForEach(this.matPreviewDs, (t: string) => {
                ListItem() {
                  Column({ space: 0 }) {
                    Row({ space: 6 }) {
                      Text(this.matPick.includes(t) ? '✓' : '○')
                        .fontSize(13)
                        .fontColor(this.matPick.includes(t) ? this.t().seal : this.t().inkSoft)
                        .width(18)
                      Text(t)
                        .fontSize(13)
                        .lineHeight(24)
                        .fontColor(this.previewInLib(t) || this.previewExcluded(t)
                          ? this.t().inkSoft : this.t().ink)
                        .wordBreak(WordBreak.BREAK_ALL)
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 6 })
                    if (this.previewInLib(t) || this.previewExcluded(t)) {
                      Text(this.previewInLib(t) ? '已在句库' : '已在排除名单')
                        .fontSize(10)
                        .fontColor(this.t().inkSoft)
                        .width('100%')
                        .padding({ left: 24, bottom: 4 })
                    } else if (t.length > 200) {
                      Text(`长句 · ${t.length} 字`)
                        .fontSize(10)
                        .fontColor(this.t().seal)
                        .width('100%')
                        .padding({ left: 24, bottom: 4 })
                    }
                  }
                  .width('100%')
                  .border({ width: { top: 1 }, color: this.t().lineSoft })
                  .onClick(() => {
                    this.togglePreview(t);
                  })
                }
              }, (t: string) => t)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .clip(true)
          }
          Row({ space: 8 }) {
            this.GhostButton('取消', () => {
              if (!this.matPreviewBusy) this.matPreviewOpen = false;
            })
            this.GhostButton(this.matPreviewBusy ? '收藏中…' : '收藏选中', () => {
              this.collectPreview();
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
      }
      .width('90%')
      .height('82%')
      .padding(16)
      .backgroundColor(this.t().cardSolid)
      .borderRadius(this.t().radiusCard)
      .border({ width: 1, color: this.t().line })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MaterialForm() {
    TextInput({ text: this.matName, placeholder: '材料名' })
      .height(40)
      .fontSize(13.5)
      .fontColor(this.t().ink)
      .placeholderColor(this.t().inkSoft)
      .backgroundColor(this.t().inputBg)
      .borderRadius(this.t().radiusInput)
      .border({ width: 1, color: this.t().line })
      .onChange((v: string) => {
        this.matName = v;
      })
      .margin({ top: 6 })
    TextArea({ text: this.matText, placeholder: '粘贴文本（或选择 .txt / .md 文件）' })
      .height(104)
      .fontSize(14)
      .fontFamily(FONT_SERIF)
      .fontColor(this.t().ink)
      .placeholderColor(this.t().inkSoft)
      .backgroundColor(this.t().inputBg)
      .borderRadius(this.t().radiusInput)
      .border({ width: 1, color: this.t().line })
      .padding(12)
      .onChange((v: string) => {
        this.matText = v;
      })
      .margin({ top: 8 })
    Text('支持 UTF-8 / UTF-16 / GB18030 的 .txt 和 Markdown（.md / .markdown）文本。可以直接导入原始文本；句栖会按空行分句，单个换行按空格处理。')
      .fontSize(11)
      .lineHeight(19)
      .fontColor(this.t().inkSoft)
      .width('100%')
      .margin({ top: 6 })
    Flex({ wrap: FlexWrap.Wrap }) {
      this.GhostButton(this.matSaving ? '保存中…' : (this.matEditId.length > 0 ? '保存修改' : '存入材料库'), () => {
        if (!this.matSaving) {
          this.saveMaterial();
        }
      })
      this.GhostButton('选择 .txt / .md 文件', () => {
        if (!this.matSaving) {
          this.importTxt();
        }
      })
      if (this.matEditId.length > 0 && !this.matSaving) {
        this.QuietButton('取消编辑', () => {
          this.cancelEdit();
        })
      }
    }
    .width('100%')
    .margin({ top: 8 })
    if (this.matSaving) {
      Text(this.matProgress.length > 0 ? this.matProgress : '请稍等，正在保存…')
        .fontSize(11.5)
        .fontColor(this.t().seal)
        .width('100%')
        .margin({ top: 4 })
    }
    Text('材料只存在本机。检索时只抽原文并注明材料名，不编造。没有固定大小上限，但大文件（数 MB 以上）导入与检索都会明显变慢，建议按书拆分，并用空行分隔句子再导入。')
      .fontSize(11.5)
      .lineHeight(22)
      .fontColor(this.t().inkSoft)
      .width('100%')
      .margin({ top: 4 })
  }

  @Builder
  FindPanel() {
    Column({ space: 0 }) {
      Text('从我的材料找一句')
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
        .width('100%')
      Text('关键词用空格隔开，表示全部包含；留空则随机抽一句。')
        .fontSize(11.5)
        .fontColor(this.t().inkSoft)
        .width('100%')
        .margin({ top: 4, bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.Chip('全部材料', this.findPick.length === 0, () => {
          this.findPick = '';
        })
        ForEach(Store.get().data.materials, (m: MaterialEntry) => {
          this.Chip(m.name, this.findPick === m.id, () => {
            this.findPick = m.id;
          })
        }, (m: MaterialEntry) => `${m.id}-${this.findPick === m.id ? 'on' : 'off'}`)
      }
      .width('100%')
      TextInput({ text: this.findKw, placeholder: '关键词（可空）' })
        .height(40)
        .fontSize(13.5)
        .fontColor(this.t().ink)
        .placeholderColor(this.t().inkSoft)
        .backgroundColor(this.t().inputBg)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .onChange((v: string) => {
          this.findKw = v;
        })
        .margin({ top: 6 })
      Row() {
        this.GhostButton('找一句', () => {
          this.findOne();
        })
        this.QuietButton('收起', () => {
          this.showFind = false;
        })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.findText.length > 0) {
        Column({ space: 0 }) {
          Text(this.findText)
            .fontSize(16)
            .lineHeight(33)
            .fontFamily(FONT_SERIF)
            .fontColor(this.t().inkStrong)
            .wordBreak(WordBreak.BREAK_ALL)
            .width('100%')
          Text(`摘自《${this.findName}》 · 原文检索`)
            .fontSize(10.5)
            .letterSpacing(1)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 6, bottom: 8 })
          Row({ space: 2 }) {
            this.GhostButton('收入句库', () => {
              this.saveFound();
            })
            this.QuietButton('再找一句', () => {
              this.findOne();
            })
            this.QuietButton('不喜欢', () => {
              this.dislikeFound();
            })
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.t().card)
        .borderRadius(this.t().radiusInput)
        .border({ width: 1, color: this.t().line })
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ top: 10 })
  }

  @Builder
  MaterialsSection() {
    Column({ space: 0 }) {
      this.MaterialList()
      Divider().color(this.t().line).margin({ top: 8, bottom: 8 })
      this.MaterialForm()
      Divider().color(this.t().line).margin({ top: 12, bottom: 4 })
      Row() {
        Text('材料检索')
          .fontSize(13.5)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
        Blank()
        Text(this.showFind ? '收起' : '找一句')
          .fontSize(12.5)
          .fontColor(this.t().seal)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .onClick(() => {
            this.showFind = !this.showFind;
          })
      }
      .width('100%')
      if (this.showFind) {
        this.FindPanel()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
    .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
    .margin({ top: 10 })
  }

  build() {
    Stack() {
      Scroll() {
      Column() {
        this.Label('取一句')
        Column({ space: 0 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.GhostButton('从材料找一句', () => {
              if (Store.get().data.materials.length === 0) {
                this.showMaterials = true;
                this.getUIContext().getPromptAction().showToast({ message: '材料库还是空的，先粘贴一段文本' });
                return;
              }
              this.showMaterials = true;
              this.showFind = true;
            })
          }
          Text('收藏和材料检索都可以取一句；应用不自带句子，内容由你自己加入。')
            .fontSize(12.5)
            .lineHeight(23)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.FavHeader()
        if (this.showLib) {
          this.SearchBox('搜索：句子、出处或标签', this.qLib, (v: string) => {
            this.qLib = v;
          this.refreshLibDs();
          })
          Column({ space: 0 }) {
            if (this.filteredLibs().length === 0) {
              Column({ space: 6 }) {
                Text(this.qLib.length > 0 ? '没有找到' : '还没收藏')
                  .fontSize(14)
                  .fontFamily(FONT_SERIF)
                  .fontColor(this.t().inkStrong)
                Text(this.qLib.length > 0 ? '换个词试试。' : '还没有收藏。去材料库找一句；也可以自己写。')
                  .fontSize(12)
                  .lineHeight(22)
                  .fontColor(this.t().inkSoft)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ top: 28, bottom: 28 })
            } else {
              LazyForEach(this.libDs, (e: LibEntry) => {
                this.LibRow(e)
              }, (e: LibEntry) => e.id)
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 4, bottom: 8 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
        }

        this.ReplyHeader()
        if (this.showReplies) {
          Column({ space: 0 }) {
            if (this.replies.length === 0) {
              Text('还没有回信。抽到自己的句子时，可以回它一句。')
                .fontSize(12.5)
                .lineHeight(24)
                .fontColor(this.t().inkSoft)
                .width('100%')
            } else {
              ForEach(this.replies, (e: OwnEntry) => {
                this.ReplyRow(e)
              }, (e: OwnEntry) => e.id)
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 4, bottom: 8 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 10 })
        }

        this.MaterialHeader()
        if (this.showMaterials) {
          this.MaterialsSection()
        }

        this.DislikeHeader()
        if (this.showDislikes) {
          Column({ space: 0 }) {
            if (this.dislikes.length === 0) {
              Text('还没有排除任何句子。点「不喜欢」会记到这里，不再出现在抽签与收藏里。')
                .fontSize(12.5)
                .lineHeight(24)
                .fontColor(this.t().inkSoft)
                .width('100%')
            } else {
              this.SearchBox('搜索排除名单', this.qDis, (v: string) => {
                this.qDis = v;
              })
              ForEach(this.filteredDislikes(), (d: DislikeEntry) => {
                Column({ space: 0 }) {
                  Text(d.text)
                    .fontSize(14.5)
                    .lineHeight(28)
                    .fontFamily(FONT_SERIF)
                    .fontColor(this.t().ink)
                    .width('100%')
                  Row({ space: 6 }) {
                    Text(this.originName(d.origin))
                      .fontSize(10)
                      .fontColor(this.t().inkSoft)
                      .backgroundColor(this.t().card)
                      .border({ width: 1, color: this.t().line })
                      .borderRadius(999)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    this.QuietButton('撤销排除', () => {
                      this.undoDislike(d);
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding({ top: 10, bottom: 4 })
                .border({ width: { top: 1 }, color: this.t().lineSoft })
              }, (d: DislikeEntry) => d.text)
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 12, bottom: 8 })
          .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
          .borderRadius(this.t().radiusCard)
          .border({ width: 1, color: this.t().line })
          .margin({ top: 10 })
        }

        Blank()

        Text('句库数据只存在这台设备上')
          .fontSize(11.5)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 26 })
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
      if (this.matPreviewOpen) {
        this.MatPreview()
      }
    }
    .width('100%')
    .height('100%')
  }
}




