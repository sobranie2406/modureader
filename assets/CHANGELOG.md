# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.5

- Centralize settings file, QR and modu-link transfer; credentials are opt-in and explicit exports remain unencrypted, separate from encrypted WebDAV sync.
- Add independently enabled CSS profiles, import/export, 13 editable templates and bounded regex highlighting.
- Add MiMo preset voices, editable speech/voice-design templates and prompt suggestions.
- Keep sentence controls open, read from a selection and improve lock-screen pause/resume ordering.
- Isolate optional speech highlighting/location failures without silently skipping body text.
- Use generic fonts after font-loading failures, handle Kindle font declarations and remove the intrusive loading notice.

- 全局设置统一文件、二维码与 modu 链接迁移，凭据按需包含；主动导出不加密，与 WebDAV 加密同步分开。
- CSS 多套独立开关、组合启用、导入导出、13 个可编辑预设及正则文字高亮。
- MiMo 增加官方音色、朗读风格和音色设计模板、常用描述提示词。
- 保持上一句/下一句控制栏，支持从选中文字朗读，改进锁屏暂停与恢复。
- 隔离高亮及可选位置异常，不静默跳过正文；特定手机停顿仍需原机验证。
- 字体失败时使用通用字体，兼容 Kindle 字体声明，优化重复加载并取消遮挡提示。
