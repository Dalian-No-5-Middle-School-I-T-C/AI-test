import { ToolCall } from '../model/ChatModels';

interface TimeResult {
  current_time: string;
  timezone: string;
  format: string;
}

interface ErrorResult {
  error: string;
}

interface ParsedArgs {
  format?: string;
}

export function executeToolCall(toolCall: ToolCall): string {
  const name = toolCall.functionName;
  let format = 'full';
  try {
    if (toolCall.functionArgs.length > 0) {
      const parsed = JSON.parse(toolCall.functionArgs) as ParsedArgs;
      if (parsed.format) {
        format = parsed.format;
      }
    }
  } catch (e) {
    console.error('Failed to parse tool args');
  }

  switch (name) {
    case 'get_current_time':
      return handleGetCurrentTime(format);
    default: {
      const err: ErrorResult = { error: 'Unknown tool: ' + name };
      return JSON.stringify(err);
    }
  }
}

function handleGetCurrentTime(format: string): string {
  const now = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
  const year = now.getFullYear().toString();
  const month = pad(now.getMonth() + 1);
  const day = pad(now.getDate());
  const hours = pad(now.getHours());
  const minutes = pad(now.getMinutes());
  const seconds = pad(now.getSeconds());

  let result = '';
  switch (format) {
    case 'date':
      result = year + '-' + month + '-' + day;
      break;
    case 'time':
      result = hours + ':' + minutes + ':' + seconds;
      break;
    case 'full':
    default:
      result = year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds;
      break;
  }

  const tr: TimeResult = {
    current_time: result,
    timezone: 'local',
    format: format
  };
  return JSON.stringify(tr);
}
