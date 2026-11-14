import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { Result } from '../core/Result';
import { SaveService, SaveSnapshot } from '../core/SaveService';
import { LiveRandomMarket } from '../services/RandomScenarioService';
import { Account } from '../models/Account';
import { AchievementContext, AchievementDef } from '../models/Achievement';
import { KLine } from '../models/KLine';
import { ScenarioData, StockSpec } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';

/** 图表最多同时显示的样本数（超出后向左滚动） */
const MAX_POINTS: number = 60;
/** K线视口显示的蜡烛根数 */
const CANDLE_POINTS: number = 42;
/** 每个"交易日"的播放间隔（毫秒）：400ms 为基准，0.75 倍速 ≈ 533ms */
const TICK_MS: number = 533;

/** 持仓总览行数据（随机盘多标的） */
interface HoldingRow {
  id: string;
  name: string;
  code: string;
  priceText: string;
  sharesText: string;
  pnlText: string;
  /** 盈亏颜色：true = 红（赚） */
  up: boolean;
  /** 持仓方向：1 多 / -1 空 / 0 空仓 */
  direction: number;
}

/**
 * 实时盯盘页：
 * - 定时器每 400ms 推进一个交易日，Canvas 分时曲线持续向右生长
 * - 买卖按钮常驻，随时可操作，账户现金/持仓/浮盈实时刷新
 * - 走到历史事件日自动暂停，弹出"历史现场"，关闭后继续
 */
@Component
export struct TradeView {
  /** 进入模式：history / random */
  @Prop mode: string = 'history';
  /** 历史剧本 id */
  @Prop scenarioId: string = AppConfig.DEFAULT_SCENARIO;
  /** 是否从存档继续 */
  @Prop resume: boolean = false;
  /** 返回上一级（由 App 页注入） */
  onBack: () => void = () => {};
  /** 查看结算复盘（由 App 页注入） */
  onFinish: () => void = () => {};
  @State scenarioName: string = '加载中…';
  /** 多标的：股票清单与选中 id（随机盘） */
  @State stockTabs: StockSpec[] = [];
  @State activeStockId: string = '';
  /** 持仓总览行数据（随机盘） */
  @State holdingRows: HoldingRow[] = [];
  @State eraText: string = '';
  @State priceText: string = '--';
  @State changeText: string = '';
  @State changeUp: boolean = true;
  @State progressText: string = '';
  @State paused: boolean = false;
  @State finished: boolean = false;

  @State cashText: string = '--';
  @State sharesText: string = '0 股';
  @State avgCostText: string = '成本 --';
  @State pnlText: string = '0';
  @State pnlUp: boolean = true;
  @State chartMode: number = 0; // 0 = 分时线，1 = K线蜡烛

  // 账户衍生信息
  @State netText: string = '--';
  @State debtText: string = '0';
  @State feeText: string = '0';
  @State loanAvailText: string = '0';
  @State sellableText: string = '0 股';
  @State bankrupt: boolean = false;

  // 下单面板（常驻，不再用弹层）
  @State marginText: string = '100000';
  @State notionalText: string = '0';
  @State feePreviewText: string = '0';
  @State riskText: string = '--';
  @State buyBtnText: string = '做多';
  @State sellBtnText: string = '做空';
  @State tradeTip: string = '';
  /** 杠杆倍数 */
  @State leverage: number = 1;

  // 贷款面板
  @State showLoan: boolean = false;
  /** 下单面板是否展开（默认收起为摘要行） */
  @State orderExpanded: boolean = false;
  @State loanAmountText: string = '100000';
  @State loanTip: string = '';
  // 利息明细
  @State debtPrincipalText: string = '0';
  @State debtInterestText: string = '0';
  @State dailyInterestText: string = '0';
  @State loanPreviewText: string = '';

  @State eventList: ScenarioEvent[] = [];
  /** 快讯条文案（随机盘，最新一条，5 秒后回到等待态） */
  @State newsText: string = '等待市场消息…';
  /** 标的下拉选择是否展开 */
  @State showStockPicker: boolean = false;
  @State introText: string = '';

