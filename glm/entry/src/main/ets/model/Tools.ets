import { ToolDef } from './Types';

export function getToolDefs(): ToolDef[] {
  const emptyProps: Record<string, Object> = {};
  const parameters: Record<string, Object> = {
    'type': 'object',
    'properties': emptyProps
  };
  return [
    {
      type: 'function',
      function: {
        name: 'get_current_time',
        description: '获取当前手机系统时间，返回 ISO 标准时间、本地可读时间以及 Unix 时间戳。',
        parameters: parameters
      }
    }
  ];
}

export function executeTool(name: string, args: string): string {
  if (name === 'get_current_time') {
    return getcurrentTimeImpl();
  }
  return JSON.stringify({ error: '未知工具: ' + name });
}

function getcurrentTimeImpl(): string {
  const now: Date = new Date();
  const iso: string = now.toISOString();
  const local: string = now.toLocaleString();
  const stamp: number = now.getTime();
  const result: Record<string, Object> = {
    'iso': iso,
    'local': local,
    'timestamp': stamp
  };
  return JSON.stringify(result);
}
