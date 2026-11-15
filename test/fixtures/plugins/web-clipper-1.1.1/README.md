# 网页稍后阅读

在插件菜单打开“网页稍后阅读”，粘贴网页地址，点击“获取正文”。预览后可导出 Markdown，或加入书架继续阅读。

正文识别和广告清理保留标题层级、列表、引用、代码、表格与来源。在插件设置中可选择保留作者、日期和图片链接；图片不会自动下载。

提取算法和依赖随插件更新。正文识别使用 [Readability](https://github.com/mozilla/readability)，虚拟 DOM 使用 [LinkeDOM](https://github.com/WebReflection/linkedom)，Markdown 转换使用 [Turndown](https://github.com/mixmark-io/turndown)，清理规则参考 [Defuddle](https://github.com/kepano/defuddle)。依赖已打入插件包，网页脚本不会执行，第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

需要支持 `article:extract` 的默读版本。安装页提示更新时，请先更新默读。

正文算法、网站适配和依赖都在包内，可随插件独立更新。开发方式见[插件开发规范](https://github.com/sobranie2406/modu-plugin/blob/main/DEVELOPMENT.md)。
