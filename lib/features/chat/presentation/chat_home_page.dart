import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/chat/chat_session.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import 'simple_chat_pages.dart';

class ChatHomePage extends StatelessWidget {
  const ChatHomePage({super.key});
  @override
  Widget build(BuildContext context) => const SimpleChatHomePage();
}

class DeletedChatSessionsPage extends ConsumerWidget {
  const DeletedChatSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(deletedChatSessionListProvider);
    return SafeArea(
      top: false,
      child: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ChatRecoveryErrorView(
          title: '已删除会话读取失败',
          message: _friendlyError(error),
          actionLabel: '返回聊天',
          onAction: () => context.go(AppRoutes.chat),
        ),
        data: (items) => ListView(
          key: const Key('deleted-chat-sessions-page'),
          padding: const EdgeInsets.all(AppTokens.spacingM),
          children: [
            Text(
              '已删除会话',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTokens.spacingS),
            const Text('这里只提供恢复，不进行永久删除。'),
            const SizedBox(height: AppTokens.spacingM),
            if (items.isEmpty)
              const _EmptyDeletedChatSessionsState()
            else
              for (final session in items)
                _DeletedChatSessionTile(session: session),
          ],
        ),
      ),
    );
  }
}

class _DeletedChatSessionTile extends ConsumerWidget {
  const _DeletedChatSessionTile({required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatMessageListProvider(session.id));
    final count = messages.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    final deletedAt = session.deletedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
      child: ListTile(
        key: Key('deleted-chat-session-${session.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        title: Text(session.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('聊天会话'),
            Text('消息 $count'),
            if (deletedAt != null)
              Text('删除 ${'${deletedAt.toLocal()}'.split('.').first}'),
          ],
        ),
        trailing: FilledButton.tonal(
          key: Key('restore-chat-session-${session.id}'),
          onPressed: () => _restoreSession(context, ref, session.id),
          child: const Text('恢复'),
        ),
      ),
    );
  }

  Future<void> _restoreSession(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(restoreChatSessionProvider)(
        sessionId: sessionId,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.chatSessions],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.chat);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }
}

class _EmptyDeletedChatSessionsState extends StatelessWidget {
  const _EmptyDeletedChatSessionsState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppTokens.spacingL),
      child: Center(
        key: Key('empty-deleted-chat-sessions-state'),
        child: Text('没有已删除会话。'),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('not found') || text.contains('not be found')) {
    return '目标不存在，请返回后重新选择。';
  }
  if (text.contains('already exists')) {
    return '保存冲突，请重新尝试。';
  }
  if (text.contains('不能为空') || text.contains('empty')) {
    return '请填写必要内容。';
  }
  if (text.contains('deleted')) {
    return '目标已经删除，无法继续操作。';
  }
  return '操作失败，请稍后重试。';
}

class _ChatRecoveryErrorView extends StatelessWidget {
  const _ChatRecoveryErrorView({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final String title, message, actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        Text(message),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}
