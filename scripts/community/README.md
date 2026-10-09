# Modu 官方 QQ 群助手

复用现有 `modureader-community-bot` Cloudflare Worker、免费 Workers AI 和 D1，保留 Telegram 服务。
QQ 群：**1009765685**。机器人：**Modu 默读助手**，AppID **1905740672**。

## 运行行为

- 群里 `@助手 /ask 问题` 或直接 @ 提问，依据公开 README 和功能文档解答，支持中英文。
- `/release` 返回最新已发布版本（含预发布版），`/stable` 返回正式版；保留发布者填写的中英文说明和 Release 链接。
- **GitHub 发布事件主动触发版本通知，不定时检查版本。** `.github/workflows/qq-release.yml` 处理 `release.published`。自动打包流程发布后直接调用该工作流，覆盖 `GITHUB_TOKEN` 不会再次触发发布事件的情况。
- 工作流用 GitHub 的短期 OIDC 身份调用 `POST /qq/release`。Worker 校验官方签名、接收地址、不可变仓库 ID、仓库名、工作流路径、事件和有效期。无需新增共享密钥，QQ 密钥只在 Cloudflare。
- 通知分段保存投递状态，同一 Release ID 只通知一次；网络结果不明确时保留待核查状态，避免盲目重发。
- 北京时间每天 **08:00、20:00** 总结之前 12 小时；仅包含启用后实际接收的文本。现有每分钟 Cron 驱动时间边界和清理，**不用于查询 GitHub 版本**。
- 完整群消息只处理绑定群，明显密钥、联系方式和链接中的查询参数会先隐藏，文本 24 小时过期并由现有 Cron 清理。不下载图片、书籍、语音或文件。普通聊天不自动回答。

## 部署与权限

现有 `BOT_TOKEN`、`WEBHOOK_SECRET` 为 Telegram 加密变量，保持原值。新增 `QQ_APP_SECRET` 仅作为 Cloudflare 加密变量。配置文件中的启用开关默认关闭，真实部署启用前需获得群主授权。

1. 使用群主手机 QQ 将机器人加入目标群。QQ 未认证机器人仅支持管理员使用，可加入管理员作为群主的群。
2. 开放平台配置 `https://modureader-bot.2406.fun/qq/webhook`，订阅群 @ 消息、完整群消息、入退群、机器人加入/移除、主动发言允许/拒绝事件。
3. 从已验证的 `GROUP_ADD_ROBOT` 回调中取得实际群 OpenID，核对来自目标群后设置 `QQ_GROUP_OPENID`。数字 QQ 群号不能替代 OpenID。
4. 按群主授权在群内机器人设置中允许全部文字消息和主动发言，再设置 `QQ_SUMMARIES_ENABLED=true`、`QQ_RELEASE_PUSH_ENABLED=true`。
5. 群主/管理员发送 `/push-test`，以实际无 `msg_id` 的主动发送成功为准，才启用定时与版本推送。`/summary-test` 验证当前阶段摘要；`/permissions` 只读检查官方提供的管理接口。
6. 运行 `Modu QQ Release` 的手动工作流，选择已有发布标签和 `test_notice=true`。通知标为测试，使用独立的去重记录，不会改变正式通知状态。

`GET /qq/status` 仅返回启用状态、时间及数值错误码，不暴露群 OpenID、凭据、成员或聊天文本。

群管理接口的开放范围、管理员角色和主动发送权限，以 QQ 实际返回为准。某些接口仅向白名单机器人开放，代码不会因配置存在就声称功能可用。现有 Q群管家和人工入群审核可以继续使用。

## 本地验证

需要 Node.js 22 或更新版本；测试使用内存 SQLite 和模拟网络，不调用真实 QQ。

```sh
node --test scripts/community/qq-bot.test.mjs
node scripts/community/build.mjs
node --check scripts/community/dist/worker.mjs
```

`dist/worker.mjs` 是供 Cloudflare 仪表板粘贴部署的单文件。使用 Wrangler 时直接以 `wrangler.toml` 中的 `worker.mjs` 为入口；部署前保留已有绑定、变量、域名和 Cron。

