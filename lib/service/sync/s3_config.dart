/// S3-compatible transport options, independent from library/sync state.
class S3Config {
  S3Config(Map<String, dynamic> values) : values = Map.unmodifiable(values) {
    validate();
  }
  final Map<String, dynamic> values;
  String text(String key, [String fallback = '']) =>
      (values[key] as String?) ?? fallback;
  Uri get endpoint => Uri.parse(text('endpoint'));
  String get bucket => text('bucket');
  String get region => text('region', 'us-east-1');
  String get accessKey => text('accessKeyId');
  String get secretKey => text('secretAccessKey');
  String get token => text('sessionToken');
  String get root => text('remoteRoot', 'modu');
  String get addressing => text('addressing', 'path');
  String get signature => text('signature', 'v4');
  String get listVersion => text('listVersion', 'v2');
  // RainYun uses form encoding (space -> '+') for encoding-type=url.
  // Request literal XML names instead of guessing what a '+' represents.
  // Match both the preset (including custom domains) and existing configs
  // using an official endpoint without a saved provider field.
  bool get useEncodedListingNames =>
      text('provider') != 'rainyun' &&
      endpoint.host != 'rains3.com' &&
      !endpoint.host.endsWith('.rains3.com');
  bool get configured => accessKey.isNotEmpty && secretKey.isNotEmpty;

  void validate() {
    if (values.containsKey('allowInsecure') &&
        values['allowInsecure'] is! bool) {
      throw const FormatException('Invalid HTTP option');
    }
    for (final key in [
      'endpoint',
      'bucket',
      'region',
      'accessKeyId',
      'secretAccessKey',
      'sessionToken',
      'remoteRoot',
      'addressing',
      'signature',
      'listVersion',
      'provider'
    ]) {
      if (values.containsKey(key) && values[key] is! String) {
        throw const FormatException('Invalid S3 configuration');
      }
    }
    final url = endpoint;
    if (!['https', 'http'].contains(url.scheme) ||
        url.host.isEmpty ||
        RegExp(r'[<>%\s]').hasMatch(url.host) ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (url.path.isNotEmpty && url.path != '/') ||
        (url.scheme == 'http' && values['allowInsecure'] != true)) {
      throw const FormatException(
          'Use an HTTPS service endpoint without a bucket, path or credentials');
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(bucket) ||
        bucket.contains('..') ||
        !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(region)) {
      throw const FormatException('Invalid bucket or region');
    }
    if (!['path', 'virtual', 'domain'].contains(addressing) ||
        !['v4', 'v2'].contains(signature) ||
        !['v1', 'v2'].contains(listVersion)) {
      throw const FormatException('Invalid S3 protocol option');
    }
    checkPath(root);
    if (root.isEmpty || root.startsWith('/') || root.endsWith('/')) {
      throw const FormatException(
          'Sync prefix must be a non-empty relative path');
    }
    for (final value in [accessKey, secretKey, token]) {
      if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException('Invalid credential characters');
      }
    }
  }

  static void checkPath(String path) {
    if (path.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        path.split('/').any((p) => p == '.' || p == '..' || p.isEmpty)) {
      throw const FormatException('Unsafe object path');
    }
  }

  String key(String logicalPath) {
    var path =
        logicalPath.startsWith('/') ? logicalPath.substring(1) : logicalPath;
    final trailing = path.endsWith('/');
    if (trailing) path = path.substring(0, path.length - 1);
    checkPath(path);
    if (path != 'modu' && !path.startsWith('modu/')) {
      throw const FormatException(
          'Object path is outside the Modu sync directory');
    }
    return '$root${path.substring(4)}${trailing ? '/' : ''}';
  }

  String logicalPath(String key) {
    if (key != root && !key.startsWith('$root/')) {
      throw const FormatException('Unexpected object prefix');
    }
    final path = 'modu${key.substring(root.length)}';
    // Validate the inverse mapping too; remote names are untrusted input.
    this.key(path);
    return path;
  }

  List<Object?> get identity =>
      ['S3', endpoint.origin.toLowerCase(), bucket, root, accessKey];
}

enum S3Preset {
  custom('S3 compatible / MinIO', '', 'us-east-1', 'path', 'v4'),
  aws('Amazon S3', 'https://s3.us-east-1.amazonaws.com', 'us-east-1', 'virtual',
      'v4'),
  aliyun('Alibaba Cloud OSS / 阿里云', 'https://s3.oss-cn-hangzhou.aliyuncs.com',
      'cn-hangzhou', 'virtual', 'v4'),
  tencent('Tencent Cloud COS / 腾讯云', 'https://cos.ap-guangzhou.myqcloud.com',
      'ap-guangzhou', 'virtual', 'v2'),
  r2('Cloudflare R2', 'https://<account-id>.r2.cloudflarestorage.com', 'auto',
      'path', 'v4'),
  rainyun(
      'RainYun ROS / 雨云', 'https://cn-sy1.rains3.com', 'rainyun', 'path', 'v4'),
  qiniu('Qiniu Kodo / 七牛云', 'https://s3.cn-east-1.qiniucs.com', 'cn-east-1',
      'virtual', 'v4'),
  baidu('Baidu Cloud BOS / 百度云', 'https://s3.bj.bcebos.com', 'bj', 'virtual',
      'v4'),
  volcengine('Volcengine TOS / 火山引擎', 'https://tos-s3-cn-beijing.volces.com',
      'cn-beijing', 'virtual', 'v4');

  const S3Preset(
      this.label, this.endpoint, this.region, this.addressing, this.signature);
  final String label, endpoint, region, addressing, signature;
}
