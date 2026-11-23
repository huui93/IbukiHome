import 'package:flutter/material.dart';
import '../../../app/widgets/ibuki_action_menu.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/chat/chat_controls_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../data/ai/ai_reasoning_parameters.dart';
import '../../../domain/ai/ai_reasoning_level.dart';
import '../../../app/localization/app_localizations.dart';

enum ChatTool {
  image,
  reasoning,
  summary,
  delete,
  regenerate,
  continueReply,
  usage,
}

Future<ChatTool?> showChatTools(
  BuildContext context, {
  required bool busy,
  required bool canDelete,
  required bool canGenerate,
}) => showIbukiActionMenu<ChatTool>(
  context: context,
  alignment: Alignment.bottomLeft,
  padding: const EdgeInsets.fromLTRB(16, 20, 16, 82),
  menuKey: const Key('chat-tools-menu'),
  width: 250,
  builder: (dialogContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in const [
        (ChatTool.image, Icons.image_outlined, '发送图片'),
        (ChatTool.reasoning, Icons.psychology_outlined, '推理等级'),
        (ChatTool.summary, Icons.summarize_outlined, '会话摘要'),
        (ChatTool.usage, Icons.data_usage_rounded, 'Token 用量'),
        (ChatTool.regenerate, Icons.refresh_rounded, '重新生成'),
        (ChatTool.continueReply, Icons.more_horiz_rounded, '续写上一条回答'),
        (ChatTool.delete, Icons.delete_outline_rounded, '删除上一条消息'),
      ])
        IbukiEntrance(
          order: item.$1.index,
          offset: const Offset(-10, 0),
          child: ListTile(
            key: Key('chat-tool-${item.$1.name}'),
            leading: Icon(item.$2),
            title: Text(dialogContext.tr(item.$3)),
            enabled: switch (item.$1) {
              ChatTool.summary || ChatTool.usage => true,
              ChatTool.delete => !busy && canDelete,
              ChatTool.regenerate ||
              ChatTool.continueReply => !busy && canGenerate,
              _ => !busy,
            },
            onTap: () => Navigator.pop(dialogContext, item.$1),
          ),
        ),
    ],
  ),
);

Future<void> showChatReasoning(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
) async {
  final current = await ref.read(chatReasoningLevelProvider(sessionId).future);
  var levels = <AiReasoningLevel>[AiReasoningLevel.automatic];
  String? modelLabel;
  try {
    final model = await ref
        .read(aiModelResolverProvider)
        .resolveForChatSession(sessionId);
    levels = reasoningLevels(model.providerType, model.model);
    modelLabel = model.displayLabel;
  } catch (_) {}
  if (!context.mounted) return;
  final selected = await showModalBottomSheet<AiReasoningLevel>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr("推理等级")),
              subtitle: Text(modelLabel ?? sheet.tr('先为当前会话配置 AI 模型。')),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.tr(
                  "默认沿用当前服务的兼容配置。部分模型只有开关；旧版 Claude 和 Gemini 2.5 的等级按思考预算映射。",
                ),
              ),
            ),
            if (levels.length == 1)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(context.tr("当前模型没有已适配的推理设置，使用服务默认行为。")),
              ),
            if (!levels.contains(current))
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(context.tr("已保存的等级不适用于当前模型，本次请求使用默认行为。")),
              ),
            for (final level in levels)
              ListTile(
                key: Key('chat-reasoning-${level.name}'),
                title: Text(sheet.tr(level.label)),
                trailing: current == level
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheet, level),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected == null) return;
  await ref
      .read(chatControlsRepositoryProvider)
      .setReasoning(sessionId, selected, ref.read(utcClockProvider).now());
  ref.invalidate(chatReasoningLevelProvider(sessionId));
}
