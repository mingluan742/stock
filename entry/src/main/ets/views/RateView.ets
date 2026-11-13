import { AppConfig } from '../config/AppConfig';
import { RatePoint, RateSeries, RateService } from '../services/RateService';

/** 快捷区间 */
interface QuickRange {
  label: string;
  days: number;
}

const QUICK: QuickRange[] = [
  { label: '30天', days: 30 },
  { label: '90天', days: 90 },
  { label: '半年', days: 182 },
  { label: '一年', days: 365 }
];

/**
 * 汇率走势页（深色，与盯盘页统一）：
 * - 数据源：欧洲央行参考汇率（frankfurter 公开接口），真实数据、免 Key
 * - 货币对：美元 / 欧元 / 日元 / 英镑 / 港币 / 澳元 对人民币
 * - 区间：30 天 ~ 一年快捷选择，也可自选起止日
 */
@Component
export struct RateView {
  /** 返回主界面 */
  onBack: () => void = () => {};

  @State base: string = 'USD';
  @State activeDays: number = 90;
  @State startText: string = '';
  @State endText: string = '';
  @State loading: boolean = false;
  @State errorText: string = '';

  @State rateText: string = '--';
  @State changeText: string = '';
  @State up: boolean = true;
  @State openText: string = '--';
  @State closeText: string = '--';
  @State highText: string = '--';
  @State lowText: string = '--';
  @State volText: string = '--';
  @State countText: string = '';

  // 日期选择弹层
  @State pickerOpen: boolean = false;
  @State pickerIsStart: boolean = true;
  @State pickerDate: Date = new Date();
  @State pickTip: string = '';

  private startDate: Date = new Date();
  private endDate: Date = new Date();
  private points: RatePoint[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.setRange(90);
  }

  /** 快捷区间：结束日取今天 */
  setRange(days: number): void {
    const end: Date = new Date();
    const start: Date = new Date(end.getTime() - days * 86400000);
    this.startDate = start;
    this.endDate = end;
    this.activeDays = days;
    this.startText = RateService.fmt(start);
    this.endText = RateService.fmt(end);
    this.load();
  }

