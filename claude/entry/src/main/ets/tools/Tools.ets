// 工具定义与执行

// 工具的 JSON Schema 定义（OpenAI 兼容 function calling 格式）
export interface ToolParameterProperty {
  type: string;
  description: string;
}

// 用具体接口描述属性集合，避免 Record<string, 接口> 触发 arkts-no-untyped-obj-literals
export interface TimeToolProperties {
  timezone: ToolParameterProperty;
}

export interface ToolParameters {
  type: string;
  properties: TimeToolProperties;
  required: string[];
}

export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: ToolParameters;
}

export interface ToolDef {
  type: string;
  function: ToolFunctionDef;
}

// 获取当前系统时间工具的定义
export const GET_CURRENT_TIME_TOOL: ToolDef = {
  type: 'function',
  function: {
    name: 'get_current_time',
    description: '获取用户手机当前的系统日期和时间。当用户询问现在几点、今天日期等与当前时间相关的问题时调用此工具。',
    parameters: {
      type: 'object',
      properties: {
        timezone: {
          type: 'string',
          description: '时区描述（可选），例如 "本地"。本工具始终返回设备本地时间。'
        }
      },
      required: []
    }
  }
};

// 提供给 API 的全部可用工具列表
export const AVAILABLE_TOOLS: ToolDef[] = [GET_CURRENT_TIME_TOOL];

// 工具执行结果
export interface ToolExecResult {
  // 返回给模型的字符串内容
  content: string;
  // 给 UI 展示的可读标签
  label: string;
}

// 格式化当前时间
function formatNow(): string {
  const d = new Date();
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  const weekDays: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  const year = d.getFullYear();
  const month = pad(d.getMonth() + 1);
  const day = pad(d.getDate());
  const hour = pad(d.getHours());
  const minute = pad(d.getMinutes());
  const second = pad(d.getSeconds());
  const week = weekDays[d.getDay()];
  return `${year}-${month}-${day} ${hour}:${minute}:${second} ${week}`;
}

// 根据工具名执行工具，返回结果
export function executeTool(name: string, argsJson: string): ToolExecResult {
  if (name === 'get_current_time') {
    const now = formatNow();
    const payload: Record<string, string> = {
      'current_time': now,
      'timezone': '设备本地时区'
    };
    return {
      content: JSON.stringify(payload),
      label: `获取当前时间 → ${now}`
    };
  }
  // 未知工具
  const errPayload: Record<string, string> = { 'error': `未知工具: ${name}` };
  return {
    content: JSON.stringify(errPayload),
    label: `未知工具调用: ${name}`
  };
}
