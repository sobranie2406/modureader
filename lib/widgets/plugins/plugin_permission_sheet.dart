import 'package:flutter/material.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_permissions.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_labels.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';

/// Asks the user to grant runtime capabilities, with the plugin's own reason.
///
/// This is the only way a plugin can obtain a runtime grant at run time. The
/// user sees one row per capability with its own checkbox, so a request for
/// three capabilities cannot smuggle in a fourth, and "allow once" is not
/// offered — grants are durable device decisions, exactly like the switch on
/// the details page.
///
/// Returns the grants in force after the dialog closes. Cancelling or tapping
/// outside returns the grants the plugin already held, never a fresh one.
Future<Set<String>> showPluginPermissionRequest(
  BuildContext context, {
  required PluginHost host,
  required String pluginId,
  required List<String> capabilities,
  required String reason,
}) async {
  // Only what this package actually declares: showing a row the host would
  // refuse to grant would let a plugin ask for a permission it never requested
  // at installation, and the grant call would then fail after the user agreed.
  final declared = host.manifestFor(pluginId)?.capabilities ?? const <String>{};
  final requested = <PluginPermissionSpec>[];
  for (final capability in capabilities) {
    if (!declared.contains(capability)) continue;
    final spec = pluginPermissionSpec(capability);
    if (spec != null && spec.isRuntime) requested.add(spec);
  }
  final record = host.byId(pluginId);
  if (requested.isEmpty || record == null) {
    return host.grantedPermissions(pluginId);
  }
  final before = host.grantedPermissions(pluginId);
  if (!context.mounted) return before;

  final answer = await showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => _PermissionDialog(
      host: host,
      pluginId: pluginId,
      pluginName: record.name.resolve(
          Localizations.localeOf(dialog).toLanguageTag()),
      specs: requested,
      reason: reason,
      initial: before,
    ),
  );
  if (answer == null) {
    // Dismissed without confirming: keep whatever was already granted.
    return host.grantedPermissions(pluginId);
  }
  // Grant first, in one batch that does not disturb running work: the caller is
  // usually the plugin's own in-flight job, and cancelling it here would make
  // the just-granted permission impossible to use. Revoking still goes through
  // setPermission, which stops the plugin's task on purpose.
  final toGrant = [
    for (final spec in requested)
      if (answer.contains(spec.token) && !before.contains(spec.token))
        spec.token,
  ];
  if (toGrant.isNotEmpty) await host.grantPermissions(pluginId, toGrant);
  for (final spec in requested) {
    if (before.contains(spec.token) && !answer.contains(spec.token)) {
      await host.setPermission(pluginId, spec.token, false);
    }
  }
  return host.grantedPermissions(pluginId);
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog({
    required this.host,
    required this.pluginId,
    required this.pluginName,
    required this.specs,
    required this.reason,
    required this.initial,
  });

  final PluginHost host;
  final String pluginId;
  final String pluginName;
  final List<PluginPermissionSpec> specs;
  final String reason;
  final Set<String> initial;

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  late final Set<String> _selected = {
    for (final spec in widget.specs)
      if (widget.initial.contains(spec.token)) spec.token,
  };

  /// A new capability defaults to **off**: the plugin must earn it, and the
  /// user is asked to make an explicit choice rather than accept a pre-ticked
  /// checkbox.
  bool get _allOff => _selected.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String t(String zh, String en) => ModuStrings.text(context, zh, en);
    final dangerous =
        widget.specs.where((spec) => spec.danger).toList(growable: false);
    return AlertDialog(
      title: Text(t('插件请求权限', 'Plugin permission request')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.pluginName, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (widget.reason.isNotEmpty) ...[
              Text(
                widget.reason,
                style: theme.textTheme.bodyMedium,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 4),
            for (final spec in widget.specs)
              CheckboxListTile(
                key: ValueKey('plugin-permission-request-${spec.token}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                secondary: spec.danger
                    ? Icon(Icons.warning_amber_outlined,
                        color: theme.colorScheme.error)
                    : null,
                title: Text(pluginCapabilityLabel(context, spec.token)),
                subtitle: Text(spec.token),
                value: _selected.contains(spec.token),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(spec.token);
                  } else {
                    _selected.remove(spec.token);
                  }
                }),
              ),
            if (dangerous.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                t('标有警告的能力可能产生费用或读取敏感内容，请确认该插件确实需要。',
                    'Capabilities marked with a warning can cost money or read sensitive content. Make sure this plugin really needs them.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('拒绝', 'Deny')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(_allOff
              ? t('继续保持关闭', 'Keep everything off')
              : t('允许所选项', 'Allow selected')),
        ),
      ],
    );
  }
}
