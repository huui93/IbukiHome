import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';

class MemoryDataNotice extends StatelessWidget {
  const MemoryDataNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: AppTokens.spacingS),
            Expanded(
              child: Text(
                '项目和正文已保存到本机 SQLite；卸载 App 或清除应用数据会删除。',
                key: const Key('memory-data-notice'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectFlowErrorView extends StatelessWidget {
  const ProjectFlowErrorView({
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel = '返回项目',
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('project-flow-error-view'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 36,
              ),
              const SizedBox(height: AppTokens.spacingM),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppTokens.spacingS),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(height: AppTokens.spacingM),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String formatLocalDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String segmentPreview(String content) {
  final normalized = content.trim();
  if (normalized.isEmpty) {
    return '空白段落';
  }
  return normalized;
}
