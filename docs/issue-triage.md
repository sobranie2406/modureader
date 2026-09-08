# Modu issue triage / 默读问题处理

Repository: https://github.com/sobranie2406/modureader

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
