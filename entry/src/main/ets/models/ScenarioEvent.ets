/**
 * 剧情的"历史现场"事件节点：时间轴走到该日期时触发
 */
export interface ScenarioEvent {
  /** 触发日期，必须与 timeline 中某个节点日期完全一致 */
  date: string;
  /** 事件标题 */
  title: string;
  /** 事件说明（人话翻译，学习卡片联动用） */
  desc: string;
  /** 关联的学习卡片 id，后续学习功能使用 */
  cardId: string;
}