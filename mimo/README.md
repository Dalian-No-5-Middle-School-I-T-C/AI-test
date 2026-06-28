# DeepSeek AI 助手

这是一个使用 DeepSeek API 的 HarmonyOS 聊天应用。

## 功能特性

- 多轮对话
- 流式输出
- 思考模式支持（可选 high/max）
- 历史会话保存与读取
- 工具调用（获取系统时间）
- 用户自定义 API Key

## 项目结构

```
entry/src/main/ets/
├── components/          # UI组件
│   └── ChatMessageComponent.ets
├── models/              # 数据模型
│   └── Message.ets
├── pages/               # 页面
│   ├── Index.ets        # 首页
│   ├── ChatPage.ets     # 聊天页面
│   ├── SettingsPage.ets # 设置页面
│   └── ConversationListPage.ets # 会话列表页面
├── services/            # 服务
│   ├── DeepSeekService.ets  # DeepSeek API服务
│   ├── StorageService.ets   # 存储服务
│   └── ToolService.ets      # 工具调用服务
└── entryability/        # 应用入口
    └── EntryAbility.ets
```

## 使用说明

1. 首次打开应用时，需要在设置页面填写 DeepSeek API Key
2. 选择模型（deepseek-v4-pro 或 deepseek-v4-flash）
3. 设置思考模式（开启/关闭）和思考深度（high/max）
4. 开始聊天

## API Key 获取

请在 DeepSeek 官网 (https://platform.deepseek.com/) 获取 API Key。

## 技术说明

- 使用 ArkTS 开发
- 使用 @kit.NetworkKit 进行 HTTP 请求
- 使用 @kit.ArkData 进行本地存储
- 支持流式响应解析

## 注意事项

- 需要 HarmonyOS 6.0 及以上版本
- 需要网络权限
- API Key 请妥善保管，不要泄露