import 'package:modu_reader/enums/sync_direction.dart';
import 'package:modu_reader/enums/sync_trigger.dart';
import 'package:modu_reader/providers/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncButton extends ConsumerStatefulWidget {
  const SyncButton({super.key});

  @override
  ConsumerState createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<SyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _syncAnimationController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _animation = Tween(begin: 1.0, end: 0.0).animate(_syncAnimationController);
  }

  @override
  void dispose() {
    _syncAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = ref.watch(syncProvider.select((s) => s.isSyncing));
    final motion = !MediaQuery.disableAnimationsOf(context);
    if (isSyncing && motion && !_syncAnimationController.isAnimating) {
      _syncAnimationController.repeat();
    } else if (!isSyncing || !motion) {
      _syncAnimationController.stop();
    }

    return IconButton(
      icon: isSyncing && motion
          ? RepaintBoundary(
              child: RotationTransition(
                turns: _animation,
                child: const Icon(Icons.sync),
              ),
            )
          : const Icon(Icons.sync),
      onPressed: isSyncing
          ? null
          : () {
              ref.read(syncProvider.notifier).syncData(SyncDirection.both, ref,
                  trigger: SyncTrigger.manual);
            },
    );
  }
}
