# AI-test
AI模型大测试专用仓库

#### 目前已测试

- GPT-5.5
- Claude Opus 4.8
- DeepSeek V4 Pro
- GLM 5.2
- Qwen 3.7 Max
- 豆包 2.1 Pro
- MiniMax M3
- Kimi K2.7 Code
- MiMo 2.5 Pro
- ERNIE-5.0-Thinking-Preview

验收结果为

- [结果1](./结果.md)
- [结果2](./额外结果.md)

评测报告为 [报告](./多模型评测报告.md)

#### 已建目录等待测试

- Gemini
- Composer

#### 测试规则

1. 使用 DevEco 创建新项目
2. 将 [题目](./question.md) 整个复制粘贴给模型
3. 工作完成后将模型的更改提交到仓库中
4. 编译，验收
   - 若未通过编译，将 hvigor 的 Error 部分完整粘贴给模型，不说其他话
   - 若通过编译，APP 交互有问题，仅描述现象或出现的文本
5. 完成条件：跑通整套流程即可，不需要美化 UI
