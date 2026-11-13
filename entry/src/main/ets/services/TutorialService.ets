/**
 * 新手教程状态：本机持久化
 * - 未完成：应用启动时自动进入教程
 * - 完成 / 口令跳过：不再自动弹出
 */
export class TutorialService {
  static readonly KEY: string = 'stock_tutorial';
  /** 口令：输入这四个字直接跳过 */
  static readonly SKIP_WORD: string = '我是老手';

  /** 是否已看过（完成或跳过） */
  static get finished(): boolean {
    try {
      const v: string | undefined = AppStorage.get<string>(TutorialService.KEY);
      return v === 'done' || v === 'skipped';
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 教程状态读取失败: ${e.message}`);
      return false;
    }
  }

  /** 走完全部步骤 */
  static complete(): void {
    TutorialService.write('done');
  }

  /** 口令跳过 */
  static skip(): void {
    TutorialService.write('skipped');
  }

  /** 重新观看（不清除已看过标记，只是本次进入） */
  private static write(v: string): void {
    try {
      AppStorage.setOrCreate<string>(TutorialService.KEY, v);
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 教程状态写入失败: ${e.message}`);
    }
  }

  /** 去掉空格后判断是否输对了口令 */
  static isSkipWord(input: string): boolean {
    return input.replace(/\s/g, '') === TutorialService.SKIP_WORD;
  }
}