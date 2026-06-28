export class FunctionParameters {
  type: string = 'object';
  properties: Record<string, Object> = {};
  required: string[] = [];
}

export class FunctionDefinition {
  name: string = 'get_current_time';
  description: string = 'Get the current mobile device system date and time.';
  parameters: FunctionParameters = new FunctionParameters();
}

export class ToolDefinition {
  type: string = 'function';
  function: FunctionDefinition = new FunctionDefinition();
}

export const TimeToolDefinition = new ToolDefinition();

export class TimeToolResult {
  status: string = '';
  message?: string;
  current_time?: string;
  day_of_week?: string;
  timezone_offset?: number;
}

export function executeTimeTool(): string {
  try {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    
    // Day of week
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const dayOfWeek = days[now.getDay()];

    const res = new TimeToolResult();
    res.status = 'success';
    res.current_time = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    res.day_of_week = dayOfWeek;
    res.timezone_offset = now.getTimezoneOffset();

    return JSON.stringify(res);
  } catch (e) {
    const res = new TimeToolResult();
    res.status = 'error';
    res.message = `Failed to retrieve system time: ${JSON.stringify(e)}`;
    return JSON.stringify(res);
  }
}
