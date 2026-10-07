# Object storage synchronization

Implementation guide for Modu 1.2.2. Provider presets do not imply live acceptance testing against every provider.

## Existing WebDAV accounts

WebDAV remains the default, including installations with no saved backend choice. Adding S3 support does not migrate, clear, disable or replace an existing WebDAV connection. Its URL, account, password, sync directory, pending-batch identity and request policy are retained. Merely opening settings makes no cloud requests.

## Setup

1. Open **Settings → Sync**. The **WebDAV / Object storage** tabs select the sync backend and show its connection settings. If sync is enabled, turn it off and wait for existing transfers to finish before changing the backend or connection.
2. Select **Object storage**, then open **Object storage (S3 compatible)**. This is library synchronization, not the separate WebDAV remote-library browser. Upgrades reuse the existing WebDAV preference fields directly, including credentials and enabled state; no rewrite or cloud migration is needed.
3. Choose a provider preset and enter the service **Endpoint**, **Region**, **Bucket**, **Sync prefix**, **AccessKey ID / SecretId** and **Secret Access Key / SecretKey**. Replace preset example regions with your bucket's actual region. The default prefix is `modu`; case is significant.
4. Advanced settings contain temporary session tokens, path-style / virtual-host / bucket-bound custom-domain addressing, signature V4 / V2, ListObjects V2 / V1 and explicit HTTP opt-in. Prefer HTTPS.
5. Choose **Test connection**. The test lists the configured prefix and creates, downloads, verifies and deletes a uniquely named probe beneath it. It never clears a bucket or tests by overwriting a library database.
6. Save, then enable cloud sync. Configure other devices with the same bucket and prefix. Keep your original local books until all devices have synchronized successfully.

WebDAV and object-store credentials are saved separately. Explicitly switching back restores the previous WebDAV configuration; switching does not copy data between clouds. Download remote-only books before moving to a different backend, and back up first. Do not point unrelated apps at the same prefix: ReadAny and Readest database formats are not interchangeable with Modu.

## Provider presets

| Provider | Example service endpoint | Default addressing / signature |
| --- | --- | --- |
| Amazon S3 | `https://s3.us-east-1.amazonaws.com` | Virtual host / V4 |
| Alibaba Cloud OSS | `https://s3.oss-cn-hangzhou.aliyuncs.com` | Virtual host / V4 |
| Tencent Cloud COS | `https://cos.ap-guangzhou.myqcloud.com` | Virtual host / V2; bucket name includes APPID |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` | Path style / V4; region `auto` |
| RainYun ROS | `https://cn-sy1.rains3.com` | Path style / V4; region `rainyun` |
| Qiniu Kodo | `https://s3.cn-east-1.qiniucs.com` | Virtual host / V4; use the **S3 space name**, which may differ from the regular name |
| Baidu BOS | `https://s3.bj.bcebos.com` | Virtual host / V4; region `bj` |
| Volcengine TOS | `https://tos-s3-cn-beijing.volces.com` | Virtual host / V4; region `cn-beijing` |
| MinIO and other S3-compatible services | Obtain the S3 endpoint and region from the provider | Path style / V4 by default; adjust if required |

Use the S3-compatible endpoint, not a console URL or public download link. Service endpoints normally exclude the bucket and any object path; the custom-domain option is the exception for a domain already bound to one bucket. Region, signature and listing support vary by provider. See [Alibaba OSS AWS SDK compatibility](https://www.alibabacloud.com/help/en/oss/developer-reference/use-aws-sdks-to-access-oss) and [Tencent COS AWS SDK compatibility](https://intl.cloud.tencent.com/document/product/436/32537?lang=en).

Provider guidance follows official [RainYun examples](https://www.rainyun.com/docs/guide/ros/nodejs/), [Qiniu S3 endpoint and space-name rules](https://developer.qiniu.com/kodo/4088/s3-access-domainname), [Baidu S3 endpoints](https://cloud.baidu.com/doc/BOS/s/xjwvyq9l4-en) and [Volcengine S3 SDK examples](https://docs.volcengine.com/docs/TorchObjectStorage/AccessingTOSUsingAWSS3SDK). Some Alibaba accounts/regions require a bucket-bound custom domain and HTTPS certificate. Huawei OBS has no validated preset: its official rules prohibit path-style access, and further signing/listing compatibility checks are still needed.

Selecting a different provider resets the form's bucket, credentials, temporary token and insecure-HTTP option, preventing accidental reuse of another provider's keys. Cancel leaves the saved configuration intact. Passwords, access keys and tokens are hidden by default and use the same Show/Hide control; revealing a value never saves it or enables sync. Endpoint/region mismatches and known incompatible addressing options are rejected before connection tests.

Automatic sync, Wi-Fi-only and **Sync service settings, API keys and passwords** are shared options for both backends. The latter remains off by default and requires a separate encryption password. It syncs encrypted AI/translation/vector/speech/remote-library settings, **not** WebDAV or object-storage connection credentials. Explicit encrypted backups can include those credentials. Do not confuse a WebDAV app password, an object-storage access key and the sync encryption password.

## Permissions and data protection

- Create a private bucket yourself. Modu does not create buckets or change their public-access policy. Give the key bucket-list permission limited to the chosen prefix plus object read, write and delete permission beneath that prefix. Public access is unnecessary.
- Configuration is stored in local preferences, not an OS keychain. Protect device access. Default settings backups omit credentials; explicitly including them creates recoverable credentials. Object-store keys are not propagated through AI-settings sync.
- Books and records are not automatically encrypted at rest by Modu. Enable provider-side encryption if needed. The separate encrypted service-settings feature does not encrypt the entire library.
- S3 synchronization uses content-addressed immutable record batches with read-back verification and the existing merge/conflict rules. It does not plain-PUT a shared `database8.db`. Published batches are compacted through the existing verified-log mechanism.
- Listing errors, missing continuation tokens and access failures are not treated as an empty cloud library. Failed downloads leave existing local files intact. Signed requests do not follow redirects; fix the endpoint instead of forwarding credentials to a new host.
- Uploads stream from disk, with payload hashing before transfer. Maximum single file size is 5 GiB; multipart upload/resume is not implemented. HTTP 429/503 triggers in-session cooldown, honoring Retry-After; this is not a persistent cross-device quota.

## Verification and references

Automated tests use an isolated local HTTP object-store fixture: signing against AWS SDK reference values, V1/V2 pagination, Unicode keys, probes, transfer failure safety, two-device record merging and existing WebDAV compatibility. Provider presets are not a substitute for acceptance testing against each user's actual bucket. No real cloud bucket was modified for these tests.

Configuration flow references: [ReadAny](https://github.com/codedogQBY/ReadAny) and [Readest](https://github.com/readest/readest). See [upstream attribution](../UPSTREAM.md).
