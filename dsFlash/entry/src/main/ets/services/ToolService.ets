import { ToolDefinition, ToolFunctionDef } from '../models/ChatModels';

export class ToolService {
  static getToolDefinitions(): ToolDefinition[] {
    const func: ToolFunctionDef = {
      name: 'get_system_time',
      description: 'Get the current system date and time of the phone',
      parameters: {
        type: 'object',
        properties: {},
        required: []
      }
    };
    const def: ToolDefinition = {
      type: 'function',
      function: func
    };
    return [def];
  }

  static executeTool(toolName: string, args: string): string {
    if (toolName === 'get_system_time') {
      return ToolService.getSystemTime();
    }
    return 'Unknown tool: ' + toolName + '. No implementation found.';
  }

  private static getSystemTime(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    const hours = now.getHours().toString().padStart(2, '0');
    const minutes = now.getMinutes().toString().padStart(2, '0');
    const seconds = now.getSeconds().toString().padStart(2, '0');
    const weekDays: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const weekDay = weekDays[now.getDay()];
    const result = 'Current system time: ' + year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds + ' (' + weekDay + ')';
    return result;
  }
}