官方资料：[QQ 开放平台](https://bot.q.qq.com/wiki/develop/api-v2/)、[GitHub OIDC](https://docs.github.com/en/actions/reference/security/oidc)、[GitHub 工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。

### QQ 入群答案自动审核

群主将「Modu 默读助手」设为群管理员，订阅 `GROUP_JOIN_REQUEST`，并在生产环境设置
`QQ_JOIN_APPROVAL_ENABLED=true`。保留当前「回答问题并由管理员审核」加群方式。
收到申请后即时检查申请人填写的答案（或验证消息），匹配阅读、閱讀、读书、看书、电子书、
默读、read/reader/reading、ModuReader、AnxReader、ebook 等表达；英文忽略大小写并兼容全角。
只匹配答案，不匹配题目或昵称；不匹配、缺少字段、接口失败均保留人工处理，不自动拒绝或拉黑。
只处理绑定群，按申请 ID 去重，不轮询申请列表。验证答案不交给 AI、不进入聊天摘要、不写日志；
去重标记与无个人信息的最近一次结果保留 24 小时。`/qq/status` 可查看启用状态和最近审核结果。

官方接口：[申请事件](https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_join_request.html)、
[审批接口](https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_approval_join_request_member_openid.post.html)。

### 默读反馈汇总

北京时间 08:00 / 20:00 汇总上一阶段与默读 APP 明确有关的 Bug、功能建议、使用意见和排查进展：
`1. 昵称甲、昵称乙：【Bug反馈/功能建议/使用意见/排查进展】话题标题 👉 现象、诉求、补充信息、相互回应和最新状态。`
按实际反馈数量列项，排除闲聊、其他软件的独立问题和纯使用咨询，不编造结论或开发承诺。
结合功能、设备、现象、代词和连续问答关联后续消息，不要求引用、@ 或每条消息都写“默读”。
相关跟进合并在同一事项中，关联不确定标注“可能相关，待确认”；单个群友验证恢复不代表所有人已解决。
最多使用前一阶段仍在保留期内的最新 200 条文字作为背景（上限 6000 字符），仅用于解释本阶段新跟进，不重复发布旧反馈。
本阶段最多取 2000 条消息，输入超限时覆盖全时段抽样并提示；AI 汇总仍需核对原文。
生成草稿后，再对照同一批原文复核相关性、最新跟进和结论；只发送复核结果，不发送未复核草稿。
管理员可发送 `/summary-test 24h` 测试过去 24 小时仍保留的文字；`/summary-test` 测试当前阶段，不影响定时发送。

仅从启用此版本后收到的消息记录发言人的群内昵称及按群隔离的摘要标识。
用 QQ 稳定成员标识的摘要关联改名前后发言，给 AI 的仅为临时 U 编号和脱敏昵称；
U 编号仅在内部关联，群内输出有昵称显示昵称，无昵称统一显示「群友」，不显示 U1、U2 等编号。
同名不同 ID 不合并。记录脱敏后的 @ 对象及引用索引关系，不保存 message_scene 的 auth_token。
引用文字单独标为背景，不当作当前发言人的观点。旧消息缺少作者时用「群友」，不猜身份。
所有新增消息元数据随原消息保留 24 小时，不建立长期个人画像，也不读取附件。


### 联网搜索与来源汇总

群友 `@Modu 默读助手 问题` 或 `/search 问题`，按脱敏后的问题联网搜索，
然后由当前 Qwen 模型整理要点、标注来源编号，附搜索服务实际返回的链接。
`/ask 问题` 保留按默读公开项目文档回答。普通群聊不会触发搜索。

使用 AnySearch 的公开匿名搜索 API，直接传入本次脱敏后的完整问题，
汇总仍由现有 Workers AI 模型完成，省去关键词提炼的额外模型调用。
每题最多取 5 个结果、1024 字，每人间隔 30 秒，全群搜索间隔 5 秒，
与文档问答共享每天 80 次上限。不传整段群聊、昵称或成员 ID。
搜索结果不作为指令；无来源或服务故障时明确提示，不凭模型记忆冒充联网结果。

不注册搜索账号、不配置付费密钥、不调用收费搜索或自动切换付费后端。
匿名调用按 IP 限流并受每日免费额度限制，官方未在接口文档承诺具体匿名次数；
额度用完时停止，不使用响应中自动生成的账号、密码或密钥，也不记录错误响应正文。
搜索结果可能遗漏或过时，模型整理需核对原文。现有模型的免费额度限制继续生效。
来源附 AnySearch 名称与实际网页链接。
官方接口：[AnySearch Search API](https://anysearch.com/docs/api-endpoints/v1-search)。