  private prices: number[] = [];
  private currentPrice: number = 0;
  private lastRatio: number = 0;
  private timerId: number = -1;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private eventScroller: Scroller = new Scroller();
  private tickCount: number = 0;
  /** 本局是否已计入结束统计（避免重复累计） */
  private roundCounted: boolean = false;
  /** 快讯条恢复等待态的计时器（随机盘专用） */
  private newsTimer: number = -1;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
    if (this.resume) {
      const snap: SaveSnapshot | null = SaveService.load();
      if (snap !== null && snap.mode === 'random' && snap.live !== undefined) {
        this.loadRandomResume(snap);
      } else {
        this.loadScenarioResume(this.scenarioId);
      }
    } else if (this.mode === 'random') {
      this.loadRandom();
    } else {
      this.loadScenario(this.scenarioId);
    }
  }

  aboutToDisappear(): void {
    this.stopPlay();
    // 清理快讯计时器，避免组件销毁后回调
    if (this.newsTimer >= 0) {
      clearTimeout(this.newsTimer);
      this.newsTimer = -1;
    }
  }

  async loadScenario(id: string): Promise<void> {
    try {
      await AppContext.getMarket().load(id);
      this.applyLoaded();
    } catch (err) {
      const e = err as Error;
      this.scenarioName = `加载失败：${e.message}`;
    }
  }

  /** 从存档恢复：加载剧本后回拨游标、账户与曲线 */
  async loadScenarioResume(id: string): Promise<void> {
    try {
      await AppContext.getMarket().load(id);
      this.applyLoaded();
      const snap: SaveSnapshot | null = SaveService.load();
      if (snap === null || snap.scenarioId !== id) {
        return;
      }
      const market = AppContext.getMarket();
      market.setCursor(snap.cursor);
      AppContext.getTrading().restore(snap.account);
      this.prices = market.historyPrices();
      const bar: KLine | null = market.currentBar;
      if (bar !== null) {
        this.currentPrice = bar.price;
      }
      this.eventList = [];
      this.appendEvents(market.eventsPassed());
      this.stockTabs = market.stocks;
      if (market.stocks.length > 0) {
        this.activeStockId = market.activeStock === null ? market.stocks[0].id : market.activeStock.id;
      }
      this.syncValuationPrices();
      this.bankrupt = AppContext.getTrading().netAsset(this.currentPrice) <= 0;
      AppContext.getTrading().updateNetTracking(this.currentPrice);
      this.syncMarketText();
      this.syncAccount();
      this.drawChart();
    } catch (err) {
      const e = err as Error;
      this.scenarioName = `恢复失败：${e.message}`;
    }
  }

  /** 保存当前对局快照（历史与随机都支持；已结束/爆仓不存） */
  saveSnapshot(): void {
    if (this.finished || this.bankrupt) {
      return;
    }
    const market = AppContext.getMarket();
    if (this.mode === 'random') {
      const live = market.liveMarket;
      if (live === null) {
        return;
      }
      const snap: SaveSnapshot = {
        mode: 'random',
        scenarioId: market.meta === null ? 'random-live' : market.meta.id,
        scenarioName: market.meta === null ? '' : market.meta.name,
        cursor: market.dayIndex,
        totalDays: market.totalDays,
        account: AppContext.getTrading().snapshot(),
        savedAt: new Date().toISOString(),
        live: live.serialize()
      };
      SaveService.save(snap);
      return;
    }
    const meta = market.meta;
    const snap: SaveSnapshot = {
      mode: 'history',
      scenarioId: this.scenarioId,
      scenarioName: meta === null ? '' : meta.name,
      cursor: market.dayIndex,
      totalDays: market.totalDays,
      account: AppContext.getTrading().snapshot(),
      savedAt: new Date().toISOString()
    };
    SaveService.save(snap);
  }

  /** 生成并载入一局随机行情（活市场：无限延续） */
  loadRandom(): void {
    try {
      const m: LiveRandomMarket = AppContext.getRandom().generateLive();
      AppContext.getMarket().loadLive(m);
      this.applyLoaded();
    } catch (err) {
      const e = err as Error;
      this.scenarioName = `生成失败：${e.message}`;
    }
  }

  /** 从存档恢复随机盘（活市场 + 账户） */
  loadRandomResume(snap: SaveSnapshot): void {
    if (snap.live === undefined) {
      this.loadRandom();
      return;
    }
    try {
      const m: LiveRandomMarket = LiveRandomMarket.restore(snap.live);
      AppContext.getMarket().loadLive(m);
      this.applyLoaded();
      const market = AppContext.getMarket();
      AppContext.getTrading().restore(snap.account);
      this.eventList = [];
      this.stockTabs = market.stocks;
      if (market.stocks.length > 0) {
        this.activeStockId = market.activeStock === null ? market.stocks[0].id : market.activeStock.id;
      }
      this.syncValuationPrices();
      const bar: KLine | null = market.currentBar;
      if (bar !== null) {
        this.currentPrice = bar.price;
      }
      this.bankrupt = AppContext.getTrading().netAsset(this.currentPrice) <= 0;
      AppContext.getTrading().updateNetTracking(this.currentPrice);
      this.syncMarketText();
      this.syncAccount();
      this.drawChart();
      this.startPlay();
    } catch (err) {
      const e = err as Error;
      this.scenarioName = `恢复失败：${e.message}`;
    }
  }

  /** 随机模式：用户主动结束本局（唯一结束方式） */
  endRound(): void {
    this.stopPlay();
    this.paused = true;
    this.finished = true;
    this.progressText = '已手动结束';
    SaveService.clear();
    this.finishRound();
  }

  /** 剧本载入后的页面初始化（历史与随机共用） */
  applyLoaded(): void {
    const market = AppContext.getMarket();
    // 每一局都是独立账户：先按本剧本规则重置
    const rules = market.rules;
    if (rules !== null) {
      AppContext.getTrading().setRules(rules);
    } else {
      AppContext.getTrading().reset();
    }
    // 多标的：注册独立记账并选中第一只
    const stocks: StockSpec[] = market.stocks;
    this.stockTabs = stocks;
    if (stocks.length > 0) {
      const ids: string[] = [];
      for (const st of stocks) {
        ids.push(st.id);
      }
      AppContext.getTrading().enableMultiStock(ids);
      this.activeStockId = stocks[0].id;
      market.selectStock(stocks[0].id);
    } else {
      this.activeStockId = '';
    }
    this.bankrupt = false;
    this.roundCounted = false;
    this.showLoan = false;
    const meta = market.meta;
    if (meta !== null) {
      this.scenarioName = meta.name;
      this.eraText = meta.era;
      this.introText = meta.intro;
    }
    this.eventList = [];
    // 补出第 1 天事件（否则加载当天的事件永远不会触发）
    this.appendEvents(market.eventsToday());
    AppContext.getAchievements().startSession();
    this.prices = [];
    const bar: KLine | null = market.currentBar;
    if (bar !== null) {
      this.prices.push(bar.price);
      this.currentPrice = bar.price;
    }
    this.finished = false;
    this.syncValuationPrices();
    AppContext.getTrading().updateNetTracking(this.currentPrice);
    this.syncMarketText();
    this.syncAccount();
    this.drawChart();
    this.startPlay();
  }

  startPlay(): void {
    this.stopPlay();
    this.paused = false;
    this.timerId = setInterval(() => {
      this.onTick();
    }, TICK_MS);
  }

  stopPlay(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 行情推进到暂停/结束：随机盘永远显示"继续" */
  togglePause(): void {
    if (this.finished) {
      if (this.mode === 'random') {
        // 随机盘已结束：去复盘页
        this.onFinish();
      } else {
        this.replay();
      }
      return;
    }
    this.paused = !this.paused;
  }

  /** 把事件加入列表：历史剧本累积保留；随机盘改为右上角弹窗，5 秒后自动消失 */
  appendEvents(events: ScenarioEvent[]): void {
    if (events.length === 0) {
      return;
    }
    if (this.mode === 'random') {
      // 快讯条：只显示最新一条消息，5 秒后回到等待态
      const last: ScenarioEvent = events[events.length - 1];
      this.newsText = `${last.title}：${last.desc}`;
      if (this.newsTimer >= 0) {
        clearTimeout(this.newsTimer);
      }
      this.newsTimer = setTimeout(() => {
        this.newsText = '等待市场消息…';
        this.newsTimer = -1;
      }, 5000);
      return;
    }
    // 历史现场：累积保留，滚动到底部
    for (const ev of events) {
      this.eventList = this.eventList.concat([ev]);
    }
    setTimeout(() => {
      this.eventScroller.scrollEdge(Edge.Bottom);
    }, 60);
  }

  /** 重播：历史剧本从头再来，随机模式重新生成一局 */
  replay(): void {
    if (this.mode === 'random') {
      this.loadRandom();
      return;
    }
    const market = AppContext.getMarket();
    market.restart();
    AppContext.getTrading().reset();
    this.prices = [];
    const bar: KLine | null = market.currentBar;
    if (bar !== null) {
      this.prices.push(bar.price);
      this.currentPrice = bar.price;
    }
    this.finished = false;
    this.paused = false;
    this.roundCounted = false;
    if (this.mode === 'random' && this.stockTabs.length > 0) {
      this.activeStockId = this.stockTabs[0].id;
      AppContext.getMarket().selectStock(this.activeStockId);
    }
    AppContext.getTrading().updateNetTracking(this.currentPrice);
    this.eventList = [];
    this.appendEvents(market.eventsToday()); // 补出第 1 天事件
    AppContext.getAchievements().startSession();
    this.syncMarketText();
    this.syncAccount();
    this.drawChart();
    this.startPlay();
  }

  /** 每个 tick 推进一步行情 */
  onTick(): void {
    if (this.paused || this.finished) {
      return;
    }
    const market = AppContext.getMarket();
    const events: ScenarioEvent[] = market.advance();
    const bar: KLine | null = market.currentBar;
    if (bar === null) {
      return;
    }
    this.currentPrice = bar.price;
    this.prices.push(bar.price);
    const trading = AppContext.getTrading();
    trading.newDay(bar.date);
    this.syncValuationPrices();
    trading.updateNetTracking(bar.price);
    this.syncMarketText();
    this.syncAccount();
    this.drawChart();
    if (trading.bankrupt(bar.price) && !this.bankrupt) {
      this.bankrupt = true;
      this.paused = true;
      this.progressText = '已爆仓';
      this.showTip('净资产归零，已爆仓');
      SaveService.clear();
    }
    if (market.finished) {
      this.finished = true;
      this.stopPlay();
      this.progressText = '剧本终结';
      SaveService.clear();
    }
    if (events.length > 0) {
      // 不打断行情：事件累积到历史现场列表，可滑动回看
      this.appendEvents(events);
    }
    // 每推进一天判定一次成就（如做空持仓、杠杆、净资产达标）
    this.checkAchievements();
    this.finishRound();
    // 每 5 个交易日存一次档，防止异常退出丢进度
    this.tickCount += 1;
    if (this.tickCount % 5 === 0) {
      this.saveSnapshot();
    }
  }

  /** 组装成就判定上下文 */
  buildAchievementContext(): AchievementContext {
    const market = AppContext.getMarket();
    const trading = AppContext.getTrading();
    const bar: KLine | null = market.currentBar;
    const price: number = bar === null ? this.currentPrice : bar.price;
    return {
      scenarioId: this.scenarioId,
      mode: this.mode,
      dayIndex: market.dayIndex,
      totalDays: market.totalDays,
      finished: this.finished,
      bankrupt: this.bankrupt,
      netAsset: trading.netAsset(price),
      price: price,
      shares: trading.shares(this.stockId()),
      maxDrawdown: trading.maxDrawdown,
      tradeCount: trading.tradeCount,
      buyCount: trading.buyCount,
      sellCount: trading.sellCount,
      winRate: trading.winRate,
      maxLeverage: trading.maxLeverageUsed,
      totalBorrowed: trading.totalBorrowed
    };
  }

  /** 弹出解锁提示 */
  notifyAchievements(gained: AchievementDef[]): void {
    if (gained.length === 0) {
      return;
    }
    if (gained.length === 1) {
      this.showTip(`解锁成就「${gained[0].name}」`);
      return;
    }
    let names: string = '';
    for (const a of gained) {
      names = names === '' ? a.name : `${names}、${a.name}`;
    }
    this.showTip(`解锁 ${gained.length} 个成就：${names}`);
  }

  /** 判定普通成就 */
  checkAchievements(): void {
    if (this.bankrupt || this.finished) {
      return;
    }
    const gained: AchievementDef[] = AppContext.getAchievements().check(this.buildAchievementContext());
    this.notifyAchievements(gained);
  }

  /** 一局结束时累计统计并判定收尾成就（每局只算一次） */
  finishRound(): void {
    if (this.roundCounted || (!this.finished && !this.bankrupt)) {
      return;
    }
    this.roundCounted = true;
    const gained: AchievementDef[] = AppContext.getAchievements().finishRound(this.buildAchievementContext());
    this.notifyAchievements(gained);
  }

  syncMarketText(): void {
    const market = AppContext.getMarket();
    const bar: KLine | null = market.currentBar;
    if (bar === null) {
      return;
    }
    this.priceText = bar.price.toFixed(2);
    const ratio: number = market.dayChangeRatio();
    this.lastRatio = ratio;
    this.changeUp = ratio >= 0;
    const sign: string = ratio >= 0 ? '+' : '';
    this.changeText = `${sign}${(ratio * 100).toFixed(2)}%`;
    if (!this.finished) {
      if (market.isLive) {
        this.progressText = `第 ${market.dayIndex + 1} 个交易日 · 无限延续`;
      } else {
        this.progressText = `第 ${market.dayIndex + 1} / ${market.totalDays} 交易日`;
      }
    }
  }

  syncAccount(): void {
    const t = AppContext.getTrading();
    const sid: string | null = this.stockId();
    const shares: number = t.shares(sid);
    this.cashText = this.formatMoney(t.cash);
    if (shares > 0) {
      this.sharesText = `多 ${shares} 股`;
    } else if (shares < 0) {
      this.sharesText = `空 ${-shares} 股`;
    } else {
      this.sharesText = '0 股';
    }
    if (shares !== 0) {
      const avg: number = t.avgCost(sid);
      this.avgCostText = shares > 0 ? `成本 ${avg.toFixed(2)}` : `卖空均价 ${avg.toFixed(2)}`;
      const pnl: number = t.pnl(this.currentPrice, sid);
      this.pnlUp = pnl >= 0;
      this.pnlText = `${pnl >= 0 ? '+' : '-'}${this.formatMoney(Math.abs(pnl))}`;
    } else {
      this.avgCostText = '成本 --';
      this.pnlUp = true;
      this.pnlText = '0';
    }
    const net: number = t.netAsset(this.currentPrice);
    this.netText = `${net < 0 ? '-' : ''}${this.formatMoney(Math.abs(net))}`;
    this.debtText = this.formatMoney(t.debt);
    this.feeText = this.formatMoney(t.feeTotal);
    this.loanAvailText = this.formatMoney(t.loanAvailable);
    this.sellableText = `${t.sellableShares(sid)} 股`;
    this.debtPrincipalText = this.formatMoney(t.debtPrincipal);
    this.debtInterestText = this.formatMoney(t.debtInterest);
    this.dailyInterestText = this.formatMoney(t.dailyInterest);
    this.syncHoldings();
    this.updatePreview();
  }

  formatMoney(v: number): string {
    const s: string = Math.abs(Math.round(v)).toString();
    let rest: string = s;
    let out: string = '';
    while (rest.length > 3) {
      out = `,${rest.substring(rest.length - 3)}${out}`;
      rest = rest.substring(0, rest.length - 3);
    }
    return rest + out;
  }

  /** 多标的辅助：当前股票 id（单标的模式返回 null） */
  stockId(): string | null {
    return this.stockTabs.length > 0 ? this.activeStockId : null;
  }

  /** 行情推进后刷新所有股票的估值价（多标的） */
  syncValuationPrices(): void {
    if (this.stockTabs.length === 0) {
      return;
    }
    const market = AppContext.getMarket();
    const map: Record<string, number> = {};
    for (const st of this.stockTabs) {
      const bar: KLine | null = market.barAt(st.id, market.dayIndex);
      if (bar !== null) {
        map[st.id] = bar.price;
      }
    }
    AppContext.getTrading().setValuationPrices(map);
  }

  /** 切换选中股票 */
  pickStock(id: string): void {
    if (this.activeStockId === id) {
      return;
    }
    this.activeStockId = id;
    AppContext.getMarket().selectStock(id);
    // 重画当前股票的曲线与账户栏
    this.prices = AppContext.getMarket().historyPrices();
    const bar: KLine | null = AppContext.getMarket().currentBar;
    if (bar !== null) {
      this.currentPrice = bar.price;
    }
    this.syncMarketText();
    this.syncAccount();
    this.drawChart();
  }

  /** 刷新持仓总览（随机盘）：每只股票一行，含持仓方向与浮动盈亏 */
  syncHoldings(): void {
    if (this.stockTabs.length === 0) {
      return;
    }
    const market = AppContext.getMarket();
    const t = AppContext.getTrading();
    const rows: HoldingRow[] = [];
    for (const st of this.stockTabs) {
      const bar: KLine | null = market.barAt(st.id, market.dayIndex);
      const price: number = bar === null ? 0 : bar.price;
      const shares: number = t.shares(st.id);
      let direction: number = 0;
      let sharesText: string = '空仓';
      let pnl: number = 0;
      if (shares > 0) {
        direction = 1;
        sharesText = `多 ${shares} 股`;
        pnl = t.pnl(price, st.id);
      } else if (shares < 0) {
        direction = -1;
        sharesText = `空 ${-shares} 股`;
        pnl = t.pnl(price, st.id);
      }
      const row: HoldingRow = {
        id: st.id,
        name: st.name,
        code: st.code,
        priceText: price.toFixed(2),
        sharesText: sharesText,
        pnlText: pnl === 0 ? '0' : `${pnl >= 0 ? '+' : '-'}${this.formatMoney(Math.abs(pnl))}`,
        up: pnl >= 0,
        direction: direction
      };
      rows.push(row);
    }
    this.holdingRows = rows;
  }

  /** 当前选中股票名称 */
  activeStockName(): string {
    for (const st of this.stockTabs) {
      if (st.id === this.activeStockId) {
        return st.name;
      }
    }
    return '--';
  }

  /** 当前选中股票代码 */
  activeStockCode(): string {
    for (const st of this.stockTabs) {
      if (st.id === this.activeStockId) {
        return st.code;
      }
    }
    return '';
  }

  /** 有持仓的股票只数（持仓卡徽标） */
  positionCount(): number {
    let n: number = 0;
    for (const r of this.holdingRows) {
      if (r.direction !== 0) {
        n += 1;
      }
    }
    return n;
  }

  /** 统一 Toast，内部捕获异常，使用组件上下文推荐写法 */
  showTip(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1400 });
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] toast 失败: ${e.message}`);
    }
  }

  // ===== 下单面板 =====

  /** 保证金输入变化 */
  setMargin(v: string): void {
    this.marginText = v;
    this.tradeTip = '';
    this.updatePreview();
  }

  /** 一键填满可用现金（预留手续费：所需现金 = 保证金 × (1 + 杠杆 × 费率)） */
  fillMarginMax(): void {
    const t = AppContext.getTrading();
    const rate: number = this.currentFeeRate();
    const maxMargin: number = t.cash / (1 + this.leverage * rate);
    this.marginText = `${Math.max(0, Math.floor(maxMargin))}`;
    this.tradeTip = '';
    this.updatePreview();
  }

  /** 杠杆变化（滑块） */
  setLeverage(v: number): void {
    this.leverage = Math.max(1, Math.min(Math.round(v), AppConfig.MAX_LEVERAGE));
    this.tradeTip = '';
    this.updatePreview();
  }

  parseMargin(): number {
    const n: number = parseInt(this.marginText, 10);
    if (isNaN(n) || n <= 0) {
      return 0;
    }
    return n;
  }

  currentFeeRate(): number {
    const rules = AppContext.getMarket().rules;
    if (rules === null) {
      return 0;
    }
    return rules.feeRate;
  }

  /** 保证金 × 杠杆 折算成整手股数 */
  previewQty(): number {
    const margin: number = this.parseMargin();
    if (margin <= 0 || this.currentPrice <= 0) {
      return 0;
    }
    const notional: number = margin * this.leverage;
    const qty: number = Math.floor(notional / this.currentPrice / 100) * 100;
    return qty > 0 ? qty : 0;
  }

  /** 买入方向的数量：空头时只平空，不反手 */
  previewBuyQty(): number {
    const t = AppContext.getTrading();
    const sid: string | null = this.stockId();
    const shares: number = t.shares(sid);
    const qty: number = this.previewQty();
    if (shares < 0) {
      const cover: number = -shares;
      return qty > cover ? cover : qty;
    }
    return qty;
  }

  /** 卖出方向的数量：多头时只平多（受 T+1 限制），空头时加空，无持仓时开空 */
  previewSellQty(): number {
    const t = AppContext.getTrading();
    const sid: string | null = this.stockId();
    const shares: number = t.shares(sid);
    const qty: number = this.previewQty();
    if (shares > 0) {
      const sellable: number = t.sellableShares(sid);
      return qty > sellable ? sellable : qty;
    }
    const rules = AppContext.getMarket().rules;
    if (shares === 0 && rules !== null && !rules.shortSell) {
      return 0;
    }
    return qty;
  }

  /** 当前市场是否允许做空 */
  canShort(): boolean {
    const rules = AppContext.getMarket().rules;
    return rules !== null && rules.shortSell;
  }

  /** 刷新参数反馈（名义仓位 / 手续费 / 可承受反向波动）与按钮文案 */
  updatePreview(): void {
    const t = AppContext.getTrading();
    const margin: number = this.parseMargin();
    const qty: number = this.previewQty();
    const notional: number = qty * this.currentPrice;
    const fee: number = notional * this.currentFeeRate();
    this.notionalText = this.formatMoney(notional);
    this.feePreviewText = this.formatMoney(fee);

    const buyQty: number = this.previewBuyQty();
    const sellQty: number = this.previewSellQty();
    const shares: number = t.shares(this.stockId());
    if (shares > 0) {
      this.buyBtnText = buyQty > 0 ? `加多 ${buyQty} 股` : '加多';
      this.sellBtnText = sellQty > 0 ? `平多 ${sellQty} 股` : '平多';
    } else if (shares < 0) {
      this.buyBtnText = buyQty > 0 ? `平空 ${buyQty} 股` : '平空';
      if (!this.canShort()) {
        this.sellBtnText = '做空不可用';
      } else {
        this.sellBtnText = sellQty > 0 ? `加空 ${sellQty} 股` : '加空';
      }
    } else {
      this.buyBtnText = buyQty > 0 ? `做多 ${buyQty} 股` : '做多';
      if (!this.canShort()) {
        this.sellBtnText = '做空不可用';
      } else {
        this.sellBtnText = sellQty > 0 ? `做空 ${sellQty} 股` : '做空';
      }
    }

    if (margin > 0 && this.leverage > 1) {
      // 自有资金能承受的反向波动：保证金 / 名义仓位（再扣掉手续费）
      const risk: number = Math.max(0, (margin - fee) / (margin * this.leverage));
      this.riskText = `${(risk * 100).toFixed(2)}%`;
    } else if (margin > 0) {
      this.riskText = '无杠杆';
    } else {
      this.riskText = '--';
    }
  }

  /** 买入：空头时先平空，多头时加仓 */
  confirmBuy(): void {
    const qty: number = this.previewBuyQty();
    if (qty <= 0) {
      this.tradeTip = '请填写保证金，并确认行情已就绪';
      return;
    }
    const t = AppContext.getTrading();
    const before: number = t.shares(this.stockId());
    const r: Result<Account> = t.buy(this.currentPrice, qty, this.lastRatio, this.leverage, this.stockId());
    if (r.ok) {
      this.tradeTip = '';
      this.showTip(before < 0 ? `平空 ${qty} 股成交` : `买入 ${qty} 股成交`);
      this.syncAccount();
      this.saveSnapshot();
      this.checkAchievements();
    } else {
      this.tradeTip = r.message;
    }
  }

  /** 卖出：多头时平多（受 T+1），空头时加空，无持仓时开空 */
  confirmSell(): void {
    const t = AppContext.getTrading();
    const qty: number = this.previewSellQty();
    if (qty <= 0) {
      if (t.shares(this.stockId()) > 0) {
        this.tradeTip = '可卖持仓为 0（T+1 或已全部卖出）';
      } else if (!this.canShort()) {
        this.tradeTip = '本市场不支持做空';
      } else {
        this.tradeTip = '请填写保证金，并确认行情已就绪';
      }
      return;
    }
    if (t.shares(this.stockId()) <= 0 && !this.canShort()) {
      this.tradeTip = '本市场不支持做空';
      return;
    }
    const before: number = t.shares(this.stockId());
    const r: Result<Account> = t.sell(this.currentPrice, qty, this.lastRatio, this.stockId());
    if (r.ok) {
      this.tradeTip = '';
      this.showTip(before <= 0 ? `做空 ${qty} 股成交` : `卖出 ${qty} 股成交`);
      this.syncAccount();
      this.saveSnapshot();
      this.checkAchievements();
    } else {
      this.tradeTip = r.message;
    }
  }

  /** 一键平仓：多头全卖，空头全买回 */
  closeAll(): void {
    const t = AppContext.getTrading();
    const sid: string | null = this.stockId();
    const shares: number = t.shares(sid);
    if (shares === 0) {
      this.tradeTip = this.stockTabs.length > 0 ? '当前股票没有持仓' : '当前没有持仓';
      return;
    }
    const r: Result<Account> = shares > 0
      ? t.sell(this.currentPrice, t.sellableShares(sid), this.lastRatio, sid)
      : t.buy(this.currentPrice, -shares, this.lastRatio, 1, sid);
    if (r.ok) {
      this.tradeTip = '';
      this.showTip('已一键平仓');
      this.syncAccount();
      this.saveSnapshot();
      this.checkAchievements();
    } else {
      this.tradeTip = r.message;
    }
  }

  // ===== 贷款面板 =====

  openLoan(): void {
    this.loanTip = '';
    this.loanAmountText = '100000';
    this.updateLoanPreview();
    this.showLoan = true;
  }

  /** 按当前输入预估利息成本 */
  updateLoanPreview(): void {
    const amt: number = this.parseLoanAmount();
    if (amt <= 0) {
      this.loanPreviewText = '';
      return;
    }
    const r: number = AppConfig.DAILY_LOAN_RATE;
    const m30: number = amt * (Math.pow(1 + r, 30) - 1);
    const m250: number = amt * (Math.pow(1 + r, 250) - 1);
    this.loanPreviewText = `借 ${this.formatMoney(amt)}：30 个交易日利息约 ${this.formatMoney(m30)}，持满 250 个交易日约 ${this.formatMoney(m250)}`;
  }

  fillLoan(v: number): void {
    this.loanAmountText = `${v}`;
    this.updateLoanPreview();
  }

  fillLoanMax(): void {
    this.loanAmountText = `${Math.round(AppContext.getTrading().loanAvailable)}`;
    this.updateLoanPreview();
  }

  parseLoanAmount(): number {
    const n: number = parseInt(this.loanAmountText, 10);
    if (isNaN(n) || n <= 0) {
      return 0;
    }
    return n;
  }

  confirmBorrow(): void {
    const amount: number = this.parseLoanAmount();
    if (amount <= 0) {
      this.loanTip = '请输入有效金额';
      return;
    }
    const r = AppContext.getTrading().borrow(amount);
    if (r.ok) {
      this.showLoan = false;
      this.showTip(`已借入 ${this.formatMoney(amount)} 元`);
      this.syncAccount();
      this.saveSnapshot();
      this.checkAchievements();
    } else {
      this.loanTip = r.message;
    }
  }

  confirmRepay(): void {
    const amount: number = this.parseLoanAmount();
    if (amount <= 0) {
      this.loanTip = '请输入有效金额';
      return;
    }
    const r = AppContext.getTrading().repay(amount);
    if (r.ok) {
      this.showLoan = false;
      this.showTip(`已还款 ${this.formatMoney(amount)} 元`);
      this.syncAccount();
      this.saveSnapshot();
    } else {
      this.loanTip = r.message;
    }
  }

  /** 切换图表形态 */
  setMode(m: number): void {
    if (this.chartMode === m) {
      return;
    }
    this.chartMode = m;
    this.drawChart();
  }

  /** 确定性小抖动（0~1），保证同一根蜡烛重绘时高低点不变 */
  jitter(i: number): number {
    const v: number = Math.sin((i + 1) * 12.9898) * 43758.5453;
    return v - Math.floor(v);
  }

  /** Canvas 绘制：网格 + 按模式画分时或K线 */
  drawChart(): void {
    const c = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const padL: number = 6;
    const padR: number = 44;
    const padT: number = 8;
    const padB: number = 8;
    const plotW: number = w - padL - padR;
    const plotH: number = h - padT - padB;
    c.clearRect(0, 0, w, h);

    // 网格（两种模式共用）
    c.strokeStyle = '#E6E9EF';
    c.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const gy: number = padT + (plotH * i) / 4;
      c.beginPath();
      c.moveTo(padL, gy);
      c.lineTo(padL + plotW, gy);
      c.stroke();
    }

    if (this.prices.length < 2) {
      return;
    }
    if (this.chartMode === 0) {
      this.drawLineChart(padL, padT, plotW, plotH);
    } else {
      this.drawCandleChart(padL, padT, plotW, plotH);
    }
  }

  /** 右侧价格刻度轴 */
  drawAxis(minP: number, maxP: number, padT: number, plotH: number): void {
    const c = this.ctx;
    const w: number = c.width;
    c.font = '9px sans-serif';
    c.fillStyle = '#9AA0A9';
    c.textAlign = 'right';
    for (let i = 0; i <= 4; i++) {
      const price: number = maxP - ((maxP - minP) * i) / 4;
      const y: number = padT + (plotH * i) / 4;
      c.fillText(price.toFixed(2), w - 3, y + 3);
    }
    c.textAlign = 'left';
  }

  /** 最新价虚线参考线 */
  drawLatestLine(price: number, minP: number, maxP: number, padT: number, plotH: number, padL: number, plotW: number): void {
    const c = this.ctx;
    const span: number = maxP - minP;
    if (span <= 0) {
      return;
    }
    const y: number = padT + ((maxP - price) / span) * plotH;
    c.setLineDash([3, 3]);
    c.strokeStyle = 'rgba(212,163,75,0.85)';
    c.lineWidth = 1;
    c.beginPath();
    c.moveTo(padL, y);
    c.lineTo(padL + plotW, y);
    c.stroke();
    c.setLineDash([]);
  }

  /** 分时折线 + 渐变面积 */
  drawLineChart(padL: number, padT: number, plotW: number, plotH: number): void {
    const c = this.ctx;
    const n: number = this.prices.length;
    const pts: number[] = n > MAX_POINTS ? this.prices.slice(n - MAX_POINTS) : this.prices;
    const m: number = pts.length;
    let minP: number = pts[0];
    let maxP: number = pts[0];
    for (const p of pts) {
      if (p < minP) {
        minP = p;
      }
      if (p > maxP) {
        maxP = p;
      }
    }
    let range: number = maxP - minP;
    if (range < maxP * 0.001) {
      range = Math.max(0.01, maxP * 0.001);
    }
    minP -= range * 0.12;
    maxP += range * 0.12;
    const span: number = maxP - minP;
    const stepX: number = plotW / (MAX_POINTS - 1);
    this.drawAxis(minP, maxP, padT, plotH);
    this.drawLatestLine(pts[m - 1], minP, maxP, padT, plotH, padL, plotW);
    const up: boolean = this.lastRatio >= 0;
    const lineColor: string = up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
    const topColor: string = up ? 'rgba(230,69,69,0.18)' : 'rgba(46,158,91,0.18)';
    const bottomColor: string = up ? 'rgba(230,69,69,0.01)' : 'rgba(46,158,91,0.01)';

    // 面积填充
    c.beginPath();
    for (let i = 0; i < m; i++) {
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - pts[i]) / span) * plotH;
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.lineTo(padL + (m - 1) * stepX, padT + plotH);
    c.lineTo(padL, padT + plotH);
    c.closePath();
    const grad: CanvasGradient = c.createLinearGradient(0, padT, 0, padT + plotH);
    grad.addColorStop(0, topColor);
    grad.addColorStop(1, bottomColor);
    c.fillStyle = grad;
    c.fill();

    // 折线
    c.beginPath();
    for (let i = 0; i < m; i++) {
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - pts[i]) / span) * plotH;
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.strokeStyle = lineColor;
    c.lineWidth = 2;
    c.stroke();

    // 最新点
    const lx: number = padL + (m - 1) * stepX;
    const ly: number = padT + ((maxP - pts[m - 1]) / span) * plotH;
    c.beginPath();
    c.arc(lx, ly, 3.5, 0, Math.PI * 2);
    c.fillStyle = lineColor;
    c.fill();
  }

  /** K线蜡烛：开盘=上一根收盘，高低点由波动幅度决定 */
  drawCandleChart(padL: number, padT: number, plotW: number, plotH: number): void {
    const c = this.ctx;
    const n: number = this.prices.length;
    const pts: number[] = n > CANDLE_POINTS ? this.prices.slice(n - CANDLE_POINTS) : this.prices;
    const m: number = pts.length;
    const opens: number[] = [];
    const closes: number[] = [];
    const highs: number[] = [];
    const lows: number[] = [];
    for (let i = 0; i < m; i++) {
      const close: number = pts[i];
      const open: number = i === 0 ? close : pts[i - 1];
      const amp: number = Math.abs(close - open);
      const extra: number = Math.max(amp * 0.35, close * 0.0012);
      opens.push(open);
      closes.push(close);
      highs.push(Math.max(open, close) + extra * (0.4 + this.jitter(i)));
      lows.push(Math.min(open, close) - extra * (0.4 + this.jitter(i + 31)));
    }
    let minP: number = lows[0];
    let maxP: number = highs[0];
    for (let i = 0; i < m; i++) {
      if (lows[i] < minP) {
        minP = lows[i];
      }
      if (highs[i] > maxP) {
        maxP = highs[i];
      }
    }
    let range: number = maxP - minP;
    if (range < maxP * 0.001) {
      range = Math.max(0.01, maxP * 0.001);
    }
    minP -= range * 0.08;
    maxP += range * 0.08;
    const span: number = maxP - minP;
    this.drawAxis(minP, maxP, padT, plotH);
    this.drawLatestLine(closes[m - 1], minP, maxP, padT, plotH, padL, plotW);
    const slot: number = plotW / CANDLE_POINTS;
    const bodyW: number = Math.max(2.5, slot * 0.62);

    for (let i = 0; i < m; i++) {
      const cx: number = padL + (i + 0.5) * slot;
      const yH: number = padT + ((maxP - highs[i]) / span) * plotH;
      const yL: number = padT + ((maxP - lows[i]) / span) * plotH;
      const yO: number = padT + ((maxP - opens[i]) / span) * plotH;
      const yC: number = padT + ((maxP - closes[i]) / span) * plotH;
      const up: boolean = closes[i] >= opens[i];
      const color: string = up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
      // 影线
      c.strokeStyle = color;
      c.lineWidth = 1;
      c.beginPath();
      c.moveTo(cx, yH);
      c.lineTo(cx, yL);
      c.stroke();
      // 实体（阳线红、阴线绿，统一实心，小尺寸下更清晰）
      const top: number = Math.min(yO, yC);
      const bodyH: number = Math.max(1.5, Math.abs(yC - yO));
      c.fillStyle = color;
      c.fillRect(cx - bodyW / 2, top, bodyW, bodyH);
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶栏
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(AppConfig.COLOR_SUB)
            .width(26)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.stopPlay();
              this.onBack();
            })
          Text(AppConfig.APP_NAME)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
            .margin({ left: 4 })
          Blank()
          Text(this.scenarioName)
            .fontSize(12)
            .fontColor(AppConfig.LIGHT_ACCENT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 4 })
          Text(this.finished ? '↻' : (this.paused ? '▶' : '⏸'))
            .fontSize(15)
            .fontColor('#7A808B')
            .padding({ left: 8, right: 6, top: 4, bottom: 4 })
            .onClick(() => {
              this.togglePause();
            })
          if (this.mode === 'random' && !this.finished && !this.bankrupt) {
            Text('⏹')
              .fontSize(14)
              .fontColor('#E64545')
              .padding({ left: 6, right: 2, top: 4, bottom: 4 })
              .onClick(() => {
                this.endRound();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

        // 多标的：标的选择（随机盘显示）
        if (this.stockTabs.length > 0) {
          Row() {
            Text('标的')
              .fontSize(10)
              .fontColor('#9AA0A9')
            Blank()
            Row({ space: 5 }) {
              Text(this.activeStockName())
                .fontSize(12)
                .fontColor(AppConfig.COLOR_TEXT)
              Text(this.activeStockCode())
                .fontSize(10)
                .fontColor('#9AA0A9')
              Text(this.showStockPicker ? '⌃' : '⌄')
                .fontSize(10)
                .fontColor('#7A808B')
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#FFFFFF')
            .borderRadius(10)
            .border({ width: 1, color: '#E9EBF0' })
            .onClick(() => {
              this.showStockPicker = !this.showStockPicker;
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: 8 })

          if (this.showStockPicker) {
            Column() {
              ForEach(this.stockTabs, (st: StockSpec) => {
                Row() {
                  Text(st.name)
                    .fontSize(12)
                    .fontColor(AppConfig.COLOR_TEXT)
                  Blank()
                  Text(st.code)
                    .fontSize(10)
                    .fontColor('#9AA0A9')
                  if (this.activeStockId === st.id) {
                    Text('●')
                      .fontSize(8)
                      .fontColor(AppConfig.LIGHT_ACCENT)
                      .margin({ left: 8 })
                  }
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(8)
                .backgroundColor(this.activeStockId === st.id ? '#FDF8EC' : Color.Transparent)
                .onClick(() => {
                  this.showStockPicker = false;
                  this.pickStock(st.id);
                })
              }, (st: StockSpec) => st.id)
            }
            .width('100%')
            .padding(6)
            .margin({ left: 16, right: 16, top: 6 })
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .border({ width: 1, color: '#E9EBF0' })
          }
        }

        // 价格区
        Row() {
          Column() {
            Text(this.priceText)
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.changeUp ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
            Text(this.changeText)
              .fontSize(15)
              .fontColor(this.changeUp ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 2 })

        // 实时走势图（右上角切换分时 / K线）
        Stack({ alignContent: Alignment.TopEnd }) {
          Canvas(this.ctx)
            .width('100%')
            .height(176)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .border({ width: 1, color: '#E9EBF0' })
            .onReady(() => {
              this.drawChart();
            })

          // 左上角：进度与年代信息
          Column() {
            Text(this.progressText)
              .fontSize(9)
              .fontColor('#9AA0A9')
              .maxLines(1)
            if (this.eraText !== '') {
              Text(this.eraText)
                .fontSize(9)
                .fontColor('#B4B9C0')
                .margin({ top: 1 })
                .maxLines(1)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 10, top: 6 })
          .hitTestBehavior(HitTestMode.None)

          Row() {
            Text('分时')
              .fontSize(10)
              .fontColor(this.chartMode === 0 ? '#12141A' : '#9AA0A9')
              .backgroundColor(this.chartMode === 0 ? AppConfig.COLOR_ACCENT : Color.Transparent)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .onClick(() => {
                this.setMode(0);
              })
            Text('K线')
              .fontSize(10)
              .fontColor(this.chartMode === 1 ? '#12141A' : '#9AA0A9')
              .backgroundColor(this.chartMode === 1 ? AppConfig.COLOR_ACCENT : Color.Transparent)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .margin({ left: 2 })
              .onClick(() => {
                this.setMode(1);
              })
          }
          .padding(3)
          .margin({ top: 8, right: 10 })
          .backgroundColor('rgba(244,246,250,0.96)')
          .border({ width: 1, color: '#E2E5EC' })
          .borderRadius(9)

          Row() {
            Text('← 过去')
              .fontSize(9)
              .fontColor('#B4B9C0')
            Blank()
            Text('现在 →')
              .fontSize(9)
              .fontColor('#B4B9C0')
          }
          .width('100%')
          .padding({ left: 12, right: 50, bottom: 5 })
          .align(Alignment.Bottom)
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(176)
        .margin({ left: 16, right: 16, top: 10 })

        // 快讯条（随机盘）：显示最新一条消息，5 秒后回到等待态
        if (this.mode === 'random') {
          Row({ space: 8 }) {
            Text('快讯')
              .fontSize(9)
              .fontColor('#2E9E5B')
              .backgroundColor('#E4F4EA')
              .borderRadius(6)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            Text(this.newsText)
              .fontSize(10)
              .fontColor('#7A808B')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin({ left: 16, right: 16, top: 10 })
          .backgroundColor('#F3F7F4')
          .borderRadius(14)
        }

        // 随机盘：手持股票持仓总览（点击行切换查看对应股票）
        if (this.mode === 'random') {
          Column() {
            Row() {
              Text('持仓')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppConfig.COLOR_TEXT)
              Text(`${this.positionCount()}`)
                .fontSize(9)
                .fontColor('#FFFFFF')
                .backgroundColor(AppConfig.LIGHT_ACCENT)
                .width(16)
                .height(16)
                .borderRadius(8)
                .textAlign(TextAlign.Center)
                .margin({ left: 6 })
              Blank()
              Text(`净资产 ${this.netText}`)
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
                .padding({ left: 8, right: 2, top: 4, bottom: 4 })
                .onClick(() => {
                  this.openLoan();
                })
            }
            .width('100%')

            if (this.holdingRows.length === 0) {
              Text('正在生成行情…')
                .fontSize(11)
                .fontColor('#9AA0A9')
                .width('100%')
                .margin({ top: 14 })
            } else {
              List({ scroller: this.eventScroller }) {
                ForEach(this.holdingRows, (row: HoldingRow) => {
                  ListItem() {
                    Row() {
                      Row({ space: 4 }) {
                        // 选中标识：行首金色色条（空仓/持仓行统一占位，保证对齐）
                        Column()
                          .width(3)
                          .height(13)
                          .borderRadius(2)
                          .backgroundColor(this.activeStockId === row.id ? AppConfig.COLOR_ACCENT : Color.Transparent)
                        Text(row.name)
                          .fontSize(12)
                          .fontWeight(this.activeStockId === row.id ? FontWeight.Bold : FontWeight.Normal)
                          .fontColor(AppConfig.COLOR_TEXT)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        Text(row.code)
                          .fontSize(9)
                          .fontColor('#9AA0A9')
                      }
                      .alignItems(VerticalAlign.Center)
                      .layoutWeight(2)

                      Text(row.sharesText)
                        .fontSize(11)
                        .fontColor(row.direction === 1 ? AppConfig.COLOR_UP
                          : (row.direction === -1 ? AppConfig.COLOR_DOWN : '#9AA0A9'))
                        .layoutWeight(1.5)

                      Text(row.priceText)
                        .fontSize(11)
                        .fontColor(AppConfig.COLOR_TEXT)
                        .textAlign(TextAlign.End)
                        .layoutWeight(1.1)

                      Text(row.pnlText)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(row.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
                        .textAlign(TextAlign.End)
                        .layoutWeight(1.4)
                    }
                    .width('100%')
                    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                    .borderRadius(8)
                    .backgroundColor(this.activeStockId === row.id ? '#FBF4E5' : Color.Transparent)
                    .onClick(() => {
                      this.pickStock(row.id);
                    })
                  }
                }, (row: HoldingRow) => row.id)
              }
              .width('100%')
              .height(Math.min(this.holdingRows.length, 4) * 25 + 4)
              .margin({ top: 4 })
              .scrollBar(BarState.Auto)
            }

            Row() {
              Text(`现金 ${this.cashText}`)
                .fontSize(9)
                .fontColor('#9AA0A9')
              Blank()
              Text(`负债 ${this.debtText}`)
                .fontSize(9)
                .fontColor('#9AA0A9')
              Blank()
              Text(`可卖 ${this.sellableText}`)
                .fontSize(9)
                .fontColor('#9AA0A9')
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 8 })
          .margin({ left: 16, right: 16, top: 10 })
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .border({ width: 1, color: '#E9EBF0' })
          .alignItems(HorizontalAlign.Start)
        } else {
          // 历史现场：事件累积保留，可滑动回看；无事件时显示剧本简介
          Column() {
            Row() {
              Text('历史现场')
                .fontSize(11)
                .fontColor(AppConfig.LIGHT_ACCENT)
              Blank()
              Text(this.eventList.length > 0 ? `${this.eventList.length} 条 · 上下滑动回看` : '等待历史事件')
                .fontSize(10)
                .fontColor(this.eventList.length > 0 ? '#7A808B' : '#9AA0A9')
            }
            .width('100%')

            List({ scroller: this.eventScroller }) {
              if (this.eventList.length === 0) {
                ListItem() {
                  Text(this.introText)
                    .fontSize(11)
                    .fontColor('#9AA0A9')
                    .lineHeight(17)
                    .width('100%')
                }
              } else {
                ForEach(this.eventList, (item: ScenarioEvent) => {
                  ListItem() {
                    Column() {
                      Row() {
                        Text(item.date)
                          .fontSize(10)
                          .fontColor('#7A808B')
                        Blank()
                        Text(item.title)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(AppConfig.LIGHT_ACCENT)
                      }
                      .width('100%')
                      Text(item.desc)
                        .fontSize(11)
                        .fontColor('#4A4F58')
                        .lineHeight(16)
                        .maxLines(4)
                        .margin({ top: 3 })
                        .width('100%')
                    }
                    .width('100%')
                    .padding({ top: 6, bottom: 6 })
                    .alignItems(HorizontalAlign.Start)
                  }
                }, (item: ScenarioEvent) => item.cardId)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .margin({ top: 4 })
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .height(98)
          .padding({ left: 14, right: 14, top: 8, bottom: 4 })
          .margin({ left: 16, right: 16, top: 10 })
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .border({ width: 1, color: this.eventList.length > 0 ? '#E8D9B8' : '#E9EBF0' })
          .alignItems(HorizontalAlign.Start)
        }

        if (this.mode !== 'random') {
          // 账户栏（历史剧本）：一行四列 + 资金入口
          Column() {
            Row() {
              Column() {
                Text('现金')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.cashText)
                  .fontSize(13)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text('持仓')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.sharesText)
                  .fontSize(13)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)

              Column() {
                Text('浮盈')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.pnlText)
                  .fontSize(13)
                  .fontColor(this.pnlUp ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)

              Column() {
                Text('净资产')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.netText)
                  .fontSize(13)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.End)
              .layoutWeight(1)

              Text('资金')
                .fontSize(11)
                .fontColor('#B7791F')
                .padding({ left: 12, right: 2, top: 8, bottom: 8 })
                .onClick(() => {
                  this.openLoan();
                })
            }
            .width('100%')

            Text(`负债 ${this.debtText}（息 ${this.debtInterestText}）· 手续费 ${this.feeText} · 可卖 ${this.sellableText}`)
              .fontSize(10)
              .fontColor('#9AA0A9')
              .margin({ top: 6 })
              .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })
        }

        Blank()

        // 结算入口：剧本播完或爆仓后可查看复盘
        if (this.finished || this.bankrupt) {
          Button('查看结算复盘')
            .width('100%')
            .height(38)
            .fontSize(13)
            .backgroundColor('#EFF1F5')
            .fontColor(AppConfig.LIGHT_ACCENT)
            .margin({ left: 16, right: 16, bottom: 8 })
            .onClick(() => {
              this.stopPlay();
              this.onFinish();
            })
        }

        // ===== 下单面板（可收起：默认只显示摘要行）=====
        if (this.orderExpanded) {
          Column() {
            Row() {
              Text('下单设置')
                .fontSize(11)
                .fontColor(AppConfig.COLOR_SUB)
              Blank()
              Text('收起 ⌄')
                .fontSize(10)
                .fontColor(AppConfig.LIGHT_ACCENT)
                .padding({ left: 8, right: 2, top: 4, bottom: 4 })
                .onClick(() => {
                  this.orderExpanded = false;
                })
            }
            .width('100%')

            Row() {
              Column() {
                Row() {
                  Text('投入保证金')
                    .fontSize(10)
                    .fontColor(AppConfig.COLOR_SUB)
                  Blank()
                  Text('CNY')
                    .fontSize(9)
                    .fontColor('#9AA0A9')
                }
                .width('100%')

                Row() {
                  Text('¥')
                    .fontSize(12)
                    .fontColor('#7A808B')
                    .margin({ left: 8 })
                  TextInput({ text: this.marginText })
                    .type(InputType.Number)
                    .layoutWeight(1)
                    .height(36)
                    .padding({ left: 4, right: 4 })
                    .fontSize(15)
                    .fontColor(AppConfig.COLOR_TEXT)
                    .backgroundColor(Color.Transparent)
                    .onChange((v: string) => {
                      this.setMargin(v);
                    })
                  Text('MAX')
                    .fontSize(9)
                    .fontColor('#2E9E5B')
                    .backgroundColor('#E4F4EA')
                    .borderRadius(6)
                    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                    .margin({ right: 4 })
                    .onClick(() => {
                      this.fillMarginMax();
                    })
                }
                .width('100%')
                .height(38)
                .margin({ top: 6 })
                .backgroundColor('#F4F6F9')
                .borderRadius(10)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column() {
                Row() {
                  Text('杠杆倍数')
                    .fontSize(10)
                    .fontColor(AppConfig.COLOR_SUB)
                  Blank()
                  Text(`${this.leverage}×`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppConfig.LIGHT_ACCENT)
                }
                .width('100%')

                Slider({
                  value: this.leverage,
                  min: 1,
                  max: AppConfig.MAX_LEVERAGE,
                  step: 1,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .height(28)
                  .blockColor('#FFFFFF')
                  .trackColor('#E6EAEF')
                  .selectedColor(AppConfig.LIGHT_ACCENT)
                  .margin({ top: 6 })
                  .onChange((v: number) => {
                    this.setLeverage(v);
                  })

                Row() {
                  Text('1×').fontSize(8).fontColor('#9AA0A9')
                  Blank()
                  Text('10×').fontSize(8).fontColor('#9AA0A9')
                  Blank()
                  Text('20×').fontSize(8).fontColor('#9AA0A9')
                  Blank()
                  Text('30×').fontSize(8).fontColor('#9AA0A9')
                  Blank()
                  Text('40×').fontSize(8).fontColor('#9AA0A9')
                  Blank()
                  Text('50×').fontSize(8).fontColor('#9AA0A9')
                }
                .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 16 })
            }
            .width('100%')
            .margin({ top: 10 })
            .alignItems(VerticalAlign.Top)

            Row({ space: 8 }) {
              Column() {
                Text('名义仓位')
                  .fontSize(9)
                  .fontColor('#9AA0A9')
                Text(this.notionalText)
                  .fontSize(12)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor('#F3F7F4')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Text('开仓手续费')
                  .fontSize(9)
                  .fontColor('#9AA0A9')
                Text(this.feePreviewText)
                  .fontSize(12)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor('#F3F7F4')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Text('可承受反向波动')
                  .fontSize(9)
                  .fontColor('#9AA0A9')
                Text(this.riskText)
                  .fontSize(12)
                  .fontColor(AppConfig.LIGHT_ACCENT)
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor('#F3F7F4')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.tradeTip !== '') {
              Text(this.tradeTip)
                .fontSize(10)
                .fontColor('#E64545')
                .margin({ top: 6 })
            }

            Row() {
              Blank()
              Text('一键平仓')
                .fontSize(10)
                .fontColor(AppConfig.LIGHT_ACCENT)
                .padding({ top: 6, bottom: 2, left: 8 })
                .onClick(() => {
                  this.closeAll();
                })
            }
            .width('100%')
            .margin({ top: 4 })

            Row({ space: 10 }) {
              Button(`▲ ${this.buyBtnText}`)
                .layoutWeight(1)
                .height(48)
                .fontSize(15)
                .backgroundColor('#BFE8D2')
                .fontColor('#1F6B45')
                .borderRadius(14)
                .onClick(() => {
                  this.confirmBuy();
                })
              Button(`▼ ${this.sellBtnText}`)
                .layoutWeight(1)
                .height(48)
                .fontSize(15)
                .backgroundColor('#F7D9E1')
                .fontColor('#A63D5C')
                .borderRadius(14)
                .onClick(() => {
                  this.confirmSell();
                })
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 14 })
        } else {
          // 收起态：保证金摘要 + 买卖按钮
          Row() {
            Column() {
              Text('保证金')
                .fontSize(9)
                .fontColor(AppConfig.COLOR_SUB)
              Row() {
                Text(this.marginText)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppConfig.COLOR_TEXT)
                Text(`${this.leverage}×`)
                  .fontSize(11)
                  .fontColor(AppConfig.LIGHT_ACCENT)
                  .margin({ left: 6 })
              }
              .alignItems(VerticalAlign.Bottom)
              .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Text('设置 ⌃')
              .fontSize(10)
              .fontColor(AppConfig.LIGHT_ACCENT)
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .onClick(() => {
                this.orderExpanded = true;
              })
            Button(this.buyBtnText)
              .height(36)
              .fontSize(13)
              .padding({ left: 14, right: 14 })
              .backgroundColor('#BFE8D2')
              .fontColor('#1F6B45')
              .borderRadius(12)
              .margin({ left: 2 })
              .onClick(() => {
                this.confirmBuy();
              })
            Button(this.sellBtnText)
              .height(36)
              .fontSize(13)
              .padding({ left: 14, right: 14 })
              .backgroundColor('#F7D9E1')
              .fontColor('#A63D5C')
              .borderRadius(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.confirmSell();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')

      // ===== 贷款面板 =====
      if (this.showLoan) {
        Column() {
          Column() {
            Row() {
              Text('资金与贷款')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppConfig.COLOR_TEXT)
              Blank()
              Text('✕')
                .fontSize(16)
                .fontColor(AppConfig.COLOR_SUB)
                .padding(4)
                .onClick(() => {
                  this.showLoan = false;
                })
            }
            .width('100%')

            Row() {
              Column() {
                Text('可用现金')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.cashText)
                  .fontSize(14)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text('当前负债')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.debtText)
                  .fontSize(14)
                  .fontColor('#A9701A')
                  .margin({ top: 4 })
                Text(`本金 ${this.debtPrincipalText} + 息 ${this.debtInterestText}`)
                  .fontSize(9)
                  .fontColor('#8A7B4A')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
              .layoutWeight(1)

              Column() {
                Text('可借额度')
                  .fontSize(10)
                  .fontColor(AppConfig.COLOR_SUB)
                Text(this.loanAvailText)
                  .fontSize(14)
                  .fontColor(AppConfig.COLOR_TEXT)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.End)
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 16 })

            Row() {
              Text('日息 0.032% · 年化 8% · 每个交易日复利')
                .fontSize(10)
                .fontColor('#9AA0A9')
              Blank()
              Text(`每天约 +${this.dailyInterestText}`)
                .fontSize(10)
                .fontColor(this.dailyInterestText === '0' ? '#9AA0A9' : '#A9701A')
            }
            .width('100%')
            .margin({ top: 10 })

            Row() {
              TextInput({ text: this.loanAmountText, placeholder: '金额（元）' })
                .type(InputType.Number)
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor(AppConfig.COLOR_TEXT)
                .placeholderColor('#9AA0A9')
                .backgroundColor('#F2F4F7')
                .borderRadius(8)
                .onChange((v: string) => {
                  this.loanAmountText = v;
                  this.updateLoanPreview();
                })
              Text('元')
                .fontSize(12)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 12 })

            if (this.loanPreviewText !== '') {
              Text(this.loanPreviewText)
                .fontSize(9)
                .fontColor('#8A7B4A')
                .lineHeight(15)
                .width('100%')
                .margin({ top: 6 })
            }

            Row({ space: 8 }) {
              Button('10万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#F2F4F7')
                .fontColor('#4A4F58')
                .onClick(() => {
                  this.fillLoan(100000);
                })
              Button('20万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#F2F4F7')
                .fontColor('#4A4F58')
                .onClick(() => {
                  this.fillLoan(200000);
                })
              Button('50万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#F2F4F7')
                .fontColor('#4A4F58')
                .onClick(() => {
                  this.fillLoan(500000);
                })
              Button('用完额度')
                .layoutWeight(1.4)
                .height(34)
                .fontSize(12)
                .backgroundColor('#F2F4F7')
                .fontColor(AppConfig.LIGHT_ACCENT)
                .onClick(() => {
                  this.fillLoanMax();
                })
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.loanTip !== '') {
              Text(this.loanTip)
                .fontSize(11)
                .fontColor('#E64545')
                .margin({ top: 8 })
            }

            Row({ space: 10 }) {
              Button('借入')
                .layoutWeight(1)
                .height(46)
                .fontSize(15)
                .backgroundColor(AppConfig.COLOR_ACCENT)
                .fontColor('#12141A')
                .onClick(() => {
                  this.confirmBorrow();
                })
              Button('还款')
                .layoutWeight(1)
                .height(46)
                .fontSize(15)
                .backgroundColor('#EFF1F5')
                .fontColor(AppConfig.COLOR_TEXT)
                .onClick(() => {
                  this.confirmRepay();
                })
            }
            .width('100%')
            .margin({ top: 16 })
          }
          .width('100%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 20, topRight: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(20,24,30,0.32)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}