import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/utils/changelog.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anx_reader/utils/log/common.dart';

/// Changelog screen for showing app updates
/// Displays version history and new features
class ChangelogScreen extends StatefulWidget {
  final String lastVersion;
  final String currentVersion;
  final VoidCallback onComplete;

  const ChangelogScreen({
    super.key,
    required this.lastVersion,
    required this.currentVersion,
    required this.onComplete,
  });

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  String _changelogContent = '';
  bool _isLoading = true;

  String get currentVersion => widget.currentVersion.split('+').first;
  String get lastVersion => widget.lastVersion.split('+').first;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    try {
      // Load changelog from assets
      final String fullChangelog =
          await rootBundle.loadString('assets/CHANGELOG.md');
      _changelogContent = changelogSince(fullChangelog,
          previous: widget.lastVersion,
          current: widget.currentVersion,
          chinese: getCurrentLanguageCode().startsWith('zh'));
      if (_changelogContent.isEmpty) _changelogContent = _getDefaultChangelog();
    } catch (e) {
      AnxLog.warning('Failed to load changelog from assets: $e');
      _changelogContent = _getDefaultChangelog();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getDefaultChangelog() => getCurrentLanguageCode().startsWith('zh')
      ? '暂无此版本的更新说明。'
      : 'Release notes are unavailable for this version.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).whatsNew),
        elevation: 0,
        actions: [],
      ),
      body: _isLoading
          ? const Center(
              child: EinkStaticIndicator(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.update,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            L10n.of(context).updateFromVersion(lastVersion),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.of(context).welcomeToVersion(currentVersion),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: StyledMarkdown(data: _changelogContent),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _onComplete,
                    child: Text(L10n.of(context).commonOk),
                  ),
                ),
              ],
            ),
    );
  }

  void _onComplete() async {
    widget.onComplete();
  }
}
