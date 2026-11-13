/**
 * 新手引导状态：本机持久化
 * - 首次打开先询问是否为新手
 * - 新手 → 看完整教程；老手 → 直接进入主界面
 * 标记值：'' 未决定 / 'newbie' 新手 / 'expert' 老手 / 'done' 已看完教程
 */
export class TutorialService {
  static readonly KEY: string = 'stock_tutorial';

  private static read(): string {
    try {
      const v: string | undefined = AppStorage.get<string>(TutorialService.KEY);
      return v === undefined ? '' : v;
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 引导状态读取失败: ${e.message}`);
      return '';
    }
  }

  private static write(v: string): void {
    try {
      AppStorage.setOrCreate<string>(TutorialService.KEY, v);
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 引导状态写入失败: ${e.message}`);
    }
  }

  /** 是否已经做过选择（新手/老手），没选过就先问 */
  static get needsWelcome(): boolean {
    return TutorialService.read() === '';
  }

  /** 选了新手但教程还没看完（中途退出过），下次继续看 */
  static get pendingTutorial(): boolean {
    return TutorialService.read() === 'newbie';
  }

  /** 是否已经完整看过教程（含新手直接看完、老手跳过） */
  static get finished(): boolean {
    const v: string = TutorialService.read();
    return v === 'newbie' || v === 'expert' || v === 'done';
  }

  /** 用户自认老手：跳过教程 */
  static chooseExpert(): void {
    TutorialService.write('expert');
  }

  /** 用户自认新手：标记后进入教程 */
  static chooseNewbie(): void {
    TutorialService.write('newbie');
  }

  /** 教程走完 */
  static complete(): void {
    TutorialService.write('done');
  }
}