import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/bubble_theme.dart';
import '../../../app/widgets/bubble_background.dart';

/// Lightweight shell for secondary and deep routes.
///
/// Primary navigation lives only on the novel and chat roots. This scaffold
/// intentionally has no drawer or dashboard navigation.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    required this.child,
    required this.currentLocation,
    this.title = '伊吹之家',
    this.subtitle = '',
    this.showBackButton = false,
    this.backFallbackLocation,
    this.childHandlesPop = false,
    this.showAppBar = true,
    super.key,
  });

  final Widget child;
  final String currentLocation;
  final String title;
  final String subtitle;
  final bool showBackButton;
  final String? backFallbackLocation;
  final bool childHandlesPop;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      key: const Key('secondary-page-shell'),
      backgroundColor: context.bubbleTheme.backgroundStart,
      resizeToAvoidBottomInset: true,
      appBar: !showAppBar
          ? null
          : AppBar(
              automaticallyImplyLeading: true,
              leading: showBackButton
                  ? BackButton(
                      key: const Key('shell-back-button'),
                      onPressed: () => _handleBack(context),
                    )
                  : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
      body: BubbleBackground(child: child),
    );
    if (!showBackButton || backFallbackLocation == null || childHandlesPop) {
      return scaffold;
    }
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          context.go(backFallbackLocation!);
        }
      },
      child: scaffold,
    );
  }

  Future<void> _handleBack(BuildContext context) async {
    final popped = await Navigator.of(context).maybePop();
    if (popped || !context.mounted) {
      return;
    }
    context.go(backFallbackLocation ?? AppRoutes.novel);
  }
}
