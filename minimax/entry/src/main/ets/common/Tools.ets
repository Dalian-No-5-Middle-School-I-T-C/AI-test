export class ToolStringParam {
  type: 'string' = 'string';
  description: string = '';
}

export class ToolFormatParam {
  type: 'string' = 'string';
  enum: string[] = ['iso', 'human'];
  description: string = '';
}

export class ToolParametersProps {
  timezone: ToolStringParam = new ToolStringParam();
  format: ToolFormatParam = new ToolFormatParam();
}

export class ToolParameters {
  type: 'object' = 'object';
  properties: ToolParametersProps = new ToolParametersProps();
  required: string[] = [];
}

export class ToolFunctionDef {
  name: string = '';
  description: string = '';
  parameters: ToolParameters = new ToolParameters();
}

export class ToolDefinition {
  type: 'function' = 'function';
  function: ToolFunctionDef = new ToolFunctionDef();
}

export class ToolCallRequest {
  id: string = '';
  name: string = '';
  rawArgs: string = '';
}

export class ToolExecResult {
  name: string = '';
  result: string = '';
}

function buildCurrentTimeTool(): ToolDefinition {
  const def = new ToolDefinition();
  def.function.name = 'get_current_time';
  def.function.description = '获取当前手机的系统时间,返回 ISO8601 格式字符串与本地可读时间。';
  def.function.parameters.properties.timezone.description =
    '可选的 IANA 时区标识,例如 Asia/Shanghai。若省略则使用设备本地时区。';
  def.function.parameters.properties.format.enum = ['iso', 'human'];
  def.function.parameters.properties.format.description =
    '返回时间格式。iso=ISO8601 字符串,human=人类可读字符串。默认 human。';
  return def;
}

export const AVAILABLE_TOOLS: ToolDefinition[] = [
  buildCurrentTimeTool()
];

export function toolNames(): string[] {
  const out: string[] = [];
  for (let i = 0; i < AVAILABLE_TOOLS.length; i++) {
    out.push(AVAILABLE_TOOLS[i].function.name);
  }
  return out;
}

class ParsedToolArgs {
  timezone: string = '';
  format: string = '';
}

function parseToolArgs(raw: string): ParsedToolArgs {
  const out = new ParsedToolArgs();
  if (raw.length === 0) {
    return out;
  }
  try {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    if (parsed['timezone'] !== undefined && typeof parsed['timezone'] === 'string') {
      out.timezone = parsed['timezone'] as string;
    }
    if (parsed['format'] !== undefined && typeof parsed['format'] === 'string') {
      out.format = parsed['format'] as string;
    }
  } catch (e) {
  }
  return out;
}

export function executeToolCall(call: ToolCallRequest): ToolExecResult {
  if (call.name === 'get_current_time') {
    const args = parseToolArgs(call.rawArgs);
    return getCurrentTimeResult(args);
  }
  const errObj = new StringMap();
  errObj.entries['error'] = `unknown tool: ${call.name}`;
  const r = new ToolExecResult();
  r.name = call.name;
  r.result = JSON.stringify(errObj.entries);
  return r;
}

class StringMap {
  entries: Record<string, string> = {};
}

class TimeResultMap {
  entries: Record<string, string> = {};
}

function getCurrentTimeResult(args: ParsedToolArgs): ToolExecResult {
  const now = new Date();
  const iso = now.toISOString();
  const human = formatHuman(now);
  const tz = args.timezone;
  let tzLabel = '';
  let tzHuman = human;
  if (tz.length > 0) {
    tzLabel = tz;
    tzHuman = `${human} (${tz})`;
  }
  const fmt = (args.format.length === 0 ? 'human' : args.format).toLowerCase();
  const out = new TimeResultMap();
  out.entries['iso'] = iso;
  out.entries['human'] = human;
  out.entries['unix_ms'] = now.getTime().toString();
  if (tzLabel.length > 0) {
    out.entries['timezone'] = tzLabel;
    out.entries['timezone_human'] = tzHuman;
  }
  if (fmt === 'iso') {
    out.entries['result'] = iso;
  } else {
    out.entries['result'] = tzHuman;
  }
  const r = new ToolExecResult();
  r.name = 'get_current_time';
  r.result = JSON.stringify(out.entries);
  return r;
}

function formatHuman(d: Date): string {
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}