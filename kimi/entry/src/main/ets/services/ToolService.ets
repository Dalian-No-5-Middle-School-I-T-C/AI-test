import { systemDateTime } from '@kit.BasicServicesKit';
import { DeepSeekTool, TimeToolParameterMap, ToolParameterProperty, ToolParameters } from '../models/ChatModels';

interface TimeToolArgs {
  format?: string;
}

interface ToolErrorResult {
  error: string;
}

interface TimeToolResult {
  current_time: string;
  timestamp: number;
}

const formatProperty: ToolParameterProperty = {
  type: 'string',
  description: 'Optional format: "iso", "locale", "time". Defaults to "locale".',
  enum: ['iso', 'locale', 'time']
};

const toolProperties: TimeToolParameterMap = {
  format: formatProperty
};

const timeToolParameters: ToolParameters = {
  type: 'object',
  properties: toolProperties,
  required: []
};

const timeTool: DeepSeekTool = {
  type: 'function',
  function: {
    name: 'get_current_system_time',
    description: 'Get the current system time of the phone. Returns a formatted date-time string.',
    parameters: timeToolParameters
  }
};

export class ToolService {
  static readonly TOOLS: DeepSeekTool[] = [timeTool];

  static executeTool(name: string, args: string): string {
    switch (name) {
      case 'get_current_system_time':
        return ToolService.getCurrentSystemTime(args);
      default:
        const errorResult: ToolErrorResult = { error: `Unknown tool: ${name}` };
        return JSON.stringify(errorResult);
    }
  }

  private static getCurrentSystemTime(args: string): string {
    let format = 'locale';
    try {
      const parsed = JSON.parse(args) as TimeToolArgs;
      if (parsed.format) {
        format = parsed.format;
      }
    } catch (e) {
      // Use default format
    }

    const nowMs = systemDateTime.getTime();
    const date = new Date(nowMs);
    let timeStr = '';
    switch (format) {
      case 'iso':
        timeStr = date.toISOString();
        break;
      case 'time':
        timeStr = date.toTimeString();
        break;
      case 'locale':
      default:
        timeStr = date.toLocaleString();
        break;
    }
    const result: TimeToolResult = { current_time: timeStr, timestamp: nowMs };
    return JSON.stringify(result);
  }
}
