# 每模型关闭推理

此设置包含在 1.0.1 源码中，安装包与验证范围见对应 GitHub Release。

入口：设置 → AI 设置 → 供应商配置中心 → 新建或编辑模型 → 参数 → 推理强度 → **关闭推理**，保存后生效。

- 自动：不发送推理控制参数，由服务端决定，不等于关闭。
- 关闭推理：向服务端明确请求停用推理，不是隐藏思考过程，也不是降低推理强度。
- 低、中、高：保留原有 OpenAI 兼容接口的 `reasoning_effort` 设置。

全文翻译使用「设置 → 翻译」中选定的 AI 模型配置。该模型的其他 AI 请求也使用同一设置。如果只希望翻译关闭推理，可新建单独的翻译模型配置。设置随默读 AI 配置导入/导出保留；旧配置缺少此字段时仍为自动。

## 适配规则

| 接口 | “关闭推理”发送的字段 | 依据 |
| --- | --- | --- |
| OpenAI / 默认兼容接口 | `reasoning_effort: "none"` | [OpenAI GPT-5.1](https://developers.openai.com/api/docs/models/gpt-5.1) |
| DeepSeek、GLM | `thinking: {"type":"disabled"}` | [DeepSeek](https://api-docs.deepseek.com/guides/thinking_mode/)、[GLM](https://docs.bigmodel.cn/cn/guide/capabilities/thinking) |
| DashScope / Qwen | `enable_thinking: false` | [阿里云](https://help.aliyun.com/zh/model-studio/deep-thinking/) |
| OpenRouter | `reasoning: {"enabled":false}` | [OpenRouter](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens) |
| Claude 原生协议 | `thinking: {"type":"disabled"}` | [Anthropic](https://platform.claude.com/docs/en/docs/build-with-claude/extended-thinking) |
| Gemini 2.5 Flash / Flash-Lite 原生协议 | `generationConfig.thinkingConfig.thinkingBudget: 0` | [Google](https://ai.google.dev/gemini-api/docs/generate-content/thinking?hl=en) |

兼容接口按服务域名识别，Qwen、DeepSeek、GLM 的模型名前缀也用于自定义代理；OpenRouter 和 DashScope 域名规则优先。代理必须实现对应字段。其他 Gemini 模型暂不允许在本适配中选择实际关闭请求，会返回明确错误。

以上是请求协议适配，不代表每个模型都支持关闭。强制推理模型及部分旧模型可能拒绝这些参数；请改回自动或选择支持关闭的模型。不会通过悄悄切换模型、隐藏推理输出、或者失败后改为开启推理来伪装成功。服务端忽略参数的行为无法由客户端保证。

减少服务端推理可能缩短等待，但也可能影响复杂任务质量；实际速度还取决于模型、文本长度、网络和服务负载。回归测试使用合成文本、模拟接口和本地服务，不使用个人密钥或书籍，也不等于真实服务的性能测试。
