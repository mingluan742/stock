/**
 * 全局配置常量
 * 所有"魔法数字"集中在这里，改配置只动这一个文件
 */
export class AppConfig {
  /** 应用名 */
  static readonly APP_NAME: string = '涨跌实验室';
  /** 初始虚拟本金（跨市场统一记账本位币） */
  static readonly INIT_CASH: number = 1000000;
  /** 默认加载的剧本 */
  static readonly DEFAULT_SCENARIO: string = 'crash-1929';

  /** 涨（中国配色：红涨） */
  static readonly COLOR_UP: string = '#E64545';
  /** 跌（绿跌） */
  static readonly COLOR_DOWN: string = '#2E9E5B';
  /** 页面背景 */
  static readonly COLOR_BG: string = '#12141A';
  /** 卡片背景 */
  static readonly COLOR_CARD: string = '#1C1F27';
  /** 主文字 */
  static readonly COLOR_TEXT: string = '#F2F3F5';
  /** 次要文字 */
  static readonly COLOR_SUB: string = '#8A8F99';
  /** 强调色（金） */
  static readonly COLOR_ACCENT: string = '#D4A34B';

  /** ===== 明亮主题（主界面 / 列表页） ===== */
  /** 页面背景 */
  static readonly LIGHT_BG: string = '#F6F7F9';
  /** 卡片背景 */
  static readonly LIGHT_CARD: string = '#FFFFFF';
  /** 主文字 */
  static readonly LIGHT_TEXT: string = '#16181D';
  /** 次要文字 */
  static readonly LIGHT_SUB: string = '#7A808B';
  /** 分割线 / 卡片描边 */
  static readonly LIGHT_LINE: string = '#E9EBF0';
  /** 强调色（深一档的金，浅底上更清晰） */
  static readonly LIGHT_ACCENT: string = '#B7791F';
  /** 强调卡片背景 */
  static readonly LIGHT_GOLD_BG: string = '#FDF8EC';
  /** 强调卡片描边 */
  static readonly LIGHT_GOLD_LINE: string = '#F0E3C4';
}