import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/widgets/ai/ai_provider_logo.dart';
import 'package:anx_reader/widgets/ai/ai_provider_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiProviderListPage extends ConsumerWidget {
  const AiProviderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final providers = ref.watch(aiProvidersProvider);
    final selectedId =
        ref.watch(aiProvidersProvider.notifier).getSelectedProvider()?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiProviders),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addProvider(context, ref),
            tooltip: l10n.settingsAiProvidersAdd,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: providers.length,
        itemBuilder: (context, index) {
          final provider = providers[index];
          final isSelected = provider.id == selectedId;
          final hasValidKey = provider.hasValidKey;

          final tile = ListTile(
            leading: AiProviderLogo(provider: provider),
            title: Text(provider.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.url,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!hasValidKey)
                  Text(
                    l10n.settingsAiProviderNoValidKeys,
                    style: TextTheme.of(context).bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Chip(
                    label: Text(l10n.settingsAiProviderDefault),
                    labelStyle: TextTheme.of(context).labelSmall,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  )
                else
                  TextButton(
                    onPressed: provider.enabled
                        ? () {
                            ref
                                .read(aiProvidersProvider.notifier)
                                .setSelectedProvider(provider.id);
                          }
                        : null,
                    child: Text(l10n.settingsAiProviderSetDefault),
                  ),
                const SizedBox(width: 8),
                Switch(
                  value: provider.enabled,
                  onChanged: (value) {
                    ref
                        .read(aiProvidersProvider.notifier)
                        .toggleProvider(provider.id, value);
                  },
                ),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AiProviderDetailPage(providerId: provider.id),
                ),
              );
            },
            onLongPress: provider.isBuiltin
                ? null
                : () => _deleteProvider(context, ref, provider),
          );
          if (provider.isBuiltin) return tile;
          return Dismissible(
            key: ValueKey('provider-${provider.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: AlignmentDirectional.centerEnd,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            confirmDismiss: (_) async {
              // Remove from the provider store after confirmation; keep the
              // swipe route from deleting a row whose backing data changed.
              await _deleteProvider(context, ref, provider);
              return false;
            },
            child: tile,
          );
        },
      ),
    );
  }

  Future<void> _addProvider(BuildContext context, WidgetRef ref) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiProviderDetailPage(providerId: null),
      ),
    );
  }

  Future<void> _deleteProvider(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
  ) async {
    if (await confirmDeleteAiProvider(context, provider) && context.mounted) {
      ref.read(aiProvidersProvider.notifier).deleteProvider(provider.id);
    }
  }
}
