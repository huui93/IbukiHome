import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/widgets/bubble_background.dart';
import '../../../application/providers/repository_providers.dart';
import '../../chat/presentation/chat_memory_widgets.dart';
import '../../../app/localization/app_localizations.dart';

class ChatMemorySettingsPage extends ConsumerWidget {
  const ChatMemorySettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => BubbleBackground(
    child: Scaffold(
      key: const Key('chat-memory-settings-page'),
      appBar: AppBar(
        title: Text(context.tr("聊天记忆")),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.settings);
            }
          },
        ),
      ),
      body: ref
          .watch(chatSessionListProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(chatSessionListProvider),
              child: Text(context.tr("读取失败，点击重试")),
            ),
            data: (sessions) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(context.tr("每个会话独立保存上下文、长期记忆和摘要。同一人格的其他会话、小说均不会读取这里的内容。")),
                const SizedBox(height: 12),
                if (sessions.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(context.tr("创建聊天会话后，可在这里管理记忆。")),
                  ),
                for (final session in sessions.where(
                  (s) => s.personaId != null,
                ))
                  ExpansionTile(
                    key: Key('memory-settings-${session.id}'),
                    title: Text(session.title),
                    children: [
                      ChatMemoryControls(sessionId: session.id),
                      ListTile(
                        leading: const Icon(Icons.manage_search),
                        title: Text(context.tr("管理记忆、摘要和历史检索")),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          AppRoutes.chatSessionMemory(session.id),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
    ),
  );
}
