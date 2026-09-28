# ANX Reader 备份导入

入口：设置 → 高级 → **导入 ANX Reader 的备份文件**。所有客户端统一选择 ZIP；不扫描另一应用的私有数据库目录，不申请跨应用文件访问权限。

## 使用步骤

1. 在 ANX Reader 中下载要迁移的书籍，结束阅读、等待同步完成。
2. 在 ANX Reader 的「设置 → 同步 → 导出与导入 → 导出」保存完整 ZIP。菜单名称可能随版本有所不同。
3. 将 ZIP 保存到运行默读的设备，不解压、不修改。
4. 选择 ZIP，查看可导入书籍、笔记数量，以及缺失正文/已删除书籍提示。
5. 点击「开始导入」。导入前自动创建当前默读数据库的完整快照；成功页提供可复制的备份路径。

## 范围及限制

- 导入：已下载书籍及封面、笔记/高亮、阅读位置、阅读时长、文件夹、标签。
- 不导入：已删除书籍、缺少正文文件的书籍及其附属笔记/时长；缺失书籍会列出书名，可在 ANX 下载完整后重新备份。
- 不导入应用设置、账号密码、API 密钥、同步配置、AI 聊天、独立字体/主题/背景。书籍自身内嵌资源仍随原书文件保留。ZIP 可能含敏感设置，请妥善保管。
- 原版 ANX 数据库 schema 7（不是应用的版本号）；仅 ZIP，不接受单独的 DB、加密 ZIP、未知 schema、未知触发器或默读数据库。
- 重复导入同一备份不会重复创建相同记录。按实际书籍 MD5 合并，不按书名合并；相同书籍保留默读现有进度和文件夹，已有笔记修改/删除状态优先。此入口用于一次性迁移，不代替跨应用双向同步；再次导入不会覆盖默读已有记录。
- 所有导入数据先在临时目录解压、校验。数据库/WAL 各不超过 256 MiB；每张读取的数据表不超过 20 万行；ZIP 展开总量不超过 20 GiB、条目不超过 10 万。预留解压、文件副本和当前数据库备份所需空间。
- 安全快照依赖 SQLite `VACUUM INTO`；过旧系统不支持或磁盘空间不足时会终止，不退回覆盖原库。校验/合并失败不会替换现有数据库。导入中请勿退出应用。
- 恢复快照保存于默读数据目录的 `import-backups/before-anx-<唯一标识>.db`。原有书籍文件不覆盖；SQLite 合并在一个事务内完成。恢复快照不是自动回滚远端 WebDAV 的工具。

## 源码依据

核对日期：2026-09-28，官方 `Anxcye/anx-reader` 的 `develop` 分支。

- [备份导出入口及 ZIP 布局](https://github.com/Anxcye/anx-reader/blob/develop/lib/page/settings_page/sync.dart)：`databases/app_database.db`、`file/`、`cover/`、`font/`、`bgimg/`、设置 JSON。该导出实现可能重复加入 databases 目录，导入时检查原始 ZIP 目录记录，拒绝校验值/大小冲突的重复文件。
- [数据库结构与迁移](https://github.com/Anxcye/anx-reader/blob/develop/lib/dao/database.dart)：schema 7、书籍、笔记、阅读时长、分组等表。
- [数据库目录](https://github.com/Anxcye/anx-reader/blob/develop/lib/utils/get_path/databases_path.dart)及[资源目录](https://github.com/Anxcye/anx-reader/blob/develop/lib/utils/get_path/get_base_path.dart)：仅用于核对备份结构；产品不按这些路径读取其他应用数据。

## 验证

`test/service/local_data/anx_database_import_test.dart` 使用合成 SQLite/ZIP，覆盖新增、同书合并、重复导入、当前记录保护、WAL、缺失文件、恶意路径、未知版本/触发器和事务失败回滚。

`test/widgets/anx_backup_import_page_test.dart` 覆盖中英文说明页、只允许 ZIP 的入口和校验前不可导入。
