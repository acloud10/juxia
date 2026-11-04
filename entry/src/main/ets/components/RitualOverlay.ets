// 句栖 · 抽签仪式：折纸 → 逐字揭示（经典 / 朴素）

import { RitualCtx, sealCN, todayStr } from '../model/Types';
import { Store } from '../data/Store';
import { Tokens, getTokens, FONT_SERIF } from '../theme/Theme';
import { scalePath, pathScale } from '../utils/PathScale';
import { UiState } from '../state/UiState';

const FLAP_CMDS: string[] = [
  'M 0 0 L 220 0 L 110 110 Z',
  'M 220 0 L 220 220 L 110 110 Z',
  'M 0 220 L 220 220 L 110 110 Z',
  'M 0 0 L 0 220 L 110 110 Z'
];

@ComponentV2
export struct RitualOverlay {
  @Local ui: UiState = UiState.get();
  @Param ctx: RitualCtx = new RitualCtx();
  @Event onClose: () => void = () => {};
  @Event onRedraw: () => void = () => {};
  @Event onBind: (id: string) => void = () => {};
  @Event onArchive: (id: string) => void = () => {};
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get appName(): string { return this.ui.appName; }
  @Local stage: string = 'packet'; // 可选：packet、reveal
  @Local open: boolean = false;
  @Local revealed: boolean = false;
  @Local showSource: boolean = false;
  @Local replyOpen: boolean = false;
  @Local replyText: string = '';
  @Local replyCount: number = 0;
  private timer: number = -1;

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  aboutToAppear(): void {
    const mode: string = Store.get().data.settings.ritualMode;
    if (mode === 'off') {
      this.stage = 'reveal';
      this.revealed = true;
    } else if (mode === 'short') {
      this.stage = 'reveal';
      this.timer = setTimeout(() => {
        this.revealed = true;
      }, 60);
    }
    if (this.ctx.entry !== null) {
      this.replyCount = Store.get().repliesOf(this.ctx.entry!.id).length;
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
  }

  private chars(): string[] {
    return this.ctx.text.split('');
  }

  private originOf(): string {
    if (this.ctx.origin.length > 0) return this.ctx.origin;
    if (this.ctx.type === 'own') return 'own';
    return 'material';
  }

  private accept(): void {
    if (this.ctx.type !== 'lib' || this.ctx.todayFlow) {
      Store.get().markDrew();
    }
    this.onClose();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  private saveLib(): void {
    const origin: string = this.originOf();
    const ok: boolean = Store.get().addLib(this.ctx.text, this.ctx.source, origin, this.ctx.tag);
    if (!ok) {
      this.toast('句库里已有这句');
    }
    if (this.ctx.todayFlow) {
      Store.get().markDrew();
    }
    this.onClose();
  }

  private openReply(): void {
    this.replyText = '';
    this.replyOpen = true;
  }

  private saveReply(): void {
    if (this.ctx.entry === null) return;
    const text: string = this.replyText.trim();
    if (text.length === 0) {
      this.toast('先写一句再回');
      return;
    }
    const ok: boolean = Store.get().addReply(this.ctx.entry!.id, text);
    if (!ok) return;
    this.replyCount = Store.get().repliesOf(this.ctx.entry!.id).length;
    this.replyText = '';
    this.replyOpen = false;
    this.toast('回好了，下次抽到会一起出现');
  }

  private dislike(): void {
    const origin: string = this.originOf();
    Store.get().addDislike(this.ctx.text, this.ctx.source, origin);
    this.toast('已加入排除名单，不会再出现');
    this.onClose();
  }

  private redraw(): void {
    this.onClose();
    this.onRedraw();
  }

  private tapPacket(): void {
    if (this.open) return;
    this.open = true;
    this.timer = setTimeout(() => {
      this.stage = 'reveal';
      setTimeout(() => {
        this.revealed = true;
      }, 40);
    }, 1150);
  }

  private skip(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.open = true;
    this.stage = 'reveal';
    setTimeout(() => {
      this.revealed = true;
    }, 40);
  }

  private flapFill(index: number): string {
    if (this.skin === 'plain') {
      return this.dark ? '#3a3327' : this.t().cardSolid;
    }
    const cols: string[] = ['#fdf9ee', '#f9f5ea', '#f7f2e6', '#fbf6ec'];
    return cols[index];
  }

  @Builder
  Flap(index: number) {
    Shape() {
      Path()
        .commands(scalePath(FLAP_CMDS[index], pathScale(220, 220)))
        .fill(this.flapFill(index))
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .width(`${this.getUIContext().vp2px(220)}px`)
    .height(`${this.getUIContext().vp2px(220)}px`)
    .rotate({
      x: (index === 0 || index === 2) ? 1 : 0,
      y: (index === 1 || index === 3) ? 1 : 0,
      z: 0,
      angle: this.open ? (index === 2 || index === 1 ? -178 : 178) : 0,
      centerX: index === 1 ? 220 : (index === 3 ? 0 : 110),
      centerY: index === 0 ? 0 : (index === 2 ? 220 : 110),
      perspective: 900
    })
    .animation({ duration: 850, delay: index * 80, curve: Curve.EaseInOut })
  }

  @Builder
  PacketStage() {
    Stack() {
      Column()
        .width(220)
        .height(220)
        .borderRadius(4)
        .backgroundColor(this.skin === 'plain' ? (this.dark ? '#3a3327' : this.t().cardSolid) : '#fdf9ee')
        .border({ width: 1, color: this.dark ? '#44e9e4d5' : '#1a5a5032' })
        .shadow({ radius: 34, color: this.dark ? '#66000000' : '#3d5a5032', offsetY: 12 })

      this.Flap(0)
      this.Flap(1)
      this.Flap(2)
      this.Flap(3)

      Column()
        .width(1)
        .height(220)
        .backgroundColor(this.dark ? '#33e9e4d5' : '#175a5032')
        .opacity(this.open ? 0 : 1)
        .animation({ duration: 300 })
      Column()
        .width(220)
        .height(1)
        .backgroundColor(this.dark ? '#33e9e4d5' : '#175a5032')
        .opacity(this.open ? 0 : 1)
        .animation({ duration: 300 })

      Text('展 开')
        .fontSize(14)
        .fontFamily(FONT_SERIF)
        .letterSpacing(8)
        .fontColor(this.skin === 'plain' ? this.t().inkSoft : '#6b5a5032')
        .opacity(this.open ? 0 : 1)
        .animation({ duration: 300 })
    }
    .width(220)
    .height(220)
    .onClick(() => {
      this.tapPacket();
    })
  }

  @Builder
  CharLine() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.chars(), (ch: string, index: number) => {
        Text(ch)
          .fontSize(this.skin === 'plain' ? this.plainFontSize() : 22)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
          .lineHeight(this.skin === 'plain' ? this.plainFontSize() * 1.85 : 46)
          .opacity(this.revealed ? 1 : 0)
          .translate({ y: this.revealed ? 0 : 8 })
          .blur(this.revealed ? 0 : 2)
          .animation({ duration: 500, delay: Math.min(index * 26, 1050), curve: Curve.EaseOut })
      }, (ch: string, index: number) => `${index}${ch}`)
    }
    .width(this.skin === 'plain' ? 250 : '86%')
  }

