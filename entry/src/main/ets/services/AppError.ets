import { UiState } from '../state/UiState';

// 全局错误出口：数据层只上报“发生了什么 + 用户可以做什么”，由根页面统一展示。
export class AppError {
  private static last: string = '';

  static report(message: string, hint: string = '', canOpenSettings: boolean = false): void {
    if (message.length === 0 || message === AppError.last) return;
    AppError.last = message;
    const ui: UiState = UiState.get();
    ui.errorMessage = message;
    ui.errorHint = hint;
    ui.errorCanOpenSettings = canOpenSettings;
    ui.errorRev = ui.errorRev + 1;
  }

  static clear(): void {
    AppError.last = '';
    const ui: UiState = UiState.get();
    ui.errorMessage = '';
    ui.errorHint = '';
    ui.errorCanOpenSettings = false;
  }
}
