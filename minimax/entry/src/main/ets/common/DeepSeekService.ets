import { http } from '@kit.NetworkKit';
import { ChatMessage, ToolCall, ToolCallFunction } from './Storage';
import { httpStreamRequest } from './HttpClient';
import { AVAILABLE_TOOLS, executeToolCall, ToolCallRequest, ToolDefinition } from './Tools';

export class SendOptions {
  apiKey: string = '';
  baseUrl: string = 'https://api.deepseek.com';
  model: string = 'deepseek-v4-pro';
  messages: ChatMessage[] = [];
  thinkingEnabled: boolean = true;
  reasoningEffort: 'high' | 'max' | '' = 'high';
  toolsEnabled: boolean = true;
}

export class SendResult {
  finishReason: string = '';
  toolCallRounds: number = 0;
  finalContent: string = '';
}

const TOOL_LOOP_MAX = 4;

class HeadersMap {
  entries: Record<string, string> = {};
}

export async function sendChatStream(
  opts: SendOptions,
  onContentDelta: (text: string) => void,
  onReasoningDelta: (text: string) => void,
  onToolCallsProduced: (calls: ToolCall[], toolMessages: ChatMessage[]) => void,
  onError: (msg: string) => void
): Promise<SendResult> {
  let messages: ChatMessage[] = opts.messages.slice();
  let rounds = 0;
  let finalContent = '';
  let lastReason = 'stop';
  for (let iter = 0; iter < TOOL_LOOP_MAX; iter++) {
    rounds = iter + 1;
    const partial = await sendOnce(opts, messages, onContentDelta, onReasoningDelta, onError);
    finalContent = partial.assistantContent;
    lastReason = partial.finishReason;
    if (partial.toolCalls.length === 0) {
      break;
    }
    const toolMessages: ChatMessage[] = [];
    for (let i = 0; i < partial.toolCalls.length; i++) {
      const tc = partial.toolCalls[i];
      const req = new ToolCallRequest();
      req.id = tc.id;
      req.name = tc.function.name;
      req.rawArgs = tc.function.arguments;
      const exec = executeToolCall(req);
      const tm = new ChatMessage();
      tm.role = 'tool';
      tm.name = exec.name;
      tm.content = exec.result;
      tm.toolCallId = tc.id;
      toolMessages.push(tm);
    }
    const assistantRecord = new ChatMessage();
    assistantRecord.role = 'assistant';
    assistantRecord.content = partial.assistantContent;
    const callsCopy: ToolCall[] = [];
    for (let i = 0; i < partial.toolCalls.length; i++) {
      callsCopy.push(partial.toolCalls[i]);
    }
    assistantRecord.toolCalls = callsCopy;
    messages = messages.concat([assistantRecord]).concat(toolMessages);
    onToolCallsProduced(partial.toolCalls, toolMessages);
  }
  const result = new SendResult();
  result.finishReason = lastReason;
  result.toolCallRounds = rounds;
  result.finalContent = finalContent;
  return result;
}

class PartialSendResult {
  finishReason: string = '';
  assistantContent: string = '';
  toolCalls: ToolCall[] = [];
}

function sendOnce(
  opts: SendOptions,
  messages: ChatMessage[],
  onContentDelta: (text: string) => void,
  onReasoningDelta: (text: string) => void,
  onError: (msg: string) => void
): Promise<PartialSendResult> {
  return new Promise<PartialSendResult>((resolve) => {
    const acc = new StreamAccumulator();
    let resolved = false;
    const resolveOnce = (r: PartialSendResult): void => {
      if (resolved) {
        return;
      }
      resolved = true;
      resolve(r);
    };

    const body = buildBody(opts, messages);
    const url = `${opts.baseUrl.replace(/\/$/, '')}/chat/completions`;
    const onDeltaAcc = (c: string): void => {
      acc.appendContent(c);
      onContentDelta(c);
    };
    const onReasoningAcc = (c: string): void => {
      acc.appendReasoning(c);
      onReasoningDelta(c);
    };
    const onToolCallAcc = (id: string, name: string, args: string): void => {
      acc.addToolCallDelta(id, name, args);
    };
    const onFinishAcc = (reason: string): void => {
      acc.finishReason = reason;
      const r = acc.toResult();
      resolveOnce(r);
    };
    const onErrorAcc = (err: string): void => {
      onError(err);
      acc.finishReason = 'error';
      const r = acc.toResult();
      resolveOnce(r);
    };

    const reqHeadersMap = new HeadersMap();
    reqHeadersMap.entries['Content-Type'] = 'application/json';
    reqHeadersMap.entries['Authorization'] = `Bearer ${opts.apiKey}`;
    reqHeadersMap.entries['Accept'] = 'text/event-stream';
    const reqHeaders = reqHeadersMap.entries;

    httpStreamRequest(
      url,
      http.RequestMethod.POST,
      reqHeaders,
      body,
      onDeltaAcc,
      onReasoningAcc,
      onToolCallAcc,
      onFinishAcc,
      onErrorAcc
    ).then(() => {
      if (!resolved) {
        resolveOnce(acc.toResult());
      }
    });
  });
}

