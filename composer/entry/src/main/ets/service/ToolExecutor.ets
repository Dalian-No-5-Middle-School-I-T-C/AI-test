import { ToolCall } from '../model/ChatModels';

export interface ToolDefinition {
  type: string;
  function: ToolFunctionDef;
}

export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: ToolParameters;
}

export interface ToolParameters {
  type: string;
  properties: Record<string, string>;
  required: string[];
}

export const AVAILABLE_TOOLS: ToolDefinition[] = [
  {
    type: 'function',
    function: {
      name: 'get_current_time',
      description: 'Get the current system date and time of the user\'s phone.',
      parameters: {
        type: 'object',
        properties: {},
        required: [],
      },
    },
  },
];

function getCurrentTime(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const weekday = weekdays[now.getDay()];
  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds} (${weekday})`;
}

export function executeTool(name: string, _argsJson: string): string {
  if (name === 'get_current_time') {
    return JSON.stringify({ current_time: getCurrentTime(), timezone: 'local' });
  }
  return JSON.stringify({ error: `Unknown tool: ${name}` });
}

export function executeToolCalls(toolCalls: ToolCall[]): Map<string, string> {
  const results = new Map<string, string>();
  for (const tc of toolCalls) {
    const result = executeTool(tc.function.name, tc.function.arguments);
    results.set(tc.id, result);
  }
  return results;
}
