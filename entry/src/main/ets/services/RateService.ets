import { http } from '@kit.NetworkKit';

/** 一个汇率数据点 */
export interface RatePoint {
  date: string;
  value: number;
}

/** 一段汇率序列 */
export interface RateSeries {
  base: string;
  quote: string;
  points: RatePoint[];
  start: string;
  end: string;
}

/** frankfurter 返回结构 */
interface FrankfurterResp {
  base: string;
  start_date: string;
  end_date: string;
  rates: Record<string, Record<string, number>>;
}

/**
 * 汇率数据服务：欧洲央行参考汇率（经 frankfurter.app 公开接口）
 * - 免 Key、免注册，只覆盖工作日
 * - 只做取数与排序，不做任何缓存写入，保证"真实数据"
 */
export class RateService {
  static readonly HOST: string = 'https://api.frankfurter.app';
  /** 可查询的货币（对人民币） */
  static readonly BASES: string[] = ['USD', 'EUR', 'JPY', 'GBP', 'HKD', 'AUD'];
  /** 单次查询允许的最短/最长跨度（天） */
  static readonly MIN_DAYS: number = 30;
  static readonly MAX_DAYS: number = 365;

  /** 格式化为 YYYY-MM-DD */
  static fmt(d: Date): string {
    const y: string = `${d.getFullYear()}`;
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const ms: string = m < 10 ? `0${m}` : `${m}`;
    const ds: string = day < 10 ? `0${day}` : `${day}`;
    return `${y}-${ms}-${ds}`;
  }

  /** 两个日期相差的自然日 */
  static dayDiff(a: Date, b: Date): number {
    return Math.round((b.getTime() - a.getTime()) / 86400000);
  }

  /** 拉取区间汇率，按日期升序返回 */
  static async fetch(base: string, start: Date, end: Date): Promise<RateSeries> {
    const s: string = RateService.fmt(start);
    const e: string = RateService.fmt(end);
    const url: string = `${RateService.HOST}/${s}..${e}?from=${base}&to=CNY`;
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 12000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode !== 200) {
        throw new Error(`数据源返回 ${resp.responseCode}`);
      }
      let text: string = '';
      if (typeof resp.result === 'string') {
        text = resp.result as string;
      } else {
        text = JSON.stringify(resp.result);
      }
      const data = JSON.parse(text) as FrankfurterResp;
      if (data.rates === undefined) {
        throw new Error('返回内容为空');
      }
      const dates: string[] = Object.keys(data.rates);
      dates.sort();
      const points: RatePoint[] = [];
      for (const d of dates) {
        const row: Record<string, number> = data.rates[d];
        const v: number = row['CNY'];
        if (v !== undefined) {
          points.push({ date: d, value: v });
        }
      }
      if (points.length < 2) {
        throw new Error('该区间没有可用数据');
      }
      return {
        base: data.base,
        quote: 'CNY',
        points: points,
        start: s,
        end: e
      };
    } finally {
      req.destroy();
    }
  }
}