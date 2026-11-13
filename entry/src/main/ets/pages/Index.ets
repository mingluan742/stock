import { AppConfig } from '../config/AppConfig';
import { AppContext } from '../core/AppContext';
import { Result } from '../core/Result';
import { Account } from '../models/Account';
import { KLine } from '../models/KLine';
import { ScenarioData } from '../models/Scenario';
import { ScenarioEvent } from '../models/ScenarioEvent';

/** 路由参数：mode = history（历史剧本）| random（随机模拟） */
interface TradeRouteParams {
  mode: string;
  id: string;
}

/** 图表最多同时显示的样本数（超出后向左滚动） */
const MAX_POINTS: number = 60;
/** K线视口显示的蜡烛根数 */
const CANDLE_POINTS: number = 42;
/** 每个"交易日"的播放间隔（毫秒）：400ms 为基准，0.75 倍速 ≈ 533ms */
const TICK_MS: number = 533;

/**
 * 实时盯盘页：
 * - 定时器每 400ms 推进一个交易日，Canvas 分时曲线持续向右生长
 * - 买卖按钮常驻，随时可操作，账户现金/持仓/浮盈实时刷新
 * - 走到历史事件日自动暂停，弹出"历史现场"，关闭后继续
 */
@Entry
@Component
struct Index {
  @State scenarioName: string = '加载中…';
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

  // 交易面板
  @State showTrade: boolean = false;
  @State tradeSide: number = 0; // 0 = 买入，1 = 卖出
  @State tradeQtyText: string = '100';
  @State tradeTip: string = '';
  @State tradeSummary: string = '';

  // 贷款面板
  @State showLoan: boolean = false;
  @State loanAmountText: string = '100000';
  @State loanTip: string = '';

  @State eventList: ScenarioEvent[] = [];
  @State introText: string = '';

