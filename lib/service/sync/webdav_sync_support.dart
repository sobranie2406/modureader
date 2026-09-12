part of 'webdav_client.dart';

extension _WebdavSyncSupport on WebdavClient {
  Future<bool> _probeAtomicSyncWrites() async {
    final folder = '${SyncPaths.root}/.sync-probes/${const Uuid().v4()}';
    final target = '$folder/database8.db';
    final temp =
        await io.Directory.systemTemp.createTemp('modu-dav-capability-');
    final source = io.File('${temp.path}/probe');
    final received = io.File('${temp.path}/received');
    var created = false;
    try {
      await mkdirAll(folder);
      created = true;
      await source.writeAsString('modu-probe-a');
      await uploadFile(source.path, target);
      final first = await readProps(target);
      if (!WebdavClient.isStrongETag(first?.eTag)) return false;
      await source.writeAsString('modu-probe-b');
      await uploadFileConditionally(source.path, target,
          expectedETag: first!.eTag);
      final second = await readProps(target);
      if (!WebdavClient.isStrongETag(second?.eTag) ||
          first.eTag == second!.eTag) {
        return false;
      }
      await source.writeAsString('modu-probe-must-not-overwrite');
      for (final createOnly in [false, true]) {
        try {
          await uploadFileConditionally(source.path, target,
              expectedETag: first.eTag, createOnly: createOnly);
          // A successful stale/duplicate write proves the validator unreliable.
          return false;
        } on DioException catch (e) {
          if (e.response?.statusCode != 412) rethrow;
        }
        await downloadFile(target, received.path);
        if (await received.readAsString() != 'modu-probe-b') return false;
      }
      return true;
    } on DioException catch (e) {
      // Even a matching token may be rejected by a broken implementation.
      // This isolated random object has no legitimate competing writers.
      if ([405, 412, 501].contains(e.response?.statusCode)) return false;
      // Authentication, transient network/server failures are not a capability.
      rethrow;
    } finally {
      if (created) {
        // Exact unique probe only; never delete the shared probe parent or data.
        try {
          await remove(target);
        } catch (_) {}
        try {
          await remove(folder);
        } catch (_) {}
      }
      await temp.delete(recursive: true);
    }
  }

  Future<List<RemoteFile>> _readCompleteSyncDirectory(String path) async {
    final endpoint = Uri.parse(_config['url'] as String);
    final rootPath =
        '${endpoint.path.replaceFirst(RegExp(r'/$'), '')}/${_safeEncodePath(path).replaceFirst(RegExp(r'^/'), '')}/';
    final root = endpoint.replace(
        path: Uri.decodeFull(rootPath), query: null, fragment: null);
    Uri next = root;
    final seen = <String>{};
    final entries = <String, RemoteFile>{};
    while (true) {
      if (next.origin != root.origin ||
          next.path != root.path ||
          next.userInfo.isNotEmpty ||
          next.fragment.isNotEmpty ||
          !seen.add(next.toString()) ||
          seen.length > 1000) {
        throw const FormatException('WebDAV 分页地址无效，已停止同步');
      }
      final response = await _client.c.req(_client, 'PROPFIND', next.toString(),
          data: '<d:propfind xmlns:d="DAV:"><d:prop>'
              '<d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>',
          optionsHandler: (options) {
        options.followRedirects = false;
        options.headers!['depth'] = '1';
        options.headers!['content-type'] = 'application/xml';
        options.responseType = ResponseType.plain;
      });
      if (response.statusCode != 207) {
        throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse);
      }
      final xml = response.data as String;
      if (xml.length > 8 * 1024 * 1024) {
        throw const FormatException('WebDAV 目录响应过大');
      }
      final document = XmlDocument.parse(xml);
      final resources = document.findAllElements('response', namespace: 'DAV:');
      if (resources.isEmpty) throw const FormatException('WebDAV 返回了空的目录响应');
      for (final resource in resources) {
        final href = resource.getElement('href', namespace: 'DAV:')?.innerText;
        if (href == null) throw const FormatException('WebDAV 目录缺少路径');
        final uri = root.resolve(href);
        final decoded =
            Uri.decodeComponent(uri.path).replaceFirst(RegExp(r'/$'), '');
        final parent =
            Uri.decodeComponent(root.path).replaceFirst(RegExp(r'/$'), '');
        if (uri.origin != root.origin ||
            !decoded.startsWith('$parent/') && decoded != parent) {
          throw const FormatException('WebDAV 目录返回了越界路径');
        }
        if (decoded == parent) continue;
        final name = decoded.substring(parent.length + 1);
        if (name.isEmpty ||
            name.contains('/') ||
            name.contains('\\') ||
            name == '.' ||
            name == '..') {
          throw const FormatException('WebDAV 子路径无效');
        }
        final status =
            resource.getElement('status', namespace: 'DAV:')?.innerText;
        if (status != null && !RegExp(r'\s200(?:\s|$)').hasMatch(status)) {
          throw const FormatException('WebDAV 目录包含无法读取的条目');
        }
        final props = resource
            .findElements('propstat', namespace: 'DAV:')
            .where((p) => RegExp(r'\s200(?:\s|$)').hasMatch(
                p.getElement('status', namespace: 'DAV:')?.innerText ?? ''))
            .expand((p) => p.findElements('prop', namespace: 'DAV:'))
            .toList();
        if (props.isEmpty) throw const FormatException('WebDAV 子项属性读取失败');
        final directory = props.any((p) =>
            p.findAllElements('collection', namespace: 'DAV:').isNotEmpty);
        final sizes = props
            .expand(
                (p) => p.findElements('getcontentlength', namespace: 'DAV:'))
            .toList();
        entries[name] = RemoteFile(
            name: name,
            path: '$path/$name',
            isDir: directory,
            size: sizes.isEmpty ? null : int.tryParse(sizes.first.innerText));
        if (entries.length > 10000) throw const FormatException('同步目录超过安全限制');
      }
      final link = response.headers.value('link');
      if (link == null || link.trim().isEmpty) {
        // Nutstore documents a 750-item page limit. A full page without its
        // continuation token cannot safely be acknowledged as a complete scan.
        if ((root.host == 'dav.jianguoyun.com') && resources.length >= 750) {
          throw const FormatException('坚果云目录可能被截断，缺少分页信息，已停止同步');
        }
        break;
      }
      final match = RegExp(r'<([^>]+)>;\s*rel="next"').firstMatch(link);
      if (match == null) throw const FormatException('无法识别 WebDAV 分页信息');
      next = root.resolve(match[1]!);
    }
    return entries.values.toList();
  }
}
