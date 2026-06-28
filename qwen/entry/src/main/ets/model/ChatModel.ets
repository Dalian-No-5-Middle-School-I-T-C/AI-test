export class ToolCall {
  id: string = '';
  type: string = 'function';
  name: string = '';
  arguments: string = '';
}

export class ChatMessage {
  role: string = '';
  content: string = '';
  reasoningContent: string = '';
  toolCalls: Array<ToolCall> = [];
  toolCallId: string = '';
}

export class Conversation {
  id: string = '';
  title: string = '';
  messages: Array<ChatMessage> = [];
  timestamp: number = 0;
}

export function createUserMessage(content: string): ChatMessage {
  let msg = new ChatMessage();
  msg.role = 'user';
  msg.content = content;
  return msg;
}

export function createAssistantMessage(content: string, reasoning: string,
  toolCalls: Array<ToolCall>): ChatMessage {
  let msg = new ChatMessage();
  msg.role = 'assistant';
  msg.content = content;
  msg.reasoningContent = reasoning;
  msg.toolCalls = toolCalls;
  return msg;
}

export function createToolMessage(toolCallId: string, content: string): ChatMessage {
  let msg = new ChatMessage();
  msg.role = 'tool';
  msg.content = content;
  msg.toolCallId = toolCallId;
  return msg;
}

export class ToolFunctionSchema {
  name: string = '';
  description: string = '';
  parameters: string = '';
}

export class ToolDefinitionSchema {
  type: string = 'function';
  function: ToolFunctionSchema = new ToolFunctionSchema();
}

export class ThinkingConfig {
  type: string = 'enabled';
}

export class ApiMessageItem {
  role: string = '';
  content: string = '';
  tool_call_id: string = '';
  tool_calls: string = '';
}

export class ChatRequestBody {
  model: string = '';
  messages: Array<ApiMessageItem> = [];
  stream: boolean = true;
  thinking: ThinkingConfig | null = null;
  reasoning_effort: string = '';
  tools: string = '';

  toJson(): string {
    let parts: Array<string> = [];
    parts.push('"model":"' + this.model + '"');
    let msgsJson: Array<string> = [];
    for (let i = 0; i < this.messages.length; i++) {
      let m = this.messages[i];
      let msgParts: Array<string> = [];
      msgParts.push('"role":"' + m.role + '"');
      msgParts.push('"content":' + JSON.stringify(m.content));
      if (m.role === 'tool' && m.tool_call_id.length > 0) {
        msgParts.push('"tool_call_id":"' + m.tool_call_id + '"');
      }
      if (m.tool_calls.length > 0) {
        msgParts.push('"tool_calls":' + m.tool_calls);
      }
      msgsJson.push('{' + msgParts.join(',') + '}');
    }
    parts.push('"messages":[' + msgsJson.join(',') + ']');
    parts.push('"stream":true');
    if (this.thinking !== null) {
      parts.push('"thinking":{"type":"' + this.thinking.type + '"}');
      parts.push('"reasoning_effort":"' + this.reasoning_effort + '"');
    }
    if (this.tools.length > 0) {
      parts.push('"tools":' + this.tools);
    }
    return '{' + parts.join(',') + '}';
  }
}
