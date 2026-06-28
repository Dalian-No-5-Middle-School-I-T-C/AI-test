你的工作目录是一个 HarmonyOS ArkTS 示例项目。你要实现一个完整 HarmonyOS 手机 APP，可直接在 DevEco 编译。

#### 功能要求

实现一个使用 DeepSeek 进行 AI 聊天的 APP。

必须支持：

- 显示思考、多轮对话、流式输出。
- 用户可以自行决定是否开启思考，选择思考深度，即 `high` `max`。
- 历史记录保存与读取。
- 为工具调用准备好（实现一个简单的获取当前手机系统时间工具）。
- 用户自己填写 API Key。

#### 提示

- ArkTS 不支持现有 OpenAI SDK，你必须自己实现 HTTP 请求。
- DeepSeek 已发布新模型，ID 分别为 `deepseek-v4-flash` 和 `deepseek-v4-pro`。
- DeepSeek 两模型均支持关闭/两档位思考模式。

示例代码：

```python
import os
from openai import OpenAI

client = OpenAI(
    api_key=os.environ.get('DEEPSEEK_API_KEY'),
    base_url="https://api.deepseek.com")

response = client.chat.completions.create(
    model="deepseek-v4-pro",
    messages=[
        {"role": "system", "content": "You are a helpful assistant"},
        {"role": "user", "content": "Hello"},
    ],
    stream=False,                                  # 你的代码中必须为 `True`
    reasoning_effort="high",                       # 可选 { "high" | "max" }
    extra_body={"thinking": {"type": "enabled"}}   # 可禁用思考
)

print(response.choices[0].message.content)
```

示例 curl 方式：

```sh
curl https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  -d '{
        "model": "deepseek-v4-pro",
        "messages": [
          {"role": "system", "content": "You are a helpful assistant."},
          {"role": "user", "content": "Hello!"}
        ],
        "thinking": {"type": "enabled"},
        "reasoning_effort": "high",
        "stream": false
      }'
```
