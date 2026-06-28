export interface ToolParameters {
  type: string
  properties: Record<string, Object>
  required: string[]
}

export interface ToolFunction {
  name: string
  description: string
  parameters: ToolParameters
}

export interface ToolDefinition {
  type: 'function'
  function: ToolFunction
}

export interface ToolResult {
  toolCallId: string
  result: string
}

interface TimeResult {
  current_time: string
  timestamp: number
  timezone: string
}

interface ErrorResult {
  error: string
}

export function getAvailableTools(): ToolDefinition[] {
  const tools: ToolDefinition[] = []
  const parameters: ToolParameters = {
    type: 'object',
    properties: {},
    required: []
  }
  const func: ToolFunction = {
    name: 'get_current_time',
    description: '获取当前系统时间，返回当前的日期和时间信息',
    parameters: parameters
  }
  const tool: ToolDefinition = {
    type: 'function',
    function: func
  }
  tools.push(tool)
  return tools
}

export function executeTool(toolName: string, toolCallId: string): ToolResult {
  switch (toolName) {
    case 'get_current_time': {
      const now = new Date()
      const timeStr = now.toLocaleString('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
      })
      const resultObj: TimeResult = {
        current_time: timeStr,
        timestamp: now.getTime(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
      }
      return {
        toolCallId,
        result: JSON.stringify(resultObj)
      }
    }
    default: {
      const errorObj: ErrorResult = {
        error: `Unknown tool: ${toolName}`
      }
      return {
        toolCallId,
        result: JSON.stringify(errorObj)
      }
    }
  }
}