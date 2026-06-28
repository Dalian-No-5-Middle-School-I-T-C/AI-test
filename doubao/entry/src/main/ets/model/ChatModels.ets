export interface TimeToolParamProperties {
  format: TimeToolFormatProp;
}

export interface TimeToolFormatProp {
  type: string;
  description: string;
  enum: string[];
}

export interface ToolParameters {
  type: string;
  properties: TimeToolParamProperties;
  required: string[];
}

export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: ToolParameters;
}

export interface ToolDefinition {
  type: string;
  function: ToolFunctionDef;
}

@Observed
export class ChatMessage {
  id: string = '';
  role: Role = Role.USER;
  content: string = '';
  thinking: string = '';
  thinkingExpanded: boolean = false;
  isStreaming: boolean = false;
  toolCalls: ToolCall[] = [];
  toolCallId: string = '';
  timestamp: number = 0;

  constructor(role: Role, content: string = '', toolCallId: string = '') {
    this.id = Date.now().toString() + Math.random().toString(36).substring(2, 8);
    this.role = role;
    this.content = content;
    this.toolCallId = toolCallId;
    this.timestamp = Date.now();
  }
}

@Observed
export class ToolCall {
  id: string = '';
  type: string = 'function';
  functionName: string = '';
  functionArgs: string = '';

  constructor(id: string, name: string, args: string) {
    this.id = id;
    this.functionName = name;
    this.functionArgs = args;
  }
}

@Observed
export class ChatSession {
  id: string = '';
  title: string = '';
  messages: ChatMessage[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;

  constructor(title: string = '新对话') {
    this.id = Date.now().toString() + Math.random().toString(36).substring(2, 8);
    this.title = title;
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
  }
}

export enum Role {
  SYSTEM = 'system',
  USER = 'user',
  ASSISTANT = 'assistant',
  TOOL = 'tool'
}

export interface AppSettings {
  apiKey: string;
  baseUrl: string;
  model: string;
  thinkingEnabled: boolean;
  reasoningEffort: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: '',
  baseUrl: 'https://api.deepseek.com',
  model: 'deepseek-v4-flash',
  thinkingEnabled: true,
  reasoningEffort: 'high'
};

export const MODELS: string[] = ['deepseek-v4-flash', 'deepseek-v4-pro'];
export const REASONING_EFFORTS: string[] = ['high', 'max'];

const timeFormatProp: TimeToolFormatProp = {
  type: 'string',
  description: '时间格式，可选值：full（完整时间）、date（仅日期）、time（仅时间）',
  enum: ['full', 'date', 'time']
};

const timeToolParams: ToolParameters = {
  type: 'object',
  properties: {
    format: timeFormatProp
  },
  required: []
};

const timeToolFunc: ToolFunctionDef = {
  name: 'get_current_time',
  description: '获取当前手机系统的日期和时间',
  parameters: timeToolParams
};

export const TIME_TOOL: ToolDefinition = {
  type: 'function',
  function: timeToolFunc
};
