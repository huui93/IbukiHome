import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/bubble_theme.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../app/localization/app_localizations.dart';

class GlobalPageScaffold extends StatelessWidget {
  const GlobalPageScaffold({
    required this.title,
    required this.subtitle,
    required this.fallbackLocation,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final String fallbackLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          context.go(fallbackLocation);
        }
      },
      child: Scaffold(
        key: const Key('global-page-shell'),
        backgroundColor: context.bubbleTheme.backgroundStart,
        appBar: AppBar(
          leading: IconButton(
            key: const Key('global-back-button'),
            tooltip: context.tr("返回"),
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _goBack(context),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                context.tr(subtitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        body: BubbleBackground(child: child),
      ),
    );
  }

  Future<void> _goBack(BuildContext context) async {
    if (await Navigator.of(context).maybePop() || !context.mounted) {
      return;
    }
    context.go(fallbackLocation);
  }
}
