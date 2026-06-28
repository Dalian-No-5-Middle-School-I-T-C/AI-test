export const TimeToolDefinition = {
  type: 'function',
  function: {
    name: 'get_current_time',
    description: 'Get the current mobile device system date and time.',
    parameters: {
      type: 'object',
      properties: {},
      required: []
    }
  }
};

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

    return JSON.stringify({
      status: 'success',
      current_time: `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`,
      day_of_week: dayOfWeek,
      timezone_offset: now.getTimezoneOffset()
    });
  } catch (e) {
    return JSON.stringify({
      status: 'error',
      message: `Failed to retrieve system time: ${JSON.stringify(e)}`
    });
  }
}
