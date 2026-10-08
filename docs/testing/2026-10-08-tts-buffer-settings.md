# Online speech buffering settings / 在线朗读缓冲设置

## Scope / 范围

Settings → Narrate now includes an online buffering/cache section. System TTS
keeps its existing sentence navigation and device-managed synthesis; these
online controls are disabled for it. No network-provider credentials, WebDAV
transport, book database or release version are changed by this work.

设置 → 朗读新增在线缓冲与缓存区域。系统 TTS 保持原有分句和设备引擎管理，
不应用在线预合成参数。未改动服务凭据、WebDAV 传输、书库数据库或版本号。

| Setting / 设置 | Default / 默认 | Valid range / 有效范围 |
| --- | --- | --- |
| Additional passages / 提前缓冲段数 | 3 | 0–12 |
| Characters per request / 单次合成字数上限 | 240 | 100–2000 |
| Concurrent requests / 预合成并发 | 2 | 1–4 |
| Paragraph pause / 段落停顿 | 0 ms | 0–3000 ms |
| Memory-cache retention / 内存缓存保留 | 10 min | 0–120 min |

## Semantics / 行为

- Lookahead excludes the active passage. Zero disables speculative synthesis.
  The first passage is synthesized before the remaining concurrent requests.
- Length is a maximum, not a target. Existing paragraph/four-sentence grouping
  is retained; longer sentences split without breaking UTF-16 surrogate pairs.
  Live and cross-chapter lookahead use the same limits and CFI boundaries.
- Only actual paragraph ends receive the extra pause, not chunks within a
  paragraph. Pause freezes the gap; Stop cancels it promptly.
- Playback parameters are captured on a new run, not on pause/resume. Stop and
  restart reading to apply changed buffer/length/concurrency/pause settings.
- Reusable audio remains memory-only, with a 32 MiB byte budget and 256-entry
  LRU ceiling. Timers expire idle entries; cache hits do not extend their TTL.
- Retention 0 clears reusable audio on Stop/natural end. Manual clearing leaves
  active audio and the already-prepared queue intact. In-flight synthesis from
  before a clear cannot repopulate the cache. Failed/timed-out synthesis is
  evicted from request deduplication so a retry can make a fresh request.
- Settings persist and participate in existing TTS/global config transfer and
  opt-in AI/provider settings sync. Missing fields in old exports get defaults;
  malformed/out-of-range imported settings are rejected. Settings import/reset
  clears reusable audio and applies the new retention policy.

提前缓冲以“段”而非“页”计量，不随屏幕和字号改变。缓存仅在内存中保留，
不是落盘缓存；应用退出后不保留。预合成可能增加在线用量，并发过高可能触发
服务端限流。系统 TTS 不启用这些预合成、分组、额外停顿或缓存策略。

## Verification / 验证

- Dart/Flutter targeted suite: **255 passed, 1 opt-in live-network test skipped**.
  TTS lifecycle, buffering, cache, bilingual narrow
  settings UI, config import/export, settings-module roundtrips and encrypted
  settings sync. Synthetic audio/providers are used; no paid API request.
- JavaScript: **65 passed**. Reader navigation + paragraph grouping tests cover configured
  caps, complete text, Unicode, paragraph endings and unchanged system mode.
- Reader JavaScript bundle rebuilt using webpack. Existing top-level-await
  target warnings remain; no new bundler error.
- No device installation, real-provider performance claim, application package
  or release produced in this task.
