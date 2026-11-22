import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/ai/ai_runtime_providers.dart';
import '../../../application/plugins/novel_plugin_providers.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/plugins/novel_plugin_models.dart';
import '../../../domain/segments/segment.dart';

Future<void> showNovelBranches(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  try {
    final repository = ref.read(novelPluginRepositoryProvider);
    final current = await repository.branch(projectId);
    final branches = await repository.branches(current.storyId);
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('故事线')),
          for (final branch in branches)
            ListTile(
              key: Key('novel-branch-${branch.projectId}'),
              leading: Icon(
                branch.projectId == projectId
                    ? Icons.radio_button_checked
                    : Icons.alt_route,
              ),
              title: Text(branch.label),
              subtitle: branch.ended ? const Text('已结束') : null,
              onTap: () => Navigator.pop(sheet, branch.projectId),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('从当前末尾另开故事线'),
            onTap: () => Navigator.pop(sheet, ''),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted || choice == projectId) return;
    if (choice.isEmpty) {
      await _fork(context, ref, projectId);
    } else {
      await repository.selectBranch(current.storyId, choice);
      if (context.mounted) _open(context, ref, projectId, choice);
    }
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

Future<void> showNovelCandidates(
  BuildContext context,
  WidgetRef ref,
  Segment segment,
) async {
  try {
    final id = segment.projectId;
    final repository = ref.read(novelPluginRepositoryProvider);
    final branch = await repository.branch(id);
    final history = await repository.history(id);
    final message = history.where((m) => m.segmentId == segment.id).firstOrNull;
    if (message == null || !context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('段落候选')),
          for (final candidate in message.candidates)
            ListTile(
              leading: Icon(
                candidate['selected'] == true
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text('版本 ${candidate['revision']}'),
              subtitle: Text(
                candidate['content'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              enabled: !branch.ended,
              onTap: () => Navigator.pop(sheet, candidate['id'] as String),
            ),
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: const Text('从这个段落分叉'),
            subtitle: const Text('保留当前选中的版本'),
            onTap: () => Navigator.pop(sheet, ''),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null || choice == message.candidateId) {
      return;
    }
    if (choice.isEmpty) {
      await _fork(context, ref, id, at: message);
      return;
    }
    final selected = await repository.selectCandidate(
      projectId: id,
      messageId: message.id,
      candidateId: choice,
      now: ref.read(utcClockProvider).now(),
    );
    if (!context.mounted) return;
    invalidateNovelBranchCaches(ref);
    await ref
        .read(novelMemoryInvalidatorProvider)
        .invalidateFromOrder(
          projectId: id,
          fromOrder: selected.orderIndex,
          nowUtc: selected.updatedAt,
        );
    if (context.mounted) {
      ref.read(novelPluginHostProvider).finalized(selected, 'select-candidate');
    }
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

Future<void> _fork(
  BuildContext context,
  WidgetRef ref,
  String projectId, {
  NovelHistoryMessage? at,
}) async {
  var name = '';
  final label = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('新故事线'),
      content: TextField(
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: '故事线名称'),
        onChanged: (value) => name = value.trim(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, name),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  if (label == null || !context.mounted) return;
  if (label.isEmpty) throw const FormatException('请填写故事线名称。');
  final repository = ref.read(novelPluginRepositoryProvider);
  final branch = await repository.fork(
    projectId: projectId,
    newProjectId: ref.read(entityIdGeneratorProvider).nextId('novel_branch'),
    label: label,
    atMessageId: at?.id,
    expectedCandidateId: at?.candidateId,
    now: ref.read(utcClockProvider).now(),
  );
  if (!context.mounted) return;
  ref
      .read(novelPluginHostProvider)
      .publish(projectId, 'fork', segmentId: at?.segmentId);
  invalidateNovelBranchCaches(ref);
  _open(context, ref, projectId, branch.projectId);
}

void _open(BuildContext context, WidgetRef ref, String previous, String id) {
  ref.read(autoStoryRunnerProvider).stop(projectId: previous);
  ref.read(aiRequestCoordinatorProvider).cancelScope(previous);
  ref.read(currentProjectControllerProvider.notifier).selectProject(id);
  context.go(AppRoutes.novelEditor(id));
}

void _showError(BuildContext context, Object error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(error.toString())));
