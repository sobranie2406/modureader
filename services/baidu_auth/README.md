# 默读百度网盘授权服务

客户端在“设置 → 远程书库”连接百度网盘，在“远程”切换百度网盘和 WebDAV。两套连接分别保存。文件列表及书籍下载由客户端直连百度；此服务只处理 OAuth 授权和令牌刷新。

百度网盘入口只保留文件夹和默读支持的书籍格式，复用 `allowBookExtensions`。网盘操作只调用 GET 列目录、文件信息及下载接口，不上传、删除、移动或重命名网盘文件。OAuth 使用百度提供的 `basic,netdisk` scope；应用只读行为不等同于百度对该 scope 强制授予只读权限。

## 凭据与会话

- 用 `create_config.py` 交互生成配置，保存在仓库外或已忽略的 `.release-secrets/`，权限 `0600`。
- `app_secret` 只在服务器；刷新令牌用 AES-GCM 加密存入 SQLite。客户端安全存储设备会话，访问令牌只保存在内存。
- 授权票据有效期 5 分钟，绑定客户端随机证明，一次领取后失效。设备会话有效期 30 天，刷新成功续期；解除连接删除服务端会话。
- 不记录授权码、令牌、请求正文及 URL 查询串。备份数据库时应另行保护加密密钥；丢失密钥需重新授权。

## 部署

服务目录 `/opt/modu-baidu-auth`；配置 `/etc/modu-baidu-auth/config.json`；状态目录 `/var/lib/modu-baidu-auth`。Python 3.11 或更新版本，在独立 venv 内安装 `requirements.txt`。程序及 venv 需允许服务用户读取执行；配置和 TLS 私钥保持 `0600`。systemd 用 `LoadCredential` 传入配置。

安装 `modu-baidu-auth.service`，只绑定 `127.0.0.1:18081`。将 `nginx.conf` 作为独立站点安装，证书和私钥分别放在 `/etc/modu-baidu-auth/origin.pem`、`origin.key`。先 `nginx -t`，通过后平滑 reload；不覆盖现有代理站点，不重启代理服务，不开放 18081 公网端口。

Cloudflare 仅配置 `baidu-auth.2406.fun`：

- A 记录指向部署服务器，开启代理；专用 Origin CA 证书，HTTPS 页面规则使用严格 TLS。
- 请求头转换规则匹配该主机，将 `X-Modu-Origin` **覆盖设置**为配置中的 `origin_secret`。不要使用追加操作，也不要把此值放进客户端。
- IP 限流 30 次/10 秒，超出阻止 10 秒。只允许 HTTPS，以及 POST `/v1/start`、`/v1/claim`、`/v1/token`、`/v1/revoke` 和 GET `/oauth/baidu/callback`。
- 原有域名、代理端口和规则保持原样。更新 Cloudflare IP 段时只修改此站点 allowlist。

## 资源限制与检查

systemd 内存软限 96 MiB、硬限 128 MiB，CPU 配额 20%、低调度优先级。Nginx 全局 5 请求/秒（突发 10）、并发 16、正文 4 KiB。应用另限制全局 300/分钟、IP 60/分钟、发起授权 5/分钟、设备令牌请求 6/分钟、百度换令牌 30/分钟且并发 4。

运行 `python -m unittest discover -s services/baidu_auth -p 'test_*.py'`。部署后确认：无来源凭证返回 403，随机设备会话返回 401，超大正文返回 413；直连源站不能访问授权服务。再用真实百度测试账号完成授权、列目录、下载和阅读。

检查原代理站点哈希、各服务主进程和启动时间，确保没有意外变动。回滚只需停用 `modu-baidu-auth`、移除其站点链接，通过 `nginx -t` 后 reload，并停用该子域名的 Cloudflare 规则；不操作原代理站点和端口。保留数据库及配置以便恢复。
