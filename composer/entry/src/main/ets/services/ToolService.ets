export interface ToolParameterProperty {
  type: string;
  description: string;
}

export interface ToolFunctionDefinition {
  name: string;
  description: string;
  parameters: ToolFunctionDefinitionParams;
}

export interface ToolFunctionDefinitionParams {
  type: string;
  properties: Record<string, ToolParameterProperty>;
  required: string[];
}

export interface ToolDefinition {
  type: string;
  function: ToolFunctionDefinition;
}

export class ToolService {
  static executeTool(name: string, args: string): string {
    switch (name) {
      case 'get_current_time':
        return ToolService.getCurrentTime();
      default:
        return JSON.stringify({ error: `Unknown tool: ${name}` });
    }
  }

  static getToolDefinitions(): ToolDefinition[] {
    let params: ToolFunctionDefinitionParams = {
      type: 'object',
      properties: {} as Record<string, ToolParameterProperty>,
      required: []
    };
    let funcDef: ToolFunctionDefinition = {
      name: 'get_current_time',
      description: '获取当前手机系统时间，返回包含时间戳和格式化时间的 JSON 对象',
      parameters: params
    };
    let toolDef: ToolDefinition = {
      type: 'function',
      function: funcDef
    };
    return [toolDef];
  }

  private static getCurrentTime(): string {
    let now = new Date();
    let year = now.getFullYear();
    let month = String(now.getMonth() + 1).padStart(2, '0');
    let day = String(now.getDate()).padStart(2, '0');
    let hours = String(now.getHours()).padStart(2, '0');
    let minutes = String(now.getMinutes()).padStart(2, '0');
    let seconds = String(now.getSeconds()).padStart(2, '0');
    let formatted = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    return JSON.stringify({
      time: formatted,
      timestamp: now.getTime(),
      timezone: ''
    });
  }
}