  /** 切换货币对 */
  switchBase(code: string): void {
    if (this.base === code) {
      return;
    }
    this.base = code;
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const s: RateSeries = await RateService.fetch(this.base, this.startDate, this.endDate);
      this.points = s.points;
      this.computeStats(s.points);
      this.drawChart();
    } catch (err) {
      const e = err as Error;
      this.errorText = `数据加载失败：${e.message}`;
      this.points = [];
      this.rateText = '--';
      this.countText = '';
    }
    this.loading = false;
  }

  /** 数值格式：小于 1 保留 4 位（日元等） */
  fmtRate(v: number): string {
    if (v < 1) {
      return v.toFixed(4);
    }
    return v.toFixed(2);
  }

  computeStats(pts: RatePoint[]): void {
    const n: number = pts.length;
    const first: number = pts[0].value;
    const last: number = pts[n - 1].value;
    const chg: number = (last - first) / first;
    this.rateText = this.fmtRate(last);
    this.up = chg >= 0;
    const sign: string = chg >= 0 ? '+' : '';
    this.changeText = `${sign}${(chg * 100).toFixed(2)}%`;
    this.openText = this.fmtRate(first);
    this.closeText = this.fmtRate(last);
    this.countText = `${n} 个交易日`;

    let hi: number = pts[0].value;
    let lo: number = pts[0].value;
    let hiDate: string = pts[0].date;
    let loDate: string = pts[0].date;
    for (const p of pts) {
      if (p.value > hi) {
        hi = p.value;
        hiDate = p.date;
      }
      if (p.value < lo) {
        lo = p.value;
        loDate = p.date;
      }
    }
    this.highText = `${this.fmtRate(hi)}（${hiDate.substring(5)}）`;
    this.lowText = `${this.fmtRate(lo)}（${loDate.substring(5)}）`;

    // 年化波动率：日对数收益标准差 × √250
    if (n >= 3) {
      const rets: number[] = [];
      for (let i = 1; i < n; i++) {
        rets.push(Math.log(pts[i].value / pts[i - 1].value));
      }
      let mean: number = 0;
      for (const r of rets) {
        mean += r;
      }
      mean = mean / rets.length;
      let sq: number = 0;
      for (const r of rets) {
        sq += (r - mean) * (r - mean);
      }
      const std: number = Math.sqrt(sq / rets.length);
      this.volText = `${(std * Math.sqrt(250) * 100).toFixed(2)}%`;
    } else {
      this.volText = '--';
    }
  }

  /** 打开日期选择 */
  openPicker(isStart: boolean): void {
    this.pickerIsStart = isStart;
    this.pickerDate = isStart ? this.startDate : this.endDate;
    this.pickTip = '';
    this.pickerOpen = true;
  }

  confirmPicker(): void {
    const s: Date = this.pickerIsStart ? this.pickerDate : this.startDate;
    const e: Date = this.pickerIsStart ? this.endDate : this.pickerDate;
    const days: number = RateService.dayDiff(s, e);
    if (days <= 0) {
      this.pickTip = '结束日期需要晚于开始日期';
      return;
    }
    if (days < RateService.MIN_DAYS || days > RateService.MAX_DAYS) {
      this.pickTip = `跨度需要在 ${RateService.MIN_DAYS}~${RateService.MAX_DAYS} 天之间，当前 ${days} 天`;
      return;
    }
    this.startDate = s;
    this.endDate = e;
    this.startText = RateService.fmt(s);
    this.endText = RateService.fmt(e);
    this.activeDays = 0;
    this.pickerOpen = false;
    this.load();
  }

  /** 绘制汇率曲线 */
  drawChart(): void {
    const c = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    const padL: number = 8;
    const padR: number = 8;
    const padT: number = 12;
    const padB: number = 12;
    const plotW: number = w - padL - padR;
    const plotH: number = h - padT - padB;

    c.strokeStyle = '#23272F';
    c.lineWidth = 1;
    for (let i = 0; i <= 3; i++) {
      const gy: number = padT + (plotH * i) / 3;
      c.beginPath();
      c.moveTo(padL, gy);
      c.lineTo(padL + plotW, gy);
      c.stroke();
    }

    const n: number = this.points.length;
    if (n < 2) {
      return;
    }
    let minP: number = this.points[0].value;
    let maxP: number = this.points[0].value;
    for (const p of this.points) {
      if (p.value < minP) {
        minP = p.value;
      }
      if (p.value > maxP) {
        maxP = p.value;
      }
    }
    let range: number = maxP - minP;
    if (range < maxP * 0.0005) {
      range = Math.max(0.0001, maxP * 0.0005);
    }
    minP -= range * 0.12;
    maxP += range * 0.12;
    const span: number = maxP - minP;
    const stepX: number = plotW / (n - 1);
    const rising: boolean = this.points[n - 1].value >= this.points[0].value;
    const lineColor: string = rising ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN;
    const topColor: string = rising ? 'rgba(230,69,69,0.24)' : 'rgba(46,158,91,0.24)';
    const bottomColor: string = rising ? 'rgba(230,69,69,0.02)' : 'rgba(46,158,91,0.02)';

    // 面积
    c.beginPath();
    for (let i = 0; i < n; i++) {
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - this.points[i].value) / span) * plotH;
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.lineTo(padL + plotW, padT + plotH);
    c.lineTo(padL, padT + plotH);
    c.closePath();
    const grad: CanvasGradient = c.createLinearGradient(0, padT, 0, padT + plotH);
    grad.addColorStop(0, topColor);
    grad.addColorStop(1, bottomColor);
    c.fillStyle = grad;
    c.fill();

    // 折线
    c.beginPath();
    for (let i = 0; i < n; i++) {
      const x: number = padL + i * stepX;
      const y: number = padT + ((maxP - this.points[i].value) / span) * plotH;
      if (i === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.strokeStyle = lineColor;
    c.lineWidth = 1.8;
    c.stroke();

    // 端点
    const lx: number = padL + plotW;
    const ly: number = padT + ((maxP - this.points[n - 1].value) / span) * plotH;
    c.beginPath();
    c.arc(lx, ly, 3.2, 0, Math.PI * 2);
    c.fillStyle = lineColor;
    c.fill();
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
              this.onBack();
            })
          Text('汇率走势')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppConfig.COLOR_TEXT)
            .margin({ left: 4 })
          Blank()
          Text('欧洲央行数据')
            .fontSize(10)
            .fontColor(AppConfig.COLOR_SUB)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

        // 货币对
        Scroll() {
          Row({ space: 8 }) {
            ForEach(RateService.BASES, (code: string) => {
              Column() {
                Text(code)
                  .fontSize(13)
                  .fontWeight(this.base === code ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.base === code ? '#12141A' : '#B8BDC7')
                Text('CNY')
                  .fontSize(8)
                  .fontColor(this.base === code ? '#12141A' : '#6B717C')
                  .margin({ top: 1 })
              }
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.base === code ? AppConfig.COLOR_ACCENT : '#22262F')
              .borderRadius(10)
              .onClick(() => {
                this.switchBase(code);
              })
            }, (code: string) => code)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 12 })

        // 快捷区间
        Row({ space: 8 }) {
          ForEach(QUICK, (q: QuickRange) => {
            Text(q.label)
              .fontSize(11)
              .fontColor(this.activeDays === q.days ? '#12141A' : '#8A8F99')
              .backgroundColor(this.activeDays === q.days ? '#D4A34B' : '#1E222A')
              .borderRadius(8)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.setRange(q.days);
              })
          }, (q: QuickRange) => q.label)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 10 })

        // 自选起止日
        Row() {
          Text(this.startText)
            .fontSize(11)
            .fontColor(AppConfig.COLOR_TEXT)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('#1E222A')
            .borderRadius(8)
            .onClick(() => {
              this.openPicker(true);
            })
          Text('→')
            .fontSize(11)
            .fontColor('#6B717C')
            .margin({ left: 8, right: 8 })
          Text(this.endText)
            .fontSize(11)
            .fontColor(AppConfig.COLOR_TEXT)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor('#1E222A')
            .borderRadius(8)
            .onClick(() => {
              this.openPicker(false);
            })
          Blank()
          Text(this.countText)
            .fontSize(10)
            .fontColor('#6B717C')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 10 })

        // 价格区
        Row() {
          Column() {
            Text(this.rateText)
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
            Text(`${this.base} / CNY　${this.changeText}`)
              .fontSize(12)
              .fontColor(this.up ? AppConfig.COLOR_UP : AppConfig.COLOR_DOWN)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Column() {
            Text(`波动率 ${this.volText}`)
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text('数据不加修饰')
              .fontSize(9)
              .fontColor('#5C626D')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })

        // 图表
        Stack() {
          Canvas(this.ctx)
            .width('100%')
            .height(200)
            .backgroundColor('#151821')
            .borderRadius(12)
            .onReady(() => {
              this.drawChart();
            })

          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(AppConfig.COLOR_ACCENT)
              Text('正在拉取真实汇率…')
                .fontSize(10)
                .fontColor(AppConfig.COLOR_SUB)
                .margin({ top: 8 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('rgba(21,24,33,0.86)')
            .borderRadius(12)
          }

          if (!this.loading && this.errorText !== '') {
            Column() {
              Text(this.errorText)
                .fontSize(11)
                .fontColor('#E64545')
                .textAlign(TextAlign.Center)
                .padding({ left: 20, right: 20 })
              Button('重试')
                .height(32)
                .fontSize(12)
                .margin({ top: 10 })
                .backgroundColor('#2A2F3A')
                .fontColor(AppConfig.COLOR_ACCENT)
                .onClick(() => {
                  this.load();
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('rgba(21,24,33,0.92)')
            .borderRadius(12)
          }
        }
        .width('100%')
        .height(200)
        .margin({ left: 16, right: 16, top: 12 })

        // 统计
        Row() {
          Column() {
            Text('期初')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.openText)
              .fontSize(13)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Text('期末')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.closeText)
              .fontSize(13)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)

          Column() {
            Text('最高')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.highText)
              .fontSize(12)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)

          Column() {
            Text('最低')
              .fontSize(10)
              .fontColor(AppConfig.COLOR_SUB)
            Text(this.lowText)
              .fontSize(12)
              .fontColor(AppConfig.COLOR_TEXT)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14 })

        Blank()

        Text('数据来自欧洲央行每日参考汇率，仅含交易日，周末与部分节假日无数据。')
          .fontSize(9)
          .fontColor('#5C626D')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, bottom: 20 })
      }
      .width('100%')
      .height('100%')

      // 日期选择弹层
      if (this.pickerOpen) {
        Column() {
          Column() {
            Row() {
              Text('取消')
                .fontSize(13)
                .fontColor(AppConfig.COLOR_SUB)
                .padding(8)
                .onClick(() => {
                  this.pickerOpen = false;
                })
              Blank()
              Text(this.pickerIsStart ? '选择开始日期' : '选择结束日期')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppConfig.COLOR_TEXT)
              Blank()
              Text('确定')
                .fontSize(13)
                .fontColor(AppConfig.COLOR_ACCENT)
                .padding(8)
                .onClick(() => {
                  this.confirmPicker();
                })
            }
            .width('100%')

            if (this.pickTip !== '') {
              Text(this.pickTip)
                .fontSize(10)
                .fontColor('#E64545')
                .width('100%')
                .margin({ top: 4 })
            }

            DatePicker({
              start: new Date(2015, 0, 1),
              end: new Date(),
              selected: this.pickerDate
            })
              .width('100%')
              .onDateChange((value: Date) => {
                this.pickerDate = value;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 16 })
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