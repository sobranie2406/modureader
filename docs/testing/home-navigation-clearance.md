# 首页底部导航避让

## 修改

- 紧凑布局统一使用 `HomeNavigationBody` 在页面外预留底部栏高度、悬浮距离、系统安全区及 12 dp 间隔。列表、网格、空状态和固定操作区都受到保护。
- 书架、远程书库、统计、笔记不再使用 80/96 dp 的固定导航补偿，仅保留正常内容间距与未消费的系统安全区。设置页不重复补偿底部栏。
- 导航栏高度随系统文字缩放增加，内容使用同一个高度计算。
- 自动隐藏时保留避让空间，防止滚动中改变视口或导航栏重新出现时遮挡操作。键盘出现时隐藏底部栏及回顶图标，由 Scaffold 处理键盘避让；不重建输入内容。
- 宽屏侧边导航不预留底部栏空间。独立页面和 AI 弹出面板不受首页底部补偿影响。

## 自动化

`flutter test --no-pub test/widgets/home_navigation_body_test.dart test/widgets/settings_bottom_navigation_test.dart test/platform/settings_navigation_test.dart`

42 项通过。覆盖网格、列表、固定按钮，0/24/48 dp 系统安全区，1.0/1.6/2.0 倍文字缩放，键盘出现及收起、自动隐藏及恢复、侧栏布局，以及真实设置页末项显示与点击。数据测试使用组件夹具，不访问个人书库或 WebDAV。

本次未重新打包、未做 Android/macOS 真机操作验证；先前生成的 Preview3 包不包含本次修改。
