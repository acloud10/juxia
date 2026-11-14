import { UiState } from '../state/UiState';

// 全局错误出口：数据层只上报“发生了什么 + 用户可以做什么”，由根页面统一展示。
export class AppError {
  private static last: string = '';
  private static lastAt: number = 0;

  static report(message: string, hint: string = '', canOpenSettings: boolean = false): void {
    if (message.length === 0) return;
    // 同一个错误只抑制很短的时间；用户重试时要能再次看到反馈。
    if (message === AppError.last && Date.now() - AppError.lastAt < 1200) return;
    AppError.last = message;
    AppError.lastAt = Date.now();
    const ui: UiState = UiState.get();
    ui.errorMessage = message;
    ui.errorHint = hint;
    ui.errorCanOpenSettings = canOpenSettings;
    ui.errorRev = ui.errorRev + 1;
  }

  static clear(): void {
    AppError.last = '';
    AppError.lastAt = 0;
    const ui: UiState = UiState.get();
    ui.errorMessage = '';
    ui.errorHint = '';
    ui.errorCanOpenSettings = false;
  }
}