  private plainFontSize(): number {
    const n: number = this.chars().length;
    let f: number = Math.max(13, Math.min(21, 22 - n * 0.055));
    return Math.round(f);
  }

  private isPunct(ch: string): boolean {
    return '，。！？；：、'.indexOf(ch) >= 0;
  }

  private plainWidth(): number {
    const chars: number = this.chars().length;
    const maxW: number = 330;
    const rvH: number = 330;
    let f: number = Math.max(13, Math.min(21, 22 - chars * 0.055));
    let w: number = maxW;
    for (let i = 0; i < 5; i++) {
      const per: number = Math.max(1, Math.floor(rvH / (f * 1.85)));
      w = Math.min(maxW, Math.ceil(chars / per) * f * 1.85 + 54);
      if (w < maxW) break;
      f = Math.max(10, f * 0.92);
    }
    return Math.round(Math.max(196, w));
  }

  private vColumns(): string[][] {
    const chars: string[] = this.chars();
    const f: number = this.plainFontSize();
    const maxRows: number = Math.max(1, Math.floor(300 / (f * 1.85)));
    const cols: number = Math.max(1, Math.ceil(chars.length / maxRows));
    const per: number = Math.ceil(chars.length / cols);
    const chunks: string[][] = [];
    let start: number = 0;
    for (let c = 0; c < cols; c++) {
      let end: number = Math.min(chars.length, start + per);
      if (c < cols - 1) {
        while (end > start + 1 && '，。！？；：、'.indexOf(chars[end]) >= 0) {
          end--;
        }
      }
      if (end <= start) end = Math.min(chars.length, start + 1);
      chunks.push(chars.slice(start, end));
      start = end;
      if (start >= chars.length) break;
    }
    if (start < chars.length && chunks.length > 0) {
      const last: string[] = chunks[chunks.length - 1];
      chunks[chunks.length - 1] = last.concat(chars.slice(start));
    }
    const out: string[][] = [];
    for (let c = chunks.length - 1; c >= 0; c--) {
      out.push(chunks[c]);
    }
    return out;
  }

