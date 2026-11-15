// 句栖 · 背景设置面板（从 SettingsPage 抽出的独立组件）
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Store } from '../data/Store';
import { BackgroundService } from '../services/BackgroundService';
import { BackgroundStyle, BgImageStyle } from '../model/BackgroundStyle';
import { Tokens, getTokens, FONT_SANS, FONT_SERIF } from '../theme/Theme';
import { UiState } from '../state/UiState';

@ComponentV2
export struct BackgroundSettingsPanel {
  @Param skin: string = 'classic';
  @Param dark: boolean = false;
  @Local editKey: string = 'light';
  @Local advanced: boolean = false;
  @Local busy: boolean = false;
  @Local expanded: boolean = false;
  @Local ui: UiState = UiState.get();
  @Local bgState: BackgroundStyle = new BackgroundStyle();
  @Local sliderRev: number = 0;
  @Local glowUi: number = 100;
  @Local grainUi: number = 100;
  @Local brightUi: number = 1.0;
  @Local blurUi: number = 0;
  @Local scrimUi: number = 38;
  @Local ditherUi: number = 100;

  aboutToAppear(): void {
    this.bgState = Store.get().data.settings.background;
    this.glowUi = this.bgState.glowValue;
    this.grainUi = this.bgState.grainValue;
    this.ditherUi = this.bgState.ditherValue;
    this.selectKey(this.effectiveKey());
  }

  private effectiveKey(): string {
    const b = this.bgState;
    if (this.ui.skin === 'plain') {
      if (this.ui.dark && b.darkPlain.path.length > 0) return 'darkPlain';
      if (!this.ui.dark && b.lightPlain.path.length > 0) return 'lightPlain';
    }
    return this.ui.dark ? 'dark' : 'light';
  }

  private applyTheme(mode: string): void {
    const st = Store.get();
    st.data.settings.theme = mode;
    st.saveKv();
    this.ui.themeMode = mode;
    this.ui.dark = mode === 'dark';
  }

  private applySkin(skin: string): void {
    const st = Store.get();
    st.data.settings.skin = skin;
    st.saveKv();
    this.ui.skin = skin;
  }

  private ensurePlain(key: string): void {
    const b = this.bgState;
    const src = key === 'lightPlain' ? b.light : b.dark;
    const dst = key === 'lightPlain' ? b.lightPlain : b.darkPlain;
    if (dst.path.length === 0 && src.path.length > 0) {
      dst.path = src.path;
      dst.brightness = src.brightness;
      dst.blur = src.blur;
      dst.scrim = src.scrim;
      dst.glowValue = src.glowValue;
      dst.grainValue = src.grainValue;
      dst.ditherValue = src.ditherValue;
    }
  }

  private activateKey(key: string): void {
    if (key === 'light' || key === 'dark') {
      const wasPlain: boolean = this.ui.skin === 'plain';
      this.applyTheme(key);
      this.applySkin('classic');
      this.selectKey(key);
      if (wasPlain) {
        try {
          this.getUIContext().getPromptAction().showToast({
            message: '已切回经典；朴素单独调节请点“高级”'
          });
        } catch (e) {
        }
      }
      return;
    }
    if (key === 'lightPlain' || key === 'darkPlain') {
      this.ensurePlain(key);
      this.applySkin('plain');
      this.applyTheme(key === 'lightPlain' ? 'light' : 'dark');
    }
    this.selectKey(key);
  }

  private selectKey(key: string): void {
    this.editKey = key;
    const s = this.styleOf(key);
    this.brightUi = s.brightness;
    this.blurUi = s.blur;
    this.scrimUi = s.scrim * 100;
    this.glowUi = s.glowValue;
    this.grainUi = s.grainValue;
    this.ditherUi = s.ditherValue;
    if (key === this.effectiveKey()) {
      this.ui.bgBrightness = s.brightness;
      this.ui.bgBlur = s.blur;
      this.ui.bgScrim = s.scrim;
      this.ui.bgGlow = s.glowValue;
      this.ui.bgGrain = s.grainValue;
      this.ui.bgDither = s.ditherValue;
    }
  }

  @Monitor('ui.dataVersion')
  onBgSaved(): void {
    this.bgState = Store.get().data.settings.background;
    this.sliderRev = this.sliderRev + 1;
  }

