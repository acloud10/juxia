import { UiState } from '../state/UiState';

// 全局错误出口：数据层不直接持有页面上下文，只把用户可读的信息交给根页面统一提示。
export class AppError {
  private static last: string = '';

  static report(message: string): void {
    if (message.length === 0 || message === AppError.last) return;
    AppError.last = message;
    const ui: UiState = UiState.get();
    ui.errorMessage = message;
    ui.errorRev = ui.errorRev + 1;
  }

  static clear(): void {
    AppError.last = '';
    UiState.get().errorMessage = '';
  }
}
