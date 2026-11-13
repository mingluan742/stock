import { http } from '@kit.NetworkKit';

/** 一条对话消息 */
export interface ChatMessage {
  role: string;
  content: string;
}

/** 模型配置（保存在本机） */
export interface AiSettings {
  baseUrl: string;
  model: string;
  key: string;
}

/** 请求体 */
interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
  stream: boolean;
}

interface ChatChoice {
  message: ChatMessage;
}

interface ChatResponse {
  choices: ChatChoice[];
}

/** 复盘输入：把一局的关键数字交给模型 */
export interface ReviewInput {
  scenarioName: string;
  era: string;
  mode: string;
  /** 收益率（小数，如 -0.32） */
  returnPct: number;
  /** 同期标的涨跌（小数） */
  benchPct: number;
  /** 最大回撤（小数） */
  maxDrawdown: number;
  tradeCount: number;
  /** 胜率（小数） */
  winRate: number;
  feeTotal: number;
  maxLeverage: number;
  debt: number;
  bankrupt: boolean;
  /** 交易流水摘要，已格式化为多行文本 */
  flowText: string;
}

/**
 * 大模型服务：兼容 OpenAI 的 /chat/completions 协议
 * - 默认 DeepSeek，可在设置页改成任意兼容接口
 * - Key 只存本机，代码中不内置任何密钥
 * - 无 Key 或请求失败时抛错，由调用方退回本地文案
 */
export class AiService {
  static readonly URL_KEY: string = 'ai_base_url';
  static readonly MODEL_KEY: string = 'ai_model';
  static readonly KEY_KEY: string = 'ai_api_key';

  static readonly DEFAULT_URL: string = 'https://api.deepseek.com/v1/chat/completions';
  static readonly DEFAULT_MODEL: string = 'deepseek-chat';

  private static read(k: string, def: string): string {
    try {
      const v: string | undefined = AppStorage.get<string>(k);
      if (v === undefined || v === '') {
        return def;
      }
      return v;
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] AI 配置读取失败: ${e.message}`);
      return def;
    }
  }

  private static write(k: string, v: string): void {
    try {
      AppStorage.setOrCreate<string>(k, v);
    } catch (err) {
      const e = err as Error;
      console.info(`[StockLab] AI 配置写入失败: ${e.message}`);
    }
  }

  static get settings(): AiSettings {
    return {
      baseUrl: AiService.read(AiService.URL_KEY, AiService.DEFAULT_URL),
      model: AiService.read(AiService.MODEL_KEY, AiService.DEFAULT_MODEL),
      key: AiService.read(AiService.KEY_KEY, '')
    };
  }

  static save(url: string, model: string, key: string): void {
    AiService.write(AiService.URL_KEY, url.trim() === '' ? AiService.DEFAULT_URL : url.trim());
    AiService.write(AiService.MODEL_KEY, model.trim() === '' ? AiService.DEFAULT_MODEL : model.trim());
    AiService.write(AiService.KEY_KEY, key.trim());
  }

  static get hasKey(): boolean {
    return AiService.settings.key !== '';
  }

  /** 组装复盘提示词 */
  static buildReviewMessages(input: ReviewInput): ChatMessage[] {
    const system: string =
      '你是一名面向大学生的投资学习教练。根据用户在一款历史行情模拟 App 中的操作数据，写一段简短、克制、有教育意义的复盘点评。' +
      '要求：1. 只依据给出的数字说话，不编造行情细节；2. 指出最突出的一个问题（如重仓、追高、频繁交易、滥用杠杆、死扛不止损）；' +
      '3. 结尾给一句可执行的改进建议；4. 总字数不超过 180 字，不分点、不加标题、不使用 emoji；5. 只是学习建议，不构成投资建议。';

    const pct = (v: number): string => `${(v * 100).toFixed(2)}%`;
    const benchDiff: number = input.returnPct - input.benchPct;
    let user: string = `剧本：${input.scenarioName}（${input.era}）\n`;
    user += `模式：${input.mode === 'random' ? '随机生成市场' : '历史剧本'}\n`;
    user += `本局收益率：${pct(input.returnPct)}\n`;
    user += `同期标的涨跌：${pct(input.benchPct)}（${benchDiff >= 0 ? '跑赢' : '跑输'} ${pct(Math.abs(benchDiff))}）\n`;
    user += `最大回撤：${pct(input.maxDrawdown)}\n`;
    user += `成交笔数：${input.tradeCount} 笔，胜率：${pct(input.winRate)}\n`;
    user += `累计手续费：${Math.round(input.feeTotal)} 元\n`;
    user += `最高使用杠杆：${input.maxLeverage} 倍\n`;
    user += `最终负债：${Math.round(input.debt)} 元\n`;
    user += `是否爆仓：${input.bankrupt ? '是' : '否'}\n`;
    if (input.flowText !== '') {
      user += `交易流水（日期/方向/价格/数量/该笔已实现盈亏）：\n${input.flowText}\n`;
    }
    user += '\n请输出复盘点评。';
    return [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ];
  }

  /** 复盘点评：成功返回文本，失败抛错 */
  static async review(input: ReviewInput): Promise<string> {
    return await AiService.chat(AiService.buildReviewMessages(input));
  }

  /** 通用对话调用 */
  static async chat(messages: ChatMessage[]): Promise<string> {
    const cfg: AiSettings = AiService.settings;
    if (cfg.key === '') {
      throw new Error('未配置 API Key');
    }
    const body: ChatRequestBody = {
      model: cfg.model,
      messages: messages,
      temperature: 0.6,
      max_tokens: 500,
      stream: false
    };
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${cfg.key}`
    };
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(cfg.baseUrl, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: 15000,
        readTimeout: 40000,
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode !== 200) {
        throw new Error(`接口返回 ${resp.responseCode}`);
      }
      let text: string = '';
      if (typeof resp.result === 'string') {
        text = resp.result as string;
      } else {
        text = JSON.stringify(resp.result);
      }
      const data = JSON.parse(text) as ChatResponse;
      if (data.choices === undefined || data.choices.length === 0) {
        throw new Error('返回内容为空');
      }
      const out: string = data.choices[0].message.content;
      if (out === undefined || out.trim() === '') {
        throw new Error('返回内容为空');
      }
      return out.trim();
    } finally {
      req.destroy();
    }
  }
}