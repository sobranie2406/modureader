# Modu issue triage / 默读问题处理

Repository: https://github.com/sobranie2406/modureader

## 应用内反馈 / In-app feedback

- 设置 → 问题反馈与功能建议：Bug 与功能建议分别填写和预览，切换类型保留当前界面中的两份草稿；草稿不写入全局设置或 WebDAV。
- Bug 填写标题、问题描述、重现步骤、实际结果与预期行为；功能建议填写标题、使用场景与希望实现的功能。补充信息可选。
- Bug 使用 `bug-report.yaml` 的字段 ID 预填表单，实际结果合并到问题描述；功能建议使用 `feature_request.md`，以 `body` 预填完整 Markdown。标签由仓库模板指定，不在链接中传入需要权限的 `labels` 参数。
- 运行环境可独立选择；崩溃诊断仅 Bug 可选、默认不附带。含诊断或编码后超过 1800 字符的报告，确认预览后复制全文并打开对应模板，不截断正文、不把诊断放进 URL。Bug 表单需手动粘贴报告并补齐 GitHub 必填项。
- 打开浏览器不代表已提交。用户登录 GitHub，检查公开内容、补充截图并点击 GitHub 提交按钮后才创建 Issue。应用不持有 GitHub Token，不调用 ReadAny 的反馈服务，也不生成虚假的 Issue 编号。

References: [GitHub issue URL queries](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue#creating-an-issue-from-a-url-query), [form field IDs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema), [ReadAny feedback types](https://github.com/codedogQBY/ReadAny/blob/main/packages/core/src/feedback/feedback-types.ts), [ReadAny feedback UI](https://github.com/codedogQBY/ReadAny/blob/main/packages/app/src/components/settings/FeedbackSettings.tsx).

## 人工处理 / Manual triage

- 先核对版本、平台和最小复现；查看重复报告，必要时关联上游问题，不把默读用户导向上游投诉。
- 不要求公开提供私人书籍、完整日志、数据库、密钥或配置二维码。优先使用原创或获准分享的最小样例以及用户预览过的脱敏诊断。
- 编译成功、未复现或未收到日志都不等于问题已修复。关闭前说明修复提交、测试范围及仍需复测的设备。
- Verify version, platform and reproduction steps. Link upstream issues when relevant, but keep Modu reports here.
- Request minimal shareable fixtures and user-reviewed sanitized diagnostics, not private books or credentials.
- Record evidence and test limits before closing an issue.

## 当前自动化 / Current automation

通用自动标记长期未活动问题、自动补充及移除 question 标签的上游任务保留仓库限定，在默读不运行。不要通过替换仓库名称来悄悄开启新策略。

The inherited general stale/label handlers are repository-gated and inactive for Modu. Their presence is not a promise of automatic triage.

现有 `stale-issues.yml` 中 question 问题的长期未回复处理，以及关闭后的锁定任务仍按文件配置运行。本次文档清理不改变其行为。问题模板和标签不保证所有上游标签均已创建。

The question-specific stale handler and closed-thread locking remain configured in `stale-issues.yml`; this cleanup does not change those policies.

## Read-only example / 只读检查示例

```sh
gh issue view NUMBER --repo sobranie2406/modureader --json title,labels,state
```

改变标签、关闭、锁定或发表评论前，应确认目标确属本仓库，并取得对应维护权限。
