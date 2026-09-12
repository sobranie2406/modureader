# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.0.4

- Bundle four verified local embedding models for offline use; automatic indexing remains off by default.
- Fix Windows WebView null JavaScript replies and order native shutdown safely.
- Preload adjacent chapter resources with a bounded cache to reduce repeated chapter loading.
- Delay foreground automatic sync and recover missing ETags without unconditional database overwrites.
- Fit desktop footnotes within 25 percent of the viewport; preserve end padding on desktop and mobile so the last line remains reachable.
- Rename the library connection entry to Remote library settings.

- 内嵌四个已校验本地向量模型，支持离线使用；自动向量化仍默认关闭。
- 修复 Windows WebView 空 JavaScript 回调及原生退出顺序问题。
- 有限缓存并预加载相邻章节资源，减少来回切换章节的重复加载。
- 回前台自动同步增加延迟与网络重试；补查缺失 ETag，保留并发写入保护，不无条件覆盖数据库。
- 桌面注释在阅读窗口 25% 面积内优先完整显示；电脑、手机均保留末尾留白，长注释可滚动查看最后一行。
- 书库连接入口统一命名为「远程书库设置」。
