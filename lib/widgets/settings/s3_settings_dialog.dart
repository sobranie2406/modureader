import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/sync/s3_client.dart';
import 'package:modu_reader/service/sync/s3_config.dart';
import 'package:modu_reader/service/sync/sync_feedback.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/settings/sync_secret_field.dart';

class S3SettingsDialog extends StatefulWidget {
  const S3SettingsDialog({super.key, required this.initial});
  final Map<String, dynamic> initial;
  @override
  State<S3SettingsDialog> createState() => _S3SettingsDialogState();
}

class _S3SettingsDialogState extends State<S3SettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late String provider, addressing, signature, listVersion;
  late bool insecure;
  bool busy = false;
  String? message;
  int credentialRevision = 0;
  String tr(String zh, String en) => ModuStrings.text(context, zh, en);

  String get _providerHelp => switch (provider) {
        'aws' => tr('选择桶实际所在区域，Endpoint 与 Region 必须一致。',
            'Use the bucket’s actual region; Endpoint and Region must match.'),
        'aliyun' => tr("填写 OSS 的 S3 端点：s3.oss-区域.aliyuncs.com。",
            "Enter the OSS S3 endpoint: s3.oss-REGION.aliyuncs.com."),
        'tencent' => tr("桶名需包含 APPID，例如 books-1250000000。",
            "Include the APPID in the bucket name, for example books-1250000000."),
        'r2' => tr(
            '将 <account-id> 替换为 Cloudflare 账户 ID，Region 填 auto。使用 R2 的 S3 访问密钥，不是普通 API Token。',
            'Replace <account-id> with your Cloudflare account ID; set Region to auto. Use R2 S3 access credentials, not a general API token.'),
        'rainyun' => tr("填写雨云控制台提供的 S3 端点，区域填写 rainyun。",
            "Use the S3 endpoint from the RainYun console and rainyun as the region."),
        'qiniu' => tr("填写空间概览中的“S3 空间名”、端点和区域。",
            "Copy the S3 space name, endpoint and region from the space overview."),
        'baidu' => tr("填写所在区域的 S3 端点，例如 s3.bj.bcebos.com。",
            "Enter your region’s S3 endpoint, such as s3.bj.bcebos.com."),
        'volcengine' => tr("填写 tos-s3-区域.volces.com，选择虚拟主机寻址。",
            "Enter tos-s3-REGION.volces.com and select virtual-host addressing."),
        _ => tr("填写服务商提供的 S3 兼容端点。",
            "Enter the S3-compatible endpoint provided by your service."),
      };
  @override
  void initState() {
    super.initState();
    fields = {
      for (final key in [
        'endpoint',
        'region',
        'bucket',
        'remoteRoot',
        'accessKeyId',
        'secretAccessKey',
        'sessionToken'
      ])
        key: TextEditingController(
            text: widget.initial[key] as String? ??
                (key == 'region'
                    ? 'us-east-1'
                    : key == 'remoteRoot'
                        ? 'modu'
                        : ''))
    };
    provider = widget.initial['provider'] as String? ?? 'custom';
    if (!S3Preset.values.any((p) => p.name == provider)) provider = 'custom';
    addressing = widget.initial['addressing'] as String? ?? 'path';
    signature = widget.initial['signature'] as String? ?? 'v4';
    listVersion = widget.initial['listVersion'] as String? ?? 'v2';
    insecure = widget.initial['allowInsecure'] == true;
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get values => {
        for (final field in fields.entries)
          field.key: field.key == 'secretAccessKey'
              ? field.value.text
              : field.value.text.trim(),
        'provider': provider,
        'addressing': addressing,
        'signature': signature,
        'listVersion': listVersion,
        'allowInsecure': insecure,
      };
  bool validate() {
    if (!_form.currentState!.validate()) return false;
    try {
      final config = S3Config(values);
      final host = config.endpoint.host;
      String? hint;
      if (addressing == 'path' &&
          (provider == 'tencent' ||
              provider == 'baidu' ||
              provider == 'volcengine' ||
              host.endsWith('.myhuaweicloud.com'))) {
        hint = tr('此服务请使用虚拟主机寻址；已绑定桶的自定义域名请选择对应选项。',
            'Use virtual-host addressing for this service, or custom-domain addressing for a bucket-bound domain.');
      } else if (provider == 'tencent' &&
          !RegExp(r'-[0-9]+$').hasMatch(config.bucket)) {
        hint = tr(
            'COS 桶名须包含结尾的 -APPID。', 'COS bucket names must end with -APPID.');
      } else if (provider == 'r2' &&
          !['auto', 'us-east-1'].contains(config.region)) {
        hint = tr('R2 的 Region 请填写 auto。', 'Use auto as the R2 region.');
      } else {
        final patterns = <String, RegExp>{
          'aws': RegExp(r'^s3[.-]([a-z0-9-]+)\.amazonaws\.com(?:\.cn)?$'),
          'aliyun': RegExp(r'^s3\.oss-([a-z0-9-]+)\.aliyuncs\.com$'),
          'tencent': RegExp(r'^cos\.([a-z0-9-]+)\.myqcloud\.com$'),
          'qiniu': RegExp(r'^s3\.([a-z0-9-]+)\.qiniucs\.com$'),
          'baidu': RegExp(r'^s3\.([a-z0-9-]+)\.bcebos\.com$'),
          'volcengine': RegExp(r'^tos-s3-([a-z0-9-]+)\.volces\.com$'),
        };
        final endpointRegion = patterns[provider]?.firstMatch(host)?.group(1);
        if (addressing != 'domain' &&
            endpointRegion != null &&
            endpointRegion != config.region) {
          hint = tr('Endpoint 与 Region 不一致，请按桶所在区域填写。',
              'Endpoint and Region do not match. Use your bucket’s actual region.');
        }
      }
      if (hint != null) {
        setState(() => message = hint);
        return false;
      }
      return true;
    } catch (_) {
      setState(() => message = tr("请检查端点、桶名、区域和同步目录。",
          "Check the endpoint, bucket, region and sync folder."));
      return false;
    }
  }

  Widget field(String key, String label,
          {bool secret = false, bool optional = false, String? helper}) =>
      Padding(
          key: secret ? ValueKey('s3-$key') : null,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: secret
              ? SyncSecretField(
                  key: ValueKey('s3-secret-$key-$credentialRevision'),
                  controller: fields[key]!,
                  label: label,
                  enabled: !busy,
                  helperText: helper,
                  validator: (value) =>
                      !optional && (value?.trim().isEmpty ?? true)
                          ? tr('请填写此项', 'Required')
                          : null,
                )
              : TextFormField(
                  key: ValueKey('s3-$key'),
                  controller: fields[key],
                  enabled: !busy,
                  obscureText: secret,
                  autocorrect: false,
                  enableSuggestions: !secret,
                  decoration: InputDecoration(
                      labelText: label,
                      helper: (helper) == null
                          ? null
                          : SettingHelpTitle(
                              title: ModuStrings.text(context, "说明", "Help"),
                              description: helper),
                      border: const OutlineInputBorder()),
                  validator: (value) =>
                      !optional && (value?.trim().isEmpty ?? true)
                          ? tr('请填写此项', 'Required')
                          : null));
  Widget choice(String key, String label, String value,
          Map<String, String> items, ValueChanged<String> change) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
              key: ValueKey('s3-$key-$value'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: items.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                        message = null;
                        change(value!);
                      })));
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(tr('对象存储（S3 兼容）', 'Object storage (S3 compatible)')),
          content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "连接步骤", "Connection steps")),
                            description: Text(tr("填写桶名和访问密钥后，点击“测试连接”。",
                                "Enter the bucket name and access keys, then test the connection."))),
                        choice('provider', tr('服务商预设', 'Provider preset'),
                            provider, {
                          for (final preset in S3Preset.values)
                            preset.name: preset.label
                        }, (value) {
                          if (provider == value) return;
                          provider = value;
                          final preset = S3Preset.values.byName(value);
                          fields['endpoint']!.text = preset.endpoint;
                          fields['region']!.text = preset.region;
                          addressing = preset.addressing;
                          signature = preset.signature;
                          listVersion = 'v2';
                          insecure = false;
                          // Never send the previous provider's credentials to
                          // a newly selected endpoint. Cancel keeps saved data.
                          for (final key in [
                            'bucket',
                            'accessKeyId',
                            'secretAccessKey',
                            'sessionToken'
                          ]) {
                            fields[key]!.clear();
                          }
                          credentialRevision++;
                        }),
                        SettingHelp(
                            title: Text(tr("端点填写", "Endpoint")),
                            description: Text(_providerHelp)),
                        field(
                            'endpoint',
                            tr('服务端点 Endpoint（HTTPS）',
                                'Service endpoint (HTTPS)'),
                            helper: tr("按实际区域填写端点，桶名在下方单独填写。",
                                "Enter the endpoint for your region. Enter the bucket name separately below.")),
                        field(
                            'region',
                            tr('区域 Region（按服务商要求填写）',
                                'Region (as required by provider)')),
                        field(
                            'bucket',
                            provider == 'qiniu'
                                ? tr('S3 空间名', 'S3 space name')
                                : provider == 'tencent'
                                    ? tr('存储桶 Bucket（含 -APPID）',
                                        'Bucket (including -APPID)')
                                    : tr('存储桶 Bucket', 'Bucket')),
                        field('remoteRoot', tr('同步目录 / 对象前缀', 'Sync prefix')),
                        field(
                            'accessKeyId',
                            provider == 'tencent'
                                ? 'SecretId'
                                : 'Access Key ID',
                            secret: true),
                        field(
                            'secretAccessKey',
                            provider == 'tencent'
                                ? 'SecretKey'
                                : 'Secret Access Key',
                            secret: true),
                        ExpansionTile(
                          key: const ValueKey('s3-advanced'),
                          title: Text(tr('高级设置', 'Advanced settings')),
                          maintainState: true,
                          children: [
                            field(
                                'sessionToken',
                                tr('临时令牌（可选，过期需更新）',
                                    'Session token (optional; renew after expiry)'),
                                secret: true,
                                optional: true),
                            choice(
                                'addressing',
                                tr('寻址方式', 'Addressing'),
                                addressing,
                                {
                                  'path': tr('路径式：endpoint/bucket',
                                      'Path style: endpoint/bucket'),
                                  'virtual': tr('虚拟主机：bucket.endpoint',
                                      'Virtual host: bucket.endpoint'),
                                  'domain': tr('已绑定桶的自定义域名',
                                      'Custom domain already bound to bucket'),
                                },
                                (v) => addressing = v),
                            choice(
                                'signature',
                                tr('签名版本', 'Signature version'),
                                signature,
                                {
                                  'v4': 'AWS Signature V4',
                                  'v2': 'AWS Signature V2 (COS / legacy)'
                                },
                                (v) => signature = v),
                            choice(
                                'listVersion',
                                tr('列举接口', 'List API'),
                                listVersion,
                                {
                                  'v2': 'ListObjects V2',
                                  'v1': 'ListObjects V1'
                                },
                                (v) => listVersion = v),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: insecure,
                                title: Text(tr('允许不加密的 HTTP（仅可信自建网络）',
                                    'Allow unencrypted HTTP (trusted private networks only)')),
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() => insecure = v)),
                          ],
                        ),
                        SettingHelp(
                            title: Text(ModuStrings.text(
                                context, "同步目录", "Sync folder")),
                            description: Text(tr(
                                "各设备使用相同的桶和目录。切换前请下载只保存在云端的书籍。",
                                "Use the same bucket and folder on each device. Download cloud-only books before switching."))),
                        if (busy)
                          const Padding(
                              padding: EdgeInsets.all(12),
                              child: EinkStaticIndicator(
                                  child: CircularProgressIndicator())),
                        if (message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(message!)),
                      ])))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: Text(tr('取消', 'Cancel'))),
            TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!validate()) return;
                        setState(() {
                          busy = true;
                          message = null;
                        });
                        try {
                          await S3SyncClient(values).testFullCapabilities();
                          if (mounted) {
                            setState(() => message = tr('连接、上传、下载校验和删除测试通过。',
                                'Connection, upload, read-back and deletion passed.'));
                          }
                        } catch (error) {
                          if (mounted) {
                            setState(() => message = syncFailureMessage(error,
                                chinese: Localizations.localeOf(context)
                                        .languageCode ==
                                    'zh'));
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(tr('测试连接', 'Test connection'))),
            FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        if (validate()) Navigator.pop(context, values);
                      },
                child: Text(tr('保存', 'Save'))),
          ]));
}
