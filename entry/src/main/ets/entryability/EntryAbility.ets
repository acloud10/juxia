import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { UiState } from '../state/UiState';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'juxia', '%{public}s', 'Ability onCreate');
    const dark: boolean = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    UiState.get().systemDark = dark;
    this.handleWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want);
  }

  private handleWant(want: Want): void {
    try {
      const v = want.parameters?.['revisit'];
      if (v !== undefined && v !== null) {
        UiState.get().openRevisit = true;
      }
    } catch (e) {
      console.error('juxia wish handle fail', String(e));
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const dark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    UiState.get().systemDark = dark;
    const theme: string = UiState.get().themeMode;
    if (theme === 'system') {
      UiState.get().dark = dark;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'juxia', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'juxia', 'Succeeded in loading the content.');
    });
    this.setupWindow(windowStage);
  }

  private async setupWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const win = await windowStage.getMainWindow();
      await win.setWindowLayoutFullScreen(true);
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const top = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const bottom = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      UiState.get().safeTop = Math.round(top.topRect.height / density);
      UiState.get().safeBottom = Math.round(bottom.bottomRect.height / density);
      const dark: boolean = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      win.setWindowBackgroundColor(dark ? '#14110b' : '#F6F0E3');
      await win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#3A3A37',
        navigationBarContentColor: dark ? '#FFFFFF' : '#3A3A37'
      });
    } catch (e) {
      UiState.get().safeTop = 0;
      UiState.get().safeBottom = 0;
    }
  }
}
