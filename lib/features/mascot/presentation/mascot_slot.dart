import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../application/mascot_controller.dart';
import '../domain/mascot_state.dart';
import 'mascot_assets.dart';

enum MascotSlotVariant { hero, drawer, input }

class MascotSlot extends ConsumerWidget {
  const MascotSlot({
    required this.slotId,
    this.variant = MascotSlotVariant.hero,
    this.stateOverride,
    super.key,
  });

  final String slotId;
  final MascotSlotVariant variant;
  final MascotState? stateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MascotState state =
        stateOverride ?? ref.watch(mascotControllerProvider);
    final visual = _MascotVisual.fromState(state);
    final scheme = Theme.of(context).colorScheme;
    final metrics = _SlotMetrics.fromVariant(variant);

    return Semantics(
      label: 'MascotSlot ${state.name}',
      child: DecoratedBox(
        key: Key('mascot-slot-$slotId'),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          border: Border.all(color: scheme.secondary.withValues(alpha: 0.36)),
          borderRadius: BorderRadius.circular(
            variant == MascotSlotVariant.input
                ? AppTokens.radiusS
                : AppTokens.radiusM,
          ),
        ),
        child: SizedBox(
          width: metrics.width,
          height: metrics.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              variant == MascotSlotVariant.input
                  ? AppTokens.radiusS
                  : AppTokens.radiusM,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  MascotAssets.forState(state),
                  fit: BoxFit.cover,
                  alignment: metrics.alignment,
                  gaplessPlayback: true,
                  cacheWidth: metrics.cacheWidth,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.82),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spacingXs,
                          vertical: 3,
                        ),
                        child: Text(
                          visual.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotMetrics {
  const _SlotMetrics({
    required this.width,
    required this.height,
    required this.cacheWidth,
    required this.alignment,
  });

  final double width;
  final double height;
  final int cacheWidth;
  final Alignment alignment;

  static _SlotMetrics fromVariant(MascotSlotVariant variant) {
    return switch (variant) {
      MascotSlotVariant.hero => const _SlotMetrics(
        width: AppTokens.mascotHeroWidth,
        height: AppTokens.mascotHeroHeight,
        cacheWidth: 520,
        alignment: Alignment.center,
      ),
      MascotSlotVariant.drawer => const _SlotMetrics(
        width: AppTokens.mascotDrawerSize,
        height: AppTokens.mascotDrawerSize,
        cacheWidth: 180,
        alignment: Alignment.center,
      ),
      MascotSlotVariant.input => const _SlotMetrics(
        width: AppTokens.mascotInputSize,
        height: AppTokens.mascotInputSize,
        cacheWidth: 120,
        alignment: Alignment.center,
      ),
    };
  }
}

class _MascotVisual {
  const _MascotVisual(this.label);

  final String label;

  static _MascotVisual fromState(MascotState state) {
    return switch (state) {
      MascotState.idle => const _MascotVisual('待机'),
      MascotState.thinking => const _MascotVisual('思考'),
      MascotState.happy => const _MascotVisual('开心'),
      MascotState.sleeping => const _MascotVisual('休息'),
      MascotState.peeking => const _MascotVisual('探头'),
      MascotState.listening => const _MascotVisual('倾听'),
    };
  }
}