  @Builder
  PrimaryAction(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .letterSpacing(1.5)
      .fontColor(this.t().bg)
      .backgroundColor(this.t().ink)
      .borderRadius(999)
      .padding({ left: 26, right: 26, top: 12, bottom: 12 })
      .onClick(action)
  }

  @Builder
  QuietAction(label: string, action: () => void) {
    Text(label)
      .fontSize(12.5)
      .letterSpacing(1.2)
      .fontColor(this.t().inkSoft)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(action)
  }

  @Builder
  Actions() {
    Column({ space: 8 }) {
      if (this.ctx.type === 'own' && this.replyCount > 0) {
        Text(`你回过它 ${this.replyCount} 句`)
          .fontSize(11)
          .letterSpacing(1)
          .fontColor(this.t().inkSoft)
      }
      if (this.ctx.type === 'own' && this.ctx.entry !== null && this.ctx.entry!.kind === 'encourage') {
        this.PrimaryAction('收下', () => {
          this.accept();
        })
        Row({ space: 4 }) {
          this.QuietAction('回它一句', () => {
            this.openReply();
          })
          this.QuietAction('为它选一件旧事', () => {
            if (this.ctx.entry !== null) {
              this.onBind(this.ctx.entry!.id);
            }
          })
          this.QuietAction('不再参与抽签', () => {
            if (this.ctx.entry !== null) {
              this.onArchive(this.ctx.entry!.id);
            }
          })
        }
      } else if (this.ctx.type === 'own' && this.ctx.entry !== null && this.ctx.entry!.kind === 'wound') {
        Text('还没准备好就放回去，完全没关系。')
          .fontSize(12)
          .fontColor(this.t().inkSoft)
          .margin({ bottom: 4 })
        this.PrimaryAction('先放回去', () => {
          this.accept();
        })
        this.QuietAction('回它一句', () => {
          this.openReply();
        })
        this.QuietAction('标记已解决 / 已放下', () => {
          if (this.ctx.entry !== null) {
            this.onArchive(this.ctx.entry!.id);
          }
        })
      } else {
        this.PrimaryAction('收入句库', () => {
          this.saveLib();
        })
        Row({ space: 4 }) {
          this.QuietAction('先收下，不入库', () => {
            this.accept();
          })
          this.QuietAction('不喜欢', () => {
            this.dislike();
          })
          this.QuietAction('换一句', () => {
            this.redraw();
          })
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LongReveal() {
    Column({ space: 14 }) {
      Text(this.ctx.badge)
        .fontSize(10)
        .letterSpacing(3.4)
        .fontColor(this.t().seal)
      Scroll() {
        Text(this.ctx.text)
          .fontSize(18)
          .lineHeight(32)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
      }
      .width('88%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      if (this.showSource) {
        Text(this.ctx.source)
          .fontSize(12)
          .fontColor(this.t().ink)
          .width('88%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  RevealStage() {
    Stack() {
      if (this.chars().length > 80) {
        this.LongReveal()
      } else if (this.skin === 'plain') {
        this.PlainPaper()
      } else {
        this.ClassicReveal()
        Text('「')
          .fontSize(96)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().seal)
          .opacity(0.1)
          .position({ x: 24, y: 120 })
        Text('」')
          .fontSize(96)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().seal)
          .opacity(0.1)
          .position({ x: 270, y: 560 })
      }

      Column() {
        Row() {
          Blank()
          Text(`出处 · ${this.ctx.tag}`)
            .fontSize(10.5)
            .letterSpacing(1.6)
            .fontColor(this.t().inkSoft)
            .backgroundColor(this.t().card)
            .border({ width: 1, color: this.t().line })
            .borderRadius(999)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.showSource = !this.showSource;
            })
        }
        .width('100%')
        .padding({ right: 20, top: 54 })
        if (this.showSource) {
          Row() {
            Blank()
            Text(this.ctx.source)
              .fontSize(12)
              .fontColor(this.t().ink)
              .padding({ right: 20, top: 8 })
          }
          .width('100%')
        }
        Blank()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      Column() {
        Blank()
        this.Actions()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .padding({ bottom: 34 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ClassicReveal() {
    Column() {
      Text(this.ctx.badge)
        .fontSize(10)
        .letterSpacing(3.4)
        .fontColor(this.t().seal)
        .margin({ bottom: 30 })
      this.CharLine()
      if (this.showSource) {
        Text(this.ctx.source)
          .fontSize(12)
          .fontColor(this.t().ink)
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 30, right: 30 })
  }

  @Builder
  PlainPaper() {
    Stack() {
      Column()
        .width(this.plainWidth())
        .height(420)
        .borderRadius(8)
        .border({ width: 1, color: this.t().line })
        .linearGradient({
          angle: 180,
          colors: [[this.t().cardSolid, 0.0], [this.t().bg, 1.0]]
        })
        .shadow({ radius: 28, color: this.t().shadowColor, offsetY: 10 })

      Column()
        .width(this.plainWidth() * 0.58)
        .height(10)
        .borderRadius(3)
        .linearGradient({
          angle: 180,
          colors: [['#c14e33', 0.0], [this.t().seal, 1.0]]
        })
        .position({ x: this.plainWidth() * 0.21, y: 12 })

      Row({ space: 2 }) {
        ForEach(this.vColumns(), (col: string[], ci: number) => {
          Column() {
            ForEach(col, (ch: string, i: number) => {
              Text(ch)
                .fontSize(this.plainFontSize())
                .fontFamily(FONT_SERIF)
                .fontColor(this.t().ink)
                .lineHeight(this.plainFontSize() * 1.85)
                .opacity(this.revealed ? 1 : 0)
                .translate({
                  x: 0,
                  y: this.revealed ? 0 : 8
                })
                .animation({
                  duration: 500,
                  delay: Math.min((ci * 6 + i) * 26, 1050),
                  curve: Curve.EaseOut
                })
            }, (ch: string, i: number) => `${ci}-${i}-${ch}`)
          }
          .width(this.plainFontSize() * 1.18)
        }, (col: string[], ci: number) => `${ci}`)
      }
      .direction(Direction.Ltr)
      .width(this.plainWidth() - 40)
      .height(300)
      .alignItems(VerticalAlign.Top)
      .position({ x: 20, y: 50 })
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(this.appName.slice(0, 2))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.t().seal)
          .letterSpacing(1)
        Text(sealCN(todayStr()))
          .fontSize(5.5)
          .fontColor(this.t().seal)
          .opacity(0.9)
      }
      .border({ width: 1.5, color: this.t().seal })
      .borderRadius(2)
      .padding({ left: 5, right: 5, top: 4, bottom: 4 })
      .rotate({ angle: -4 })
      .position({ x: 12, y: 356 })
    }
    .width(this.plainWidth())
    .height(420)
    .align(Alignment.Center)
  }

  @Builder
  ReplySheet() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.replyOpen = false;
        })
      Column({ space: 10 }) {
        Text('回它一句')
          .fontSize(17)
          .letterSpacing(2)
          .fontFamily(FONT_SERIF)
          .fontColor(this.t().inkStrong)
          .width('100%')
        Text(this.ctx.text)
          .fontSize(12)
          .lineHeight(22)
          .fontColor(this.t().inkSoft)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        TextArea({ text: this.replyText, placeholder: '不用写完整，回它一句就好' })
          .height(110)
          .fontSize(14)
          .fontColor(this.t().ink)
          .placeholderColor(this.t().inkSoft)
          .backgroundColor(this.t().inputBg)
          .borderRadius(this.t().radiusInput)
          .border({ width: 1, color: this.t().line })
          .onChange((v: string) => {
            this.replyText = v;
          })
        Row({ space: 8 }) {
          this.QuietAction('取消', () => {
            this.replyOpen = false;
          })
          this.PrimaryAction('回它', () => {
            this.saveReply();
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('86%')
      .padding(18)
      .backgroundColor(this.t().cardSolid)
      .borderRadius(this.t().radiusCard)
      .border({ width: 1, color: this.t().line })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      if (this.stage === 'packet') {
        this.PacketStage()
      } else {
        this.RevealStage()
      }

      if (this.stage === 'packet') {
        Column() {
          Row() {
            Blank()
            Text('跳过 ›')
              .fontSize(11.5)
              .letterSpacing(2)
              .fontColor(this.t().inkSoft)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: this.t().line })
              .borderRadius(999)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                this.skip();
              })
          }
          .width('100%')
          .padding({ right: 20, top: 54 })
          Blank()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      if (this.replyOpen) {
        this.ReplySheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
    .alignContent(Alignment.Center)
  }
}