function buildBody(opts: SendOptions, messages: ChatMessage[]): string {
  const msgParts: string[] = [];
  for (let i = 0; i < messages.length; i++) {
    msgParts.push(messageToJson(messages[i]));
  }
  const messagesJson = `[${msgParts.join(',')}]`;
  const thinkingEnabled = opts.thinkingEnabled;
  const thinkingJson = thinkingEnabled
    ? `{"type":"enabled"}`
    : `{"type":"disabled"}`;
  let reasoningPart = '';
  if (thinkingEnabled && (opts.reasoningEffort === 'high' || opts.reasoningEffort === 'max')) {
    reasoningPart = `,"reasoning_effort":${jsonString(opts.reasoningEffort)}`;
  }
  let toolsPart = '';
  if (opts.toolsEnabled) {
    toolsPart = `,"tools":${availableToolsJson()}`;
  }
  return `{"model":${jsonString(opts.model)},"messages":${messagesJson},"stream":true,"thinking":${thinkingJson}${reasoningPart}${toolsPart}}`;
}

function messageToJson(m: ChatMessage): string {
  if (m.role === 'assistant' && m.toolCalls.length > 0) {
    const callsJson: string = toolCallsToJson(m.toolCalls);
    return `{"role":"assistant","content":${jsonString(m.content)},"tool_calls":${callsJson}}`;
  }
  if (m.role === 'tool') {
    return `{"role":"tool","content":${jsonString(m.content)},"tool_call_id":${jsonString(m.toolCallId)},"name":${jsonString(m.name)}}`;
  }
  return `{"role":${jsonString(m.role)},"content":${jsonString(m.content)}}`;
}

function toolCallsToJson(calls: ToolCall[]): string {
  const parts: string[] = [];
  for (let i = 0; i < calls.length; i++) {
    const tc = calls[i];
    parts.push(`{"id":${jsonString(tc.id)},"type":"function","function":{"name":${jsonString(tc.function.name)},"arguments":${jsonString(tc.function.arguments)}}}`);
  }
  return `[${parts.join(',')}]`;
}

function jsonString(s: string): string {
  return JSON.stringify(s);
}

function availableToolsJson(): string {
  const parts: string[] = [];
  for (let i = 0; i < AVAILABLE_TOOLS.length; i++) {
    const def = AVAILABLE_TOOLS[i];
    parts.push(toolDefinitionJson(def));
  }
  return `[${parts.join(',')}]`;
}

function toolDefinitionJson(def: ToolDefinition): string {
  return `{"type":"function","function":{"name":${jsonString(def.function.name)},"description":${jsonString(def.function.description)},"parameters":${toolParametersJson(def.function.parameters)}}}`;
}

function toolParametersJson(p: object): string {
  return JSON.stringify(p);
}

class StreamAccumulator {
  content: string = '';
  reasoning: string = '';
  finishReason: string = 'stop';
  toolCallMap: Map<string, ToolCall> = new Map();
  toolCallOrder: string[] = [];

  appendContent(c: string): void {
    this.content += c;
  }

  appendReasoning(c: string): void {
    this.reasoning += c;
  }

  addToolCallDelta(id: string, name: string, args: string): void {
    let key = id;
    if (key.length === 0) {
      key = `idx_${this.toolCallOrder.length}`;
    }
    let existing = this.toolCallMap.get(key);
    if (!existing) {
      const fn = new ToolCallFunction();
      fn.name = name;
      fn.arguments = args;
      const tc = new ToolCall();
      tc.id = key;
      tc.function = fn;
      this.toolCallMap.set(key, tc);
      this.toolCallOrder.push(key);
    } else {
      if (name.length > 0) {
        existing.function.name = name;
      }
      existing.function.arguments += args;
    }
  }

  toResult(): PartialSendResult {
    const calls: ToolCall[] = [];
    for (let i = 0; i < this.toolCallOrder.length; i++) {
      const k = this.toolCallOrder[i];
      const v = this.toolCallMap.get(k);
      if (v) {
        calls.push(v);
      }
    }
    const r = new PartialSendResult();
    r.finishReason = this.finishReason;
    r.assistantContent = this.content;
    r.toolCalls = calls;
    return r;
  }
}