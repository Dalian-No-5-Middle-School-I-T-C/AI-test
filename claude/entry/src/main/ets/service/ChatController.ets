// 会话编排：管理流式生成与工具调用循环。
// 重要：本控制器不持有消息数组的引用，而是通过回调实时读取（getHistory）
// 与追加（appendMessage）。这样 UI 始终是消息数组的唯一所有者，
// 避免“控制器持有旧数组、UI 换了新数组”导致的双方分裂问题。
import {
  ApiMessage,
  ChatMessage,
  ToolCall,
  AppSettings,
  SYSTEM_PROMPT
} from '../models/ChatModels';
import { AVAILABLE_TOOLS, executeTool, ToolExecResult } from '../tools/Tools';
import { ChatRequestParams, DeepSeekService, StreamCallbacks } from './DeepSeekService';

// 单次工具调用循环的最大轮数，防止无限循环
const MAX_TOOL_ROUNDS: number = 5;

// 控制器回调，用于驱动 UI 刷新并让 UI 独占消息数组
export interface ChatControllerCallbacks {
  // 返回 UI 当前的消息数组（实时，包含已追加的工具消息与后续 assistant）
  getHistory: () => ChatMessage[];
  // 把一条新消息加入 UI 的数组并刷新；返回加入的对象（供后续流式写入）
  appendMessage: (msg: ChatMessage) => void;
  // 流式增量 / 状态变更后触发 UI 重绘 / 滚动
  onUpdate: () => void;
  // 整轮对话（含可能的多次工具调用）完成
  onComplete: () => void;
  // 出错
  onError: (message: string) => void;
}

export class ChatController {
  private service: DeepSeekService = new DeepSeekService();
  private generating: boolean = false;

  isGenerating(): boolean {
    return this.generating;
  }

  // 停止当前生成
  stop(): void {
    if (this.generating) {
      this.service.cancel();
      this.generating = false;
    }
  }

  // 将 UI 消息列表转换为 API 请求消息列表
  private buildApiMessages(uiMessages: ChatMessage[]): ApiMessage[] {
    const result: ApiMessage[] = [];
    // 系统提示
    result.push({ role: 'system', content: SYSTEM_PROMPT });

    for (const m of uiMessages) {
      if (m.isError) {
        continue; // 错误占位不发送
      }
      if (m.role === 'user') {
        result.push({ role: 'user', content: m.content });
      } else if (m.role === 'assistant') {
        // 跳过“正在流式生成、尚无任何产出”的占位消息：它既无正文也无工具调用，
        // 只是 UI 为本轮预留的空壳，不应作为历史发给服务端。
        if (m.content.length === 0 && m.toolCalls.length === 0) {
          continue;
        }
        const msg: ApiMessage = { role: 'assistant', content: m.content };
        if (m.toolCalls.length > 0) {
          msg.tool_calls = m.toolCalls;
        }
        result.push(msg);
      } else if (m.role === 'tool') {
        result.push({
          role: 'tool',
          content: m.content,
          tool_call_id: m.toolCallId
        });
      }
    }
    return result;
  }

  // 发起一轮完整对话。assistantMsg 已由 UI 通过 appendMessage 加入数组并 streaming=true。
  startRound(
    assistantMsg: ChatMessage,
    settings: AppSettings,
    cb: ChatControllerCallbacks
  ): void {
    this.generating = true;
    this.runOnce(assistantMsg, settings, cb, 0);
  }

  // 执行单次模型请求；若返回工具调用则执行工具并递归继续
  private runOnce(
    assistantMsg: ChatMessage,
    settings: AppSettings,
    cb: ChatControllerCallbacks,
    round: number
  ): void {
    // 实时读取 UI 当前的完整消息数组（含本轮之前追加的工具消息）
    const apiMessages: ApiMessage[] = this.buildApiMessages(cb.getHistory());

    const params: ChatRequestParams = {
      apiKey: settings.apiKey,
      model: settings.model,
      messages: apiMessages,
      thinkingEnabled: settings.thinkingEnabled,
      reasoningEffort: settings.reasoningEffort,
      tools: AVAILABLE_TOOLS
    };

    const callbacks: StreamCallbacks = {
      onReasoning: (delta: string) => {
        assistantMsg.reasoning += delta;
        cb.onUpdate();
      },
      onContent: (delta: string) => {
        assistantMsg.content += delta;
        cb.onUpdate();
      },
      onDone: (toolCalls: ToolCall[]) => {
        if (toolCalls.length > 0 && round < MAX_TOOL_ROUNDS) {
          // 记录助手的工具调用到当前消息
          assistantMsg.toolCalls = toolCalls;
          assistantMsg.streaming = false;
          assistantMsg.reasoningExpanded = false;
          cb.onUpdate();

          // 为每个工具调用执行并追加一条 tool 消息（顺序紧跟 assistant，保证配对）
          for (const call of toolCalls) {
            const execResult: ToolExecResult = executeTool(call.function.name, call.function.arguments);
            const toolMsg = new ChatMessage('tool', execResult.content);
            toolMsg.toolCallId = call.id;
            toolMsg.toolLabel = execResult.label;
            cb.appendMessage(toolMsg);
          }

          // 追加新的助手消息继续生成最终回答
          const nextAssistant = new ChatMessage('assistant', '');
          nextAssistant.streaming = true;
          cb.appendMessage(nextAssistant);

          // 递归继续下一轮
          this.runOnce(nextAssistant, settings, cb, round + 1);
        } else {
          // 正常结束
          assistantMsg.streaming = false;
          assistantMsg.reasoningExpanded = false;
          this.generating = false;
          cb.onUpdate();
          cb.onComplete();
        }
      },
      onError: (message: string) => {
        assistantMsg.streaming = false;
        if (assistantMsg.content.length === 0 && assistantMsg.reasoning.length === 0) {
          assistantMsg.isError = true;
          assistantMsg.content = message;
        } else {
          assistantMsg.content += `\n\n[生成中断] ${message}`;
        }
        this.generating = false;
        cb.onUpdate();
        cb.onError(message);
      }
    };

    this.service.streamChat(params, callbacks);
  }
}
