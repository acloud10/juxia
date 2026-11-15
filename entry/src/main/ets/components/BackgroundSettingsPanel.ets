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
      AppStorage.setOrCreate('bgCropSkin', this.skin);
      AppStorage.setOrCreate('bgCropDark', this.dark);
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/BackgroundCropPage'
      }).catch(() => {});
    } catch (e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '选择图片失败' }); } catch (e2) {}
    } finally {
      this.busy = false;
    }
  }

  private clear(key: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const s = this.styleOf(key);
    if (s.path.length > 0) {
      BackgroundService.remove(ctx, s.path);
      s.path = '';
      Store.get().saveSettings();
      try { this.getUIContext().getPromptAction().showToast({ message: '已移除背景' }); } catch (e) {}
    }
  }

  private updateNum(key: string, field: string, v: number): void {
    const s = this.styleOf(key);
    if (field === 'brightness') s.brightness = v;
    else if (field === 'blur') s.blur = v;
    else if (field === 'scrim') s.scrim = v;
    Store.get().saveSettings();
  }

  private modeValue(field: string): string {
    return field === 'glow' ? this.bg().glow : this.bg().grain;
  }

  @Builder
  BgRow(label: string, key: string) {
    Row({ space: 10 }) {
      if (this.styleOf(key).path.length > 0) {
        Image('file://' + this.styleOf(key).path)
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
        .onClick(() => this.choose(key))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  BgCell(label: string, key: string) {
    Column({ space: 4 }) {
      if (this.styleOf(key).path.length > 0) {
        Image('file://' + this.styleOf(key).path)
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
      Row({ space: 4 }) {
        Text('调整')
          .fontSize(10)
          .fontColor(this.editKey === key ? this.t().sealInk : this.t().inkSoft)
          .onClick(() => { this.editKey = key; })
        Blank()
        Text(this.styleOf(key).path.length > 0 ? '换图' : '选图')
          .fontSize(10)
          .fontColor(this.t().sealInk)
          .onClick(() => this.choose(key))
      }
      .width('100%')
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(this.editKey === key ? this.t().seal : this.t().card)
    .borderRadius(10)
    .border({ width: 1, color: this.t().line })
  }

  @Builder
  SliderRow(label: string, field: string, min: number, max: number, step: number) {
    Column({ space: 2 }) {
      Row() {
        Text(label).fontFamily(FONT_SANS).fontSize(12).fontColor(this.t().inkSoft)
        Blank()
        Text(field === 'brightness'
          ? this.styleOf(this.editKey).brightness.toFixed(2)
          : (field === 'blur'
            ? Math.round(this.styleOf(this.editKey).blur).toString()
            : Math.round(this.styleOf(this.editKey).scrim * 100).toString() + '%'))
          .fontFamily(FONT_SANS).fontSize(11).fontColor(this.t().inkSoft)
      }
      .width('100%')
      Slider({
        value: field === 'brightness' ? this.styleOf(this.editKey).brightness
          : (field === 'blur' ? this.styleOf(this.editKey).blur : this.styleOf(this.editKey).scrim * 100),
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
  LevelSlider(label: string, field: string) {
    Column({ space: 2 }) {
      Row() {
        Text(label).fontSize(12).fontColor(this.t().inkSoft)
        Blank()
        Text(`${Math.round(field === 'glow' ? this.bg().glowValue : this.bg().grainValue)}%`)
          .fontSize(11).fontColor(this.t().inkSoft)
      }
      .width('100%')
      Slider({
        value: field === 'glow' ? this.bg().glowValue : this.bg().grainValue,
        min: 0,
        max: 100,
        step: 1
      })
        .width('100%')
        .selectedColor(this.t().seal)
        .onChange((v: number) => {
          if (field === 'glow') this.bg().glowValue = v;
          else this.bg().grainValue = v;
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
      .onClick(() => { this.editKey = key; })
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

      if (this.expanded) {
        this.BgRow('浅色模式', 'light')
        this.BgRow('深色模式', 'dark')

        Row({ space: 8 }) {
          Text('调整')
            .fontSize(12)
            .fontColor(this.t().inkSoft)
          this.EditChip('浅色', 'light')
          this.EditChip('深色', 'dark')
          Blank()
          Text(this.advanced ? '收起高级' : '高级')
            .fontSize(12)
            .fontColor(this.t().sealInk)
            .onClick(() => { this.advanced = !this.advanced; })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })

        this.SliderRow('亮度', 'brightness', 0.6, 1.4, 0.02)
        this.SliderRow('模糊', 'blur', 0, 20, 1)
        this.SliderRow('遮罩', 'scrim', 0, 100, 2)

        this.LevelSlider('氛围光', 'glow')
        this.LevelSlider('纸纹', 'grain')

        if (this.dark) {
          Row() {
            Text('深色 dither').fontSize(12).fontColor(this.t().inkSoft)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.bg().dither })
              .selectedColor(this.t().seal)
              .onChange((on: boolean) => {
                this.bg().dither = on;
                Store.get().saveSettings();
              })
          }
          .width('100%')
        }

        if (this.advanced) {
          Text('2×2 覆盖：经典 / 朴素')
            .fontSize(11)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 4 })
          Row({ space: 8 }) {
            this.BgCell('浅色经典', 'lightClassic')
            this.BgCell('浅色朴素', 'lightPlain')
          }
          .width('100%')
          Row({ space: 8 }) {
            this.BgCell('深色经典', 'darkClassic')
            this.BgCell('深色朴素', 'darkPlain')
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.t().card)
    .borderRadius(this.t().radiusCard)
    .border({ width: 1, color: this.t().line })
  }
}
