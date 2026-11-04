// 句栖 · 全局 UI 状态（ArkUI 状态管理 V2）
@ObservedV2
export class UiState {
  private static instance: UiState | null = null;

  static get(): UiState {
    if (UiState.instance === null) {
      UiState.instance = new UiState();
    }
    return UiState.instance;
  }

  @Trace skin: string = 'classic';
  @Trace dark: boolean = false;
  @Trace appName: string = '句栖';
  @Trace dayCount: number = 1;
  @Trace showDays: boolean = true;
  @Trace safeTop: number = 0;
  @Trace safeBottom: number = 0;
  @Trace dataVersion: number = 0;
  @Trace openRevisit: boolean = false;
  @Trace backRev: number = 0;
  @Trace mineOpenId: string = '';
  @Trace mineOpenPanel: string = '';
  @Trace mineOpenRev: number = 0;
  @Trace settingsSection: string = 'ui';
  @Trace sheetOpenToday: boolean = false;
  @Trace sheetOpenMine: boolean = false;
  @Trace sheetOpenArchive: boolean = false;
  @Trace nickname: string = '';
  @Trace fontFollow: boolean = true;
  @Trace systemDark: boolean = false;
  @Trace systemFontScale: number = 1;
  @Trace themeMode: string = 'system';
  @Trace errorMessage: string = '';
  @Trace errorHint: string = '';
  @Trace errorCanOpenSettings: boolean = false;
  @Trace errorRev: number = 0;
}
