import { ToolDefinition, ToolFunctionDef, ToolParameters } from '../models/ChatModels';

export class ToolService {
  static getToolDefinitions(): ToolDefinition[] {
    const params: ToolParameters = {
      type: 'object',
      properties: {},
      required: []
    };
    const func: ToolFunctionDef = {
      name: 'get_system_time',
      description: 'Get the current system date and time of the phone',
      parameters: params
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
    const now: Date = new Date();
    const year: string = now.getFullYear().toString();
    const month: string = (now.getMonth() + 1).toString().padStart(2, '0');
    const day: string = now.getDate().toString().padStart(2, '0');
    const hours: string = now.getHours().toString().padStart(2, '0');
    const minutes: string = now.getMinutes().toString().padStart(2, '0');
    const seconds: string = now.getSeconds().toString().padStart(2, '0');
    const weekDays: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const weekDay: string = weekDays[now.getDay()];
    return 'Current system time: ' + year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds + ' (' + weekDay + ')';
  }
}