  private prices: number[] = [];
  private currentPrice: number = 0;
  private lastRatio: number = 0;
  private timerId: number = -1;
  private mode: string = 'history';
  private scenarioId: string = AppConfig.DEFAULT_SCENARIO;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private eventScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      AppContext.init(host.resourceManager);
    }
    this.readRouteParams();
    if (this.mode === 'random') {
      this.loadRandom();
    } else {
      this.loadScenario(this.scenarioId);
    }
  }

  /** 读取主界面传来的路由参数 */
  readRouteParams(): void {
    try {
      const params = this.getUIContext().getRouter().getParams() as TradeRouteParams;
      if (params !== undefined && params !== null) {
        if (params.mode !== undefined && params.mode !== null) {
          this.mode = params.mode;
        }
        if (params.id !== undefined && params.id !== null && params.id !== '') {
          this.scenarioId = params.id;
        }
      }
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] 无路由参数，使用默认剧本: ${e.message}`);
    }
  }

  aboutToDisappear(): void {
    this.stopPlay();
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

  /** 生成并载入一局随机行情 */
  loadRandom(): void {
    try {
      const data: ScenarioData = AppContext.getRandom().generate();
      AppContext.getMarket().loadData(data);
      this.applyLoaded();
    } catch (err) {
      const e = err as Error;
      this.scenarioName = `生成失败：${e.message}`;
    }
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
    this.bankrupt = false;
    this.showTrade = false;
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
    this.prices = [];
    const bar: KLine | null = market.currentBar;
    if (bar !== null) {
      this.prices.push(bar.price);
      this.currentPrice = bar.price;
    }
    this.finished = false;
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

  togglePause(): void {
    if (this.finished) {
      this.replay();
      return;
    }
    this.paused = !this.paused;
  }

  /** 把事件累积进列表并滚到底部 */
  appendEvents(events: ScenarioEvent[]): void {
    if (events.length === 0) {
      return;
    }
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
    this.eventList = [];
    this.appendEvents(market.eventsToday()); // 补出第 1 天事件
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
    this.syncMarketText();
    this.syncAccount();
    this.drawChart();
    if (trading.bankrupt(bar.price) && !this.bankrupt) {
      this.bankrupt = true;
      this.paused = true;
      this.progressText = '已爆仓';
      this.showTip('净资产归零，已爆仓');
    }
    if (market.finished) {
      this.finished = true;
      this.stopPlay();
      this.progressText = '剧本终结';
    }
    if (events.length > 0) {
      // 不打断行情：事件累积到历史现场列表，可滑动回看
      this.appendEvents(events);
    }
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
      this.progressText = `第 ${market.dayIndex + 1} / ${market.totalDays} 交易日`;
    }
  }

  syncAccount(): void {
    const t = AppContext.getTrading();
    this.cashText = this.formatMoney(t.cash);
    this.sharesText = `${t.shares} 股`;
    if (t.shares !== 0) {
      this.avgCostText = t.shares > 0 ? `成本 ${t.avgCost.toFixed(2)}` : `卖空均价 ${t.avgCost.toFixed(2)}`;
      const pnl: number = t.pnl(this.currentPrice);
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
    this.sellableText = `${t.sellableShares} 股`;
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

  /** 统一 Toast，内部捕获异常，使用组件上下文推荐写法 */
  showTip(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1400 });
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] toast 失败: ${e.message}`);
    }
  }

  // ===== 交易面板 =====

  /** 打开交易面板 */
  openTrade(side: number): void {
    if (this.bankrupt) {
      this.showTip('已爆仓，请重开一局');
      return;
    }
    this.tradeSide = side;
    this.tradeQtyText = side === 0 ? '100' : '100';
    this.tradeTip = '';
    this.updateTradeSummary();
    this.showTrade = true;
  }

  parseQty(): number {
    const n: number = parseInt(this.tradeQtyText, 10);
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

  /** 交易面板实时费用预览 */
  updateTradeSummary(): void {
    const qty: number = this.parseQty();
    const amount: number = this.currentPrice * qty;
    const fee: number = amount * this.currentFeeRate();
    this.tradeSummary = `金额 ${this.formatMoney(amount)} · 手续费 ${fee.toFixed(2)}`;
  }

  fillQty(qty: number): void {
    this.tradeQtyText = `${qty}`;
    this.updateTradeSummary();
  }

  fillAll(): void {
    const t = AppContext.getTrading();
    if (this.tradeSide === 0) {
      this.fillQty(t.maxBuyable(this.currentPrice));
    } else {
      this.fillQty(t.sellableShares);
    }
  }

  confirmTrade(): void {
    const qty: number = this.parseQty();
    if (qty <= 0) {
      this.tradeTip = '请输入有效数量';
      return;
    }
    const t = AppContext.getTrading();
    const r: Result<Account> = this.tradeSide === 0
      ? t.buy(this.currentPrice, qty, this.lastRatio)
      : t.sell(this.currentPrice, qty, this.lastRatio);
    if (r.ok) {
      this.showTrade = false;
      this.showTip(this.tradeSide === 0 ? `买入 ${qty} 股成交` : `卖出 ${qty} 股成交`);
      this.syncAccount();
    } else {
      this.tradeTip = r.message;
    }
  }

  // ===== 贷款面板 =====

  openLoan(): void {
    this.loanTip = '';
    this.loanAmountText = '100000';
    this.showLoan = true;
  }

  fillLoan(v: number): void {
    this.loanAmountText = `${v}`;
  }

  fillLoanMax(): void {
    this.loanAmountText = `${Math.round(AppContext.getTrading().loanAvailable)}`;
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
    const padR: number = 6;
    const padT: number = 8;
    const padB: number = 8;
    const plotW: number = w - padL - padR;
    const plotH: number = h - padT - padB;
    c.clearRect(0, 0, w, h);

    // 网格（两种模式共用）
    c.strokeStyle = '#23272F';
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
    const up: boolean = this.lastRatio >= 0;
    const lineColor: string = up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
    const topColor: string = up ? 'rgba(230,69,69,0.30)' : 'rgba(46,158,91,0.30)';
    const bottomColor: string = up ? 'rgba(230,69,69,0.02)' : 'rgba(46,158,91,0.02)';

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
              this.getUIContext().getRouter().back();
            })
          Text(AppConfig.APP_NAME)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
            .margin({ left: 4 })
          Blank()
          Text(this.scenarioName)
            .fontSize(12)
            .fontColor(AppConfig.COLOR_ACCENT)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

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

          Column() {
            Text(this.progressText)
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.eraText)
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10 })

        // 实时走势图（右上角切换分时 / K线）
        Stack({ alignContent: Alignment.TopEnd }) {
          Canvas(this.ctx)
            .width('100%')
            .height(192)
            .backgroundColor('#151821')
            .borderRadius(12)
            .onReady(() => {
              this.drawChart();
            })

          Row() {
            Text('分时')
              .fontSize(10)
              .fontColor(this.chartMode === 0 ? '#12141A' : '#8A8F99')
              .backgroundColor(this.chartMode === 0 ? AppConfig.COLOR_ACCENT : Color.Transparent)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .onClick(() => {
                this.setMode(0);
              })
            Text('K线')
              .fontSize(10)
              .fontColor(this.chartMode === 1 ? '#12141A' : '#8A8F99')
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
          .backgroundColor('rgba(24,28,36,0.85)')
          .borderRadius(9)
        }
        .width('100%')
        .height(192)
        .margin({ left: 16, right: 16, top: 12 })

        // 历史现场：事件累积保留，可滑动回看；无事件时显示剧本简介
        Column() {
          Row() {
            Text('历史现场')
              .fontSize(11)
              .fontColor(AppConfig.COLOR_ACCENT)
            Blank()
            Text(this.eventList.length > 0 ? `${this.eventList.length} 条 · 上下滑动回看` : '等待历史事件')
              .fontSize(10)
              .fontColor(this.eventList.length > 0 ? '#8A8F99' : '#6B717C')
          }
          .width('100%')

          List({ scroller: this.eventScroller }) {
            if (this.eventList.length === 0) {
              ListItem() {
                Text(this.introText)
                  .fontSize(11)
                  .fontColor('#6B717C')
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
                        .fontColor(AppConfig.COLOR_ACCENT)
                    }
                    .width('100%')
                    Text(item.desc)
                      .fontSize(11)
                      .fontColor('#B8BDC7')
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
        .height(136)
        .padding({ left: 14, right: 14, top: 10, bottom: 6 })
        .margin({ left: 16, right: 16, top: 10 })
        .backgroundColor('#181C24')
        .borderRadius(12)
        .border({ width: 1, color: this.eventList.length > 0 ? '#4A3F2A' : '#22262F' })
        .alignItems(HorizontalAlign.Start)

        // 账户栏：第一行资金/持仓，第二行净值/负债/手续费
        Column() {
          Row() {
            Column() {
              Text('现金')
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
              Text('持仓')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
              Text(this.sharesText)
                .fontSize(14)
                .fontColor(AppConfig.COLOR_TEXT)
                .margin({ top: 4 })
              Text(this.avgCostText)
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column() {
              Text('浮动盈亏')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
              Text(this.pnlText)
                .fontSize(14)
                .fontColor(this.pnlUp ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.End)
            .layoutWeight(1)
          }
          .width('100%')

          Divider()
            .color('#23272F')
            .margin({ top: 8, bottom: 8 })

          Row() {
            Column() {
              Text('净资产')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
              Text(this.netText)
                .fontSize(13)
                .fontColor(AppConfig.COLOR_TEXT)
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text('负债')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
              Text(this.debtText)
                .fontSize(13)
                .fontColor('#C9A227')
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column() {
              Text('手续费')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
              Text(this.feeText)
                .fontSize(13)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.End)
            .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10 })

        Blank()

        // 操作区：播放控制 / 买入 / 卖出 / 资金
        Row({ space: 8 }) {
          Button(this.finished ? (this.mode === 'random' ? '再来一局' : '重播剧情') : (this.paused ? '继续播放' : '暂停播放'))
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .backgroundColor('#2A2F3A')
            .fontColor(AppConfig.COLOR_ACCENT)
            .onClick(() => {
              this.togglePause();
            })
          Button('买入')
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .backgroundColor(AppConfig.COLOR_UP)
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.openTrade(0);
            })
          Button('卖出')
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .backgroundColor(AppConfig.COLOR_DOWN)
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.openTrade(1);
            })
          Button('资金')
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .backgroundColor('#2A2F3A')
            .fontColor('#D4A34B')
            .onClick(() => {
              this.openLoan();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      }
      .width('100%')
      .height('100%')

      // ===== 交易面板 =====
      if (this.showTrade) {
        Column() {
          Column() {
            Row() {
              Text(this.tradeSide === 0 ? '买入' : '卖出')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tradeSide === 0 ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              Blank()
              Text('✕')
                .fontSize(16)
                .fontColor(AppConfig.COLOR_SUB)
                .padding(4)
                .onClick(() => {
                  this.showTrade = false;
                })
            }
            .width('100%')

            Text(this.tradeSide === 0
              ? `现价 ${this.priceText} · 可用现金 ${this.cashText}`
              : `现价 ${this.priceText} · 可卖 ${this.sellableText}`)
              .fontSize(11)
              .fontColor(AppConfig.COLOR_SUB)
              .margin({ top: 8 })

            Row() {
              TextInput({ text: this.tradeQtyText, placeholder: '数量（股）' })
                .type(InputType.Number)
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor(AppConfig.COLOR_TEXT)
                .placeholderColor('#6B717C')
                .backgroundColor('#262B35')
                .borderRadius(8)
                .onChange((v: string) => {
                  this.tradeQtyText = v;
                  this.updateTradeSummary();
                })
              Text('股')
                .fontSize(12)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 12 })

            Row({ space: 8 }) {
              Button('100')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillQty(100);
                })
              Button('500')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillQty(500);
                })
              Button('1000')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillQty(1000);
                })
              Button('全仓')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor(AppConfig.COLOR_ACCENT)
                .onClick(() => {
                  this.fillAll();
                })
            }
            .width('100%')
            .margin({ top: 10 })

            Text(this.tradeSummary)
              .fontSize(11)
              .fontColor('#8A8F99')
              .margin({ top: 10 })

            if (this.tradeTip !== '') {
              Text(this.tradeTip)
                .fontSize(11)
                .fontColor(AppConfig.COLOR_UP)
                .margin({ top: 8 })
            }

            Button(this.tradeSide === 0 ? '确认买入' : '确认卖出')
              .width('100%')
              .height(46)
              .fontSize(15)
              .margin({ top: 16 })
              .backgroundColor(this.tradeSide === 0 ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.confirmTrade();
              })
          }
          .width('100%')
          .padding(20)
          .backgroundColor('#1C1F27')
          .borderRadius({ topLeft: 20, topRight: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0,0,0,0.55)')
      }

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
                  .fontColor('#C9A227')
                  .margin({ top: 4 })
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

            Text('年化 8%，每个交易日按复利计息')
              .fontSize(10)
              .fontColor('#6B717C')
              .margin({ top: 10 })

            Row() {
              TextInput({ text: this.loanAmountText, placeholder: '金额（元）' })
                .type(InputType.Number)
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor(AppConfig.COLOR_TEXT)
                .placeholderColor('#6B717C')
                .backgroundColor('#262B35')
                .borderRadius(8)
                .onChange((v: string) => {
                  this.loanAmountText = v;
                })
              Text('元')
                .fontSize(12)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 12 })

            Row({ space: 8 }) {
              Button('10万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillLoan(100000);
                })
              Button('20万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillLoan(200000);
                })
              Button('50万')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor('#B8BDC7')
                .onClick(() => {
                  this.fillLoan(500000);
                })
              Button('用完额度')
                .layoutWeight(1.4)
                .height(34)
                .fontSize(12)
                .backgroundColor('#262B35')
                .fontColor(AppConfig.COLOR_ACCENT)
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
                .backgroundColor('#2A2F3A')
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
          .backgroundColor('#1C1F27')
          .borderRadius({ topLeft: 20, topRight: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0,0,0,0.55)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppConfig.COLOR_BG)
  }
}