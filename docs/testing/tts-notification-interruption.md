# 短信打断与朗读通知

## 修复

- 保留语音内容的短暂暂停，不让短信提示音盖过正文。连续重复的音频焦点丢失只暂停一次，恢复焦点后只恢复一次，不重复请求已经获得的焦点。
- 原来已暂停、手动暂停、停止、拔掉耳机、切换引擎或永久丢失焦点时，不自动重新播放。恢复期间再次被打断也必须等待最后一次焦点恢复。
- Android 播放器通知明确 `setSilent(true)`、`setOnlyAlertOnce(true)`，清除声音/振动和默认提醒标志。新建通知渠道也明确无声无振动。保留原渠道与用户权限，不删除渠道，不改变短信应用或系统音量。
- `android/modu_audio_notification.gradle` 只在构建目录生成 audio_service Java 源码副本，不修改 Pub 缓存；更换上游实现导致补丁定位不唯一时构建失败，避免静默漏掉修复。Apple/Windows 不使用此 Android 构建补丁。

## 回归

`flutter test test/service/tts` 包含重复打断、快速连续打断、慢暂停、用户暂停、永久焦点丢失及锁屏媒体控制等测试。

`node --test test/android_tts_notification.test.mjs` 检查构建接线与静音策略。生成 APK 后还须检查实际生成的 Java 和实机通知状态，不能仅凭源码断言认定真机通过。

实机步骤：使用系统朗读及在线引擎分别开始连续朗读；保持亮屏，收到一条真实短信，确认短信仅响一次、朗读短暂停顿后继续；在短信打断期间手动暂停，确认不会自动恢复；再检查锁屏暂停/播放与跨段朗读。只查看默读的媒体状态与日志，不读取短信正文或其他应用数据。

参考：[Android 音频焦点](https://developer.android.com/media/optimize/audio-focus)、[NotificationCompat.Builder](https://developer.android.com/reference/androidx/core/app/NotificationCompat.Builder)。

## 2026-09-28 本轮结果

- 荣耀 LGE-AN10 / Android 15，保留数据覆盖安装 `1.1.6-test.sms+10051`。
- 自动化：朗读测试 133 项通过、1 项跳过；Android 原生策略/接线测试 5 项通过。
- 实际编译的 audio_service Java 字节码已检查包含 `setSilent`、`setOnlyAlertOnce`、渠道静音设置。
- 真实设备上的 MiMo 朗读合成文本期间，独立测试工具申请一次 `GAIN_TRANSIENT_MAY_DUCK`，持续 1800 ms 后释放。媒体状态采样显示 PLAYING → PAUSED → PLAYING，仅一次暂停/恢复；焦点历史中没有默读因自动恢复重复申请焦点。
- 默读实际通知记录：`sound=null`、`vibrate=null`、`defaults=0`、`ONLY_ALERT_ONCE`、`groupKey=silent`、`isNoisy=false`、`mIsInterruptive=false`。
- 用户要求结束测试，未完成真实短信响声的人工确认，也未完成系统朗读引擎的同场景实机对照。不能据此声称原报告的重复响声已实机消失。
- 停止测试朗读、卸载独立测试工具；保留修复版默读及测试书，不删除用户原有内容。