  @Monitor('ui.bgSavedRev')
  onBgFileSaved(): void {
    this.bgState = Store.get().data.settings.background;
    this.sliderRev = this.sliderRev + 1;
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private bg(): BackgroundStyle {
    return Store.get().data.settings.background;
  }

  private styleOf(key: string): BgImageStyle {
    const b = this.bg();
    if (key === 'dark') return b.dark;
    if (key === 'lightClassic') return b.lightClassic;
    if (key === 'lightPlain') return b.lightPlain;
    if (key === 'darkClassic') return b.darkClassic;
    if (key === 'darkPlain') return b.darkPlain;
    return b.light;
  }

  private async choose(key: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri: string = await BackgroundService.pick(ctx);
      if (uri.length === 0) return;
      AppStorage.setOrCreate('bgCropSrc', uri);
      AppStorage.setOrCreate('bgCropKey', key);
      AppStorage.setOrCreate('bgCropSkin', this.ui.skin);
      AppStorage.setOrCreate('bgCropDark', this.ui.dark);
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/BackgroundCropPage'
      }).catch(() => {});
    } catch (e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '选择图片失败' }); } catch (e2) {}
    } finally {
      this.busy = false;
    }
  }

  private cleanupFiles(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const b = Store.get().data.settings.background;
      const keep: string[] = [b.light.path, b.dark.path, b.lightPlain.path, b.darkPlain.path]
        .filter((p: string) => p.length > 0);
      BackgroundService.cleanup(ctx, keep);
    } catch (e) {
    }
  }

  private clear(key: string): void {
    const s = this.styleOf(key);
    if (s.path.length > 0) {
      s.path = '';
      const b = Store.get().data.settings.background;
      const anyImage: boolean = b.light.path.length > 0 || b.dark.path.length > 0 ||
        b.lightClassic.path.length > 0 || b.lightPlain.path.length > 0 ||
        b.darkClassic.path.length > 0 || b.darkPlain.path.length > 0;
      if (!anyImage) {
        b.glowValue = 100;
        b.glow = 'normal';
        b.grainValue = 100;
        b.grain = 'normal';
        this.glowUi = 100;
        this.grainUi = 100;
        this.ui.bgGlow = 100;
        this.ui.bgGrain = 100;
      }
      Store.get().saveSettings();
      this.cleanupFiles();
      UiState.get().bgSavedRev = UiState.get().bgSavedRev + 1;
      try { this.getUIContext().getPromptAction().showToast({ message: '已移除背景' }); } catch (e) {}
    }
  }

  private updateNum(key: string, field: string, v: number): void {
    console.info('juxia-slider key=' + key + ' field=' + field + ' v=' + v.toFixed(3));
    const s = this.styleOf(key);
    if (field === 'brightness') s.brightness = v;
    else if (field === 'blur') s.blur = v;
    else if (field === 'scrim') s.scrim = v;
    const effective: boolean = key === this.effectiveKey();
    if (field === 'brightness') {
      this.brightUi = v;
      if (effective) this.ui.bgBrightness = v;
    } else if (field === 'blur') {
      this.blurUi = v;
      if (effective) this.ui.bgBlur = v;
    } else if (field === 'scrim') {
      this.scrimUi = v * 100;
      if (effective) this.ui.bgScrim = v;
    }
    Store.get().saveSettings();
    this.sliderRev = this.sliderRev + 1;
  }

  private modeValue(field: string): string {
    return field === 'glow' ? this.bg().glow : this.bg().grain;
  }

  @Builder
  BgRow(label: string, key: string, rev: number) {
    Row({ space: 10 }) {
      if (this.styleOf(key).path.length > 0) {
        Image('file://' + this.styleOf(key).path)
          .id('bgrow-' + key + '-' + rev)
          .width(64)
          .height(42)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .border({ width: 1, color: this.t().line })
      } else {
        Column()
          .width(64)
          .height(42)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(8)
      }
      Text(label)
        .fontFamily(FONT_SANS)
        .fontSize(13)
        .fontColor(this.t().ink)
        .layoutWeight(1)
      if (this.styleOf(key).path.length > 0) {
        Text('移除')
          .fontSize(11)
          .fontColor(this.t().inkSoft)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => this.clear(key))
      }
      Text(this.styleOf(key).path.length > 0 ? '更换' : '选择')
        .fontSize(12)
        .fontColor(this.t().sealInk)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.t().seal)
        .borderRadius(999)
        .onClick(() => {
          this.activateKey(key);
          this.choose(key);
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  BgCell(label: string, key: string, rev: number) {
    Column({ space: 4 }) {
      if (this.styleOf(key).path.length > 0) {
        Image('file://' + this.styleOf(key).path)
          .id('bgcell-' + key + '-' + rev)
          .width('100%')
          .height(52)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
      } else {
        Column()
          .width('100%')
          .height(52)
          .backgroundColor(this.t().card)
          .border({ width: 1, color: this.t().line })
          .borderRadius(8)
      }
      Text(label).fontSize(11).fontColor(this.t().ink).width('100%')
      Row({ space: 10 }) {
        Text('选择')
          .fontSize(10)
          .fontColor(this.editKey === key ? this.t().sealInk : this.t().inkSoft)
          .onClick(() => { this.activateKey(key); })
        if (this.styleOf(key).path.length > 0) {
          Text('移除')
            .fontSize(10)
            .fontColor(this.t().inkSoft)
            .onClick(() => { this.clear(key); })
        }
        Blank()
        Text(this.styleOf(key).path.length > 0 ? '换图' : '选图')
          .fontSize(10)
          .fontColor(this.t().inkSoft)
          .onClick(() => {
            this.activateKey(key);
            this.choose(key);
          })
      }
      .width('100%')
      .padding({ top: 4 })
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(this.editKey === key ? this.t().seal : this.t().card)
    .borderRadius(10)
    .border({ width: 1, color: this.t().line })
  }

  @Builder
  SliderRow(label: string, field: string, min: number, max: number, step: number, rev: number) {
    Column({ space: 2 }) {
      Row() {
        Text(label).fontFamily(FONT_SANS).fontSize(12).fontColor(this.t().inkSoft)
        Blank()
        Text((field === 'brightness'
          ? this.brightUi.toFixed(2)
          : (field === 'blur'
            ? Math.round(this.blurUi).toString()
            : Math.round(this.scrimUi).toString() + '%')) + (rev < 0 ? '?' : ''))
          .fontFamily(FONT_SANS).fontSize(11).fontColor(this.t().inkSoft)
      }
      .width('100%')
      Slider({
        value: field === 'brightness' ? this.brightUi
          : (field === 'blur' ? this.blurUi : this.scrimUi),
        min: min,
        max: max,
        step: step
      })
        .width('100%')
        .selectedColor(this.t().seal)
        .onChange((v: number) => {
          this.updateNum(this.editKey, field, field === 'scrim' ? v / 100 : v);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  LevelSlider(label: string, field: string, rev: number) {
    Column({ space: 2 }) {
      Row() {
        Text(label).fontSize(12).fontColor(this.t().inkSoft)
        Blank()
        Text(`${Math.round(field === 'glow' ? this.styleOf(this.editKey).glowValue : this.styleOf(this.editKey).grainValue)}%` + (rev < 0 ? '?' : ''))
          .fontSize(11).fontColor(this.t().inkSoft)
      }
      .width('100%')
      Slider({
        value: field === 'glow' ? this.styleOf(this.editKey).glowValue : this.styleOf(this.editKey).grainValue,
        min: 0,
        max: field === 'grain' ? 150 : 100,
        step: 1
      })
        .width('100%')
        .selectedColor(this.t().seal)
        .onChange((v: number) => {
          console.info('juxia-level field=' + field + ' v=' + v.toFixed(1));
          const s = this.styleOf(this.editKey);
          const effective: boolean = this.editKey === this.effectiveKey();
          if (field === 'glow') {
            this.glowUi = v;
            s.glowValue = v;
            if (effective) this.ui.bgGlow = v;
          } else {
            this.grainUi = v;
            s.grainValue = v;
            if (effective) this.ui.bgGrain = v;
          }
          Store.get().saveSettings();
          this.sliderRev = this.sliderRev + 1;
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  DitherRow() {
    Column({ space: 2 }) {
      Row() {
        Text('深色 dither').fontSize(12).fontColor(this.t().inkSoft)
        Blank()
        Text(`${Math.round(this.styleOf(this.editKey).ditherValue)}%`)
          .fontSize(11).fontColor(this.t().inkSoft)
      }
      .width('100%')
      Slider({ value: this.styleOf(this.editKey).ditherValue, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor(this.t().seal)
        .onChange((v: number) => {
          const s = this.styleOf(this.editKey);
          s.ditherValue = v;
          this.ditherUi = v;
          if (this.editKey === this.effectiveKey()) this.ui.bgDither = v;
          Store.get().saveSettings();
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  ModeChip(label: string, value: string, field: string) {
    Text(label)
      .fontFamily(FONT_SANS)
      .fontSize(11)
      .fontColor(this.modeValue(field) === value ? this.t().bg : this.t().inkSoft)
      .backgroundColor(this.modeValue(field) === value ? this.t().ink : this.t().card)
      .borderRadius(999)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => {
        if (field === 'glow') this.bg().glow = value;
        else this.bg().grain = value;
        Store.get().saveSettings();
      })
  }

  @Builder
  EditChip(label: string, key: string) {
    Text(label)
      .fontFamily(FONT_SANS)
      .fontSize(11)
      .fontColor(this.editKey === key ? this.t().bg : this.t().inkSoft)
      .backgroundColor(this.editKey === key ? this.t().ink : this.t().card)
      .borderRadius(999)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => { this.activateKey(key); })
  }

  build() {
    Column({ space: 8 }) {
      Text(`${this.ui.dataVersion}`)
        .width(0)
        .height(0)
        .opacity(0)
      Row() {
        Text('自定义背景')
          .fontFamily(FONT_SERIF)
          .fontSize(16)
          .fontColor(this.t().ink)
        Blank()
        Text(this.expanded ? '收起' : '展开')
          .fontSize(12)
          .fontColor(this.t().inkSoft)
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
      .onClick(() => { this.expanded = !this.expanded; })

      if (this.expanded && this.ui.dataVersion >= 0 && this.sliderRev >= 0) {
        this.BgRow('经典浅色', 'light', this.sliderRev)
        this.BgRow('经典深色', 'dark', this.sliderRev)

        Row({ space: 8 }) {
          Text('选择')
            .fontSize(12)
            .fontColor(this.t().inkSoft)
          this.EditChip('浅色', 'light')
          this.EditChip('深色', 'dark')
          Blank()
          Text(this.advanced ? '收起高级' : '高级')
            .fontSize(12)
            .fontColor(this.t().inkSoft)
            .onClick(() => { this.advanced = !this.advanced; })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })

        this.SliderRow('亮度', 'brightness', 0, 1.5, 0.01, this.sliderRev)
        this.SliderRow('模糊', 'blur', 0, 100, 1, this.sliderRev)
        this.SliderRow('遮罩', 'scrim', 0, 100, 1, this.sliderRev)

        this.LevelSlider('氛围光', 'glow', this.sliderRev)
        this.LevelSlider('纸纹', 'grain', this.sliderRev)

        if (this.editKey === 'dark') {
          this.DitherRow()
        }

        if (this.advanced) {
          Text('额外覆盖朴素浅色 / 深色；不设置时与上面的经典浅色 / 深色一致')
            .fontSize(11)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 4 })
          Row({ space: 8 }) {
            this.BgCell('朴素浅色', 'lightPlain', this.sliderRev)
            this.BgCell('朴素深色', 'darkPlain', this.sliderRev)
          }
          .width('100%')
          if (this.editKey === 'darkPlain') {
            this.DitherRow()
          }
        }
      }
    }
    .width('100%')
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean) => {
      if (isVisible) {
        this.bgState = Store.get().data.settings.background;
        this.glowUi = this.bgState.glowValue;
        this.grainUi = this.bgState.grainValue;
        this.ditherUi = this.bgState.ditherValue;
        this.selectKey(this.effectiveKey());
        this.cleanupFiles();
        this.sliderRev = this.sliderRev + 1;
      }
    })
    .padding(16)
    .backgroundColor(this.t().card)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }
}
