/**
 * K线数据点：剧本时间轴上的一个"交易日"
 * 注意：价格为指数点位；由 JSON 反序列化而来，保持 interface 形态
 */
export interface KLine {
  /** 日期，格式 yyyy-MM-dd */
  date: string;
  /** 收盘价（指数点位） */
  price: number;
  /** 关键节点备注，普通节点为空字符串 */
  note: string;
}