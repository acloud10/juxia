import { Store } from '../data/Store';
import { OwnEntry } from '../model/Types';
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { InnerScrollNav } from './InnerScrollNav';

@ComponentV2
export struct ReplySection {
  @Local ui: UiState = UiState.get();
  @Local open: boolean = false;
  @Local q: string = '';
  @Local limit: number = 20;
  @Local replies: OwnEntry[] = [];
  @Local contentH: number = 360;
  private scroll: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('ui.dataVersion')
  onData(monitor: IMonitor): void {
    this.reload();
  }

  private t(): Tokens {
    return getTokens(this.ui.skin, this.ui.dark);
  }

  private reload(): void {
    this.replies = Store.get().data.own
      .filter((e: OwnEntry) => e.kind === 'reply')
      .sort((a: OwnEntry, b: OwnEntry) => b.createdAt - a.createdAt);
  }

  private source(e: OwnEntry): string {
    const p: OwnEntry | undefined = Store.get().data.own.find((x: OwnEntry) => x.id === e.replyToId);
    return p === undefined ? '' : p.text;
  }

  private sourceLabel(e: OwnEntry): string {
    const p: OwnEntry | undefined = Store.get().data.own.find((x: OwnEntry) => x.id === e.replyToId);
    if (p === undefined) return '回的是';
    if (p.kind === 'encourage') return '回的是鼓励';
    return '回的是旧事';
  }

  private fromLabel(e: OwnEntry): string {
    if (e.replyFrom === 'revisit') return '回访回信';
    if (e.replyFrom === 'draw') return '抽签回信';
    return '回信';
  }

  private filtered(): OwnEntry[] {
    const kw: string = this.q.trim().toLowerCase();
    if (kw.length === 0) return this.replies;
    return this.replies.filter((e: OwnEntry) =>
      e.text.toLowerCase().includes(kw) || this.source(e).toLowerCase().includes(kw));
  }

  private paged(): OwnEntry[] {
    return this.filtered().slice(0, this.limit);
  }

  private remove(e: OwnEntry): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条回信？',
      message: '只会删除这条回信，不会删除它回的原句。删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        action: () => {
          Store.get().removeOwn(e.id);
          this.reload();
        }
      }
    });
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
    }
  }

  @Builder
  Header() {
    Row() {
      Text('回信')
        .fontSize(14)
        .letterSpacing(1.5)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Text(`${this.replies.length} 条`)
        .fontFamily(FONT_SANS)
        .fontSize(10)
        .fontColor(this.t().inkSoft)
        .backgroundColor(this.t().card)
        .border({ width: 1, color: this.t().line })
        .borderRadius(999)
        .padding({ left: 9, right: 9, top: 2, bottom: 2 })
        .margin({ left: 8 })
      Blank()
      Text(this.open ? '−' : '＋')
        .fontFamily(FONT_SANS)
        .fontSize(16)
        .fontColor(this.t().seal)
    }
    .width('100%')
    .padding({ top: 14, bottom: 8 })
    .onClick(() => { this.open = !this.open; })
  }

  @Builder
  SearchBox() {
    TextInput({ text: this.q, placeholder: '搜索回信或原句' })
      .height(40)
      .fontSize(13.5)
      .fontColor(this.t().ink)
      .placeholderColor(this.t().inkSoft)
      .backgroundColor(this.t().inputBg)
      .borderRadius(this.t().radiusInput)
      .border({ width: 1, color: this.t().line })
      .width('100%')
      .onChange((v: string) => {
        this.q = v;
        this.limit = 20;
      })
  }

  @Builder
  ReplyRow(e: OwnEntry) {
    Column({ space: 0 }) {
      Text(e.text)
        .fontFamily(FONT_SERIF)
        .fontSize(15)
        .lineHeight(28)
        .fontColor(this.t().ink)
        .width('100%')
      Row({ space: 6 }) {
        Text(this.fromLabel(e))
          .fontFamily(FONT_SANS)
          .fontSize(9.5)
          .fontColor(this.t().seal)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(999)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        if (this.source(e).length > 0) {
          Text(`${this.sourceLabel(e)}：${this.source(e)}`)
            .fontFamily(FONT_SANS)
            .fontSize(11.5)
            .fontColor(this.t().inkSoft)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        Text('删除')
          .fontFamily(FONT_SANS)
          .fontSize(11)
          .fontColor(this.t().inkSoft)
          .onClick(() => this.remove(e))
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
    .border({ width: { top: 1 }, color: this.t().lineSoft })
  }

  build() {
    Column({ space: 0 }) {
      this.Header()
      if (this.open) {
        if (this.replies.length === 0) {
          Text('还没有回信。抽到自己的句子时，可以回一句话。')
            .fontFamily(FONT_SANS)
            .fontSize(12.5)
            .lineHeight(24)
            .fontColor(this.t().inkSoft)
            .width('100%')
        } else {
          this.SearchBox()
          if (this.filtered().length === 0) {
            Text('没有找到。换个词，或清空搜索。')
              .fontFamily(FONT_SANS)
              .fontSize(12.5)
              .lineHeight(24)
              .fontColor(this.t().inkSoft)
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            Scroll(this.scroll) {
              Column({ space: 0 }) {
                ForEach(this.paged(), (e: OwnEntry) => {
                  this.ReplyRow(e)
                }, (e: OwnEntry) => `${e.id}-${e.text.length}`)
                if (this.filtered().length > this.limit) {
                  Text(`加载更多（还有 ${this.filtered().length - this.limit} 条）`)
                    .fontFamily(FONT_SANS)
                    .fontSize(12)
                    .fontColor(this.t().seal)
                    .padding({ top: 10, bottom: 10 })
                    .onClick(() => { this.limit += 20; })
                }
              }
              .width('100%')
              .onAreaChange((_old, area) => {
                this.contentH = Number(area.height);
              })
            }
            .height(this.contentH > 360 ? 360 : this.contentH)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            if (this.contentH > 360) {
              InnerScrollNav({
                onTop: () => { this.scroll.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 300, curve: Curve.EaseOut } }); },
                onBottom: () => { this.scroll.scrollEdge(Edge.Bottom); }
              })
            }
          }
        }
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 2, bottom: 8 })
    .backgroundColor(this.t().card).backdropBlur(this.ui.dark ? 0 : 10)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }
}
