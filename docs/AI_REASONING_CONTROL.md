# Per-model reasoning control

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md) and [settings guide](SETTINGS.md).

Open **Settings → AI settings → Provider Center**, add or edit a model configuration, then choose **Parameters → Reasoning Effort → Off** and save.

- **Auto** sends no reasoning-control parameter and leaves the decision to the server; it does not disable reasoning.
- **Off** explicitly requests that the server disable reasoning. It does not merely hide thinking output or lower the reasoning effort.
- **Low / Medium / High** retain the OpenAI-compatible `reasoning_effort` settings.

Full-text translation uses the AI model selected under **Settings → Translation**. Other AI requests using that model configuration share its reasoning setting. To disable reasoning only for translation, create a separate translation-model configuration.

The setting survives AI-configuration import/export through **Settings → Global settings backup**. Older configurations without this field remain on Auto. Global settings use settings files or `modu:` links; global and separate TTS configuration export do not offer QR export.

## Request adaptation

| API | Fields sent for Off | Protocol reference |
| --- | --- | --- |
| OpenAI / default compatible API | `reasoning_effort: "none"` | [OpenAI GPT-5.1](https://developers.openai.com/api/docs/models/gpt-5.1) |
| DeepSeek, GLM | `thinking: {"type":"disabled"}` | [DeepSeek](https://api-docs.deepseek.com/guides/thinking_mode/), [GLM](https://docs.bigmodel.cn/cn/guide/capabilities/thinking) |
| DashScope / Qwen | `enable_thinking: false` | [Alibaba Cloud](https://help.aliyun.com/zh/model-studio/deep-thinking/) |
| OpenRouter | `reasoning: {"enabled":false}` | [OpenRouter](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens) |
| Native Claude protocol | `thinking: {"type":"disabled"}` | [Anthropic](https://platform.claude.com/docs/en/docs/build-with-claude/extended-thinking) |
| Native Gemini 2.5 Flash / Flash-Lite protocol | `generationConfig.thinkingConfig.thinkingBudget: 0` | [Google](https://ai.google.dev/gemini-api/docs/generate-content/thinking?hl=en) |

Compatible APIs are identified by service domain; Qwen, DeepSeek and GLM model-name prefixes also support custom proxies. OpenRouter and DashScope domain rules take priority. A proxy must implement the corresponding fields. Other Gemini models are not supported by this adapter's Off mode and produce an explicit error.

These are request adaptations, not a guarantee that every model supports disabling reasoning. Models with mandatory reasoning and some older models may reject the parameters; switch back to Auto or select a compatible model. The client does not silently switch models, hide reasoning output or retry with reasoning enabled to present a failure as success. It cannot guarantee that a server respects the requested parameters.

Reducing server-side reasoning may shorten waiting time but can affect complex-task quality. Speed also depends on the model, text length, network and service load. Existing regression tests use synthetic text, mocked APIs and a local service, without personal keys or books; they are not live-service performance tests and were not rerun for this documentation update.

Implementation: [reasoning-control adapter](../lib/service/ai/reasoning_control_client.dart).
