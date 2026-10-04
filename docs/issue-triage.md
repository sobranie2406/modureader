# Modu issue triage

Current guide for Modu 1.2.0+10082. Repository: [sobranie2406/modureader](https://github.com/sobranie2406/modureader). See the [documentation index](README.md) and [settings guide](SETTINGS.md).

## In-app feedback

- Open **Settings → Bug reports and feature requests**. Bug reports and feature requests have separate fields and previews. Switching type preserves both drafts in the current screen; drafts are not saved to global settings or WebDAV.
- Bug reports collect a title, description, reproduction steps, actual result and expected behavior. Feature requests collect a title, use case and desired feature. Additional information is optional.
- Bugs prefill form field IDs from `bug-report.yaml`, with the actual result included in the description. Feature requests use `feature_request.md` and prefill the complete Markdown via `body`. Repository templates specify labels; URLs do not pass the permission-sensitive `labels` parameter.
- Environment information is independently optional. Crash diagnostics are optional for bugs only and excluded by default. Reports containing diagnostics or exceeding 1,800 characters after URL encoding use full-report copying after preview confirmation and open the corresponding template. The body is not truncated, and diagnostics are not put in the URL. For bug forms, manually paste the report and complete GitHub's required fields.
- Opening GitHub is not submission. The user logs in, reviews public content, adds screenshots as needed and clicks GitHub's submit button to create an issue. Modu holds no GitHub token, does not call ReadAny's feedback service and does not invent an issue number.

References: [GitHub issue URL queries](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue#creating-an-issue-from-a-url-query), [form field IDs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema), [ReadAny feedback types](https://github.com/codedogQBY/ReadAny/blob/main/packages/core/src/feedback/feedback-types.ts), [ReadAny feedback UI](https://github.com/codedogQBY/ReadAny/blob/main/packages/app/src/components/settings/FeedbackSettings.tsx).

Implementation: [feedback screen](../lib/page/settings_page/bug_report.dart), [feedback report service](../lib/service/feedback/bug_report.dart).

## Manual triage

- Verify version/build, platform and minimal reproduction steps. Check duplicate reports and link upstream issues when relevant, while keeping Modu user reports in this repository.
- Request minimal original or authorized-to-share fixtures and user-reviewed sanitized diagnostics. Do not require public disclosure of private books, full logs, databases, keys or configuration QRs/links.
- A successful build, failure to reproduce or absence of logs is not evidence that a bug is fixed. Before closing, identify the fix commit, test scope and devices that still need retesting.

## Current automation

Inherited general stale handling and automatic addition/removal of the `question` label are gated to the upstream repository and inactive for Modu. Their presence is not a promise of automatic triage. Do not silently enable a new policy by replacing the repository name.

The question-specific handler in `stale-issues.yml` remains configured: questions become stale after 30 inactive days and close after seven more days. The closed-thread locking job remains configured to lock issues and pull requests after 30 days of inactivity following closure. This documentation update did not change those policies. Templates and label references do not guarantee that every upstream label exists in Modu.

Workflow references: [stale/questions/locking](../.github/workflows/stale-issues.yml), [label trigger](../.github/workflows/label-trigger.yml), [question-label removal](../.github/workflows/remove-question-label.yml). These are source configuration checks, not verification of recent hosted workflow runs or live label availability.

## Read-only inspection example

```sh
gh issue view NUMBER --repo sobranie2406/modureader --json title,labels,state
```

Before changing labels, closing, locking or commenting, confirm that the target belongs to this repository and that the corresponding maintenance authority has been granted.
