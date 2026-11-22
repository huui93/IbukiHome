import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/ai/ai_draft_update.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/segments/segment.dart';
import '../../ai/presentation/ai_ui_helpers.dart';

enum SegmentAiUiOperation { rewrite, modify, selectionModify }

Future<bool> showSegmentAiDialog(
  BuildContext context, {
  required Segment segment,
  required SegmentAiUiOperation operation,
  int? selectionStart,
  int? selectionEnd,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SegmentAiDraftDialog(
          segment: segment,
          operation: operation,
          selectionStart: selectionStart,
          selectionEnd: selectionEnd,
        ),
      ) ??
      false;
}

class SegmentAiDraftDialog extends ConsumerStatefulWidget {
  const SegmentAiDraftDialog({
    required this.segment,
    required this.operation,
    this.selectionStart,
    this.selectionEnd,
    super.key,
  });

  final Segment segment;
  final SegmentAiUiOperation operation;
  final int? selectionStart;
  final int? selectionEnd;

  @override
  ConsumerState<SegmentAiDraftDialog> createState() =>
      _SegmentAiDraftDialogState();
}

class _SegmentAiDraftDialogState extends ConsumerState<SegmentAiDraftDialog> {
  late final TextEditingController _instructionController;
  String? _requestId;
  String _draft = '';
  String? _error;
  AiUiErrorPresentation? _errorDetail;
  var _generating = false;
  var _completed = false;
  var _applying = false;
  late final void Function(String requestId) _cancelGeneration;

  @override
  void initState() {
    super.initState();
    _instructionController = TextEditingController();
    _cancelGeneration = ref.read(segmentAiDraftRunnerProvider).cancel;
  }

  @override
  void dispose() {
    final requestId = _requestId;
    if (requestId != null) {
      _cancelGeneration(requestId);
    }
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(
      projectAiLabelProvider(widget.segment.projectId),
    );
    return AlertDialog(
      key: Key('segment-ai-${widget.operation.name}-dialog'),
      title: Text(_title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                provider.value ?? '尚未配置可用 AI',
                key: const Key('segment-ai-provider-label'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.spacingS),
              if (widget.operation == SegmentAiUiOperation.selectionModify)
                Text(
                  '已选择 ${(_selectionEnd - _selectionStart).clamp(0, widget.segment.content.length)} 个字符',
                  key: const Key('segment-ai-selection-summary'),
                ),
              TextField(
                key: const Key('segment-ai-instruction-field'),
                controller: _instructionController,
                enabled: !_generating && !_applying,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _instructionLabel,
                  hintText: _instructionHint,
                ),
              ),
              if (_draft.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spacingM),
                Text(
                  _generating ? '伊吹正在写……' : 'AI 草稿预览',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppTokens.spacingS),
                Container(
                  key: const Key('segment-ai-draft'),
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(AppTokens.spacingM),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  ),
                  child: SingleChildScrollView(child: SelectableText(_draft)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppTokens.spacingS),
                Text(
                  _error!,
                  key: const Key('segment-ai-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (_errorDetail != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('segment-ai-error-detail-button'),
                      onPressed: () =>
                          showAiErrorDetails(context, _errorDetail!),
                      child: const Text('查看详情'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying
              ? null
              : () {
                  if (_generating) {
                    _stop();
                  }
                  Navigator.pop(context, false);
                },
          child: const Text('取消'),
        ),
        if (_generating)
          FilledButton.icon(
            key: const Key('segment-ai-stop-button'),
            onPressed: _stop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('停止'),
          )
        else if (_completed)
          FilledButton.icon(
            key: const Key('segment-ai-apply-button'),
            onPressed: _applying ? null : _apply,
            icon: _applying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_applying ? '保存中' : '确认替换'),
          )
        else
          FilledButton.icon(
            key: const Key('segment-ai-generate-button'),
            onPressed: _start,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('开始生成'),
          ),
        if (provider.value == null)
          TextButton(
            key: const Key('segment-ai-open-settings'),
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.pop(context, false);
              router.push(AppRoutes.aiSettings);
            },
            child: const Text('去设置'),
          ),
      ],
    );
  }

  String get _title => switch (widget.operation) {
    SegmentAiUiOperation.rewrite => 'AI 重写这一段',
    SegmentAiUiOperation.modify => '按要求修改这一段',
    SegmentAiUiOperation.selectionModify => 'AI 修改选中文字',
  };

  String get _instructionLabel => switch (widget.operation) {
    SegmentAiUiOperation.rewrite => '重写要求（可选）',
    SegmentAiUiOperation.modify => '修改要求',
    SegmentAiUiOperation.selectionModify => '选区修改要求（可选）',
  };

  String get _instructionHint => switch (widget.operation) {
    SegmentAiUiOperation.rewrite => '例如：让节奏更紧凑，保留当前情节',
    SegmentAiUiOperation.modify => '例如：增加环境描写，减少对白',
    SegmentAiUiOperation.selectionModify => '例如：把语气改得更压抑',
  };

  int get _selectionStart => widget.selectionStart ?? -1;
  int get _selectionEnd => widget.selectionEnd ?? -1;

  Future<void> _start() async {
    if (_generating) {
      return;
    }
    final instruction = _instructionController.text.trim();
    if (widget.operation == SegmentAiUiOperation.modify &&
        instruction.isEmpty) {
      setState(() => _error = '请先填写修改要求。');
      return;
    }
    final requestId = ref.read(entityIdGeneratorProvider).nextId('ai_request');
    setState(() {
      _requestId = requestId;
      _draft = '';
      _error = null;
      _errorDetail = null;
      _completed = false;
      _generating = true;
    });
    try {
      final stream = switch (widget.operation) {
        SegmentAiUiOperation.rewrite => ref.read(rewriteSegmentProvider)(
          projectId: widget.segment.projectId,
          segmentId: widget.segment.id,
          instruction: instruction,
          selectedCharacterIds: const {},
          selectedWorldCardIds: const {},
          requestId: requestId,
        ),
        SegmentAiUiOperation.modify =>
          ref.read(modifySegmentWithInstructionProvider)(
            projectId: widget.segment.projectId,
            segmentId: widget.segment.id,
            instruction: instruction,
            selectedCharacterIds: const {},
            selectedWorldCardIds: const {},
            requestId: requestId,
          ),
        SegmentAiUiOperation.selectionModify =>
          ref.read(selectionModifySegmentProvider)(
            projectId: widget.segment.projectId,
            segmentId: widget.segment.id,
            selectionStart: _selectionStart,
            selectionEnd: _selectionEnd,
            instruction: instruction,
            selectedCharacterIds: const {},
            selectedWorldCardIds: const {},
            requestId: requestId,
          ),
      };
      await for (final update in stream) {
        if (!mounted || update.requestId != _requestId) {
          continue;
        }
        setState(() {
          _draft = update.draft;
          _generating = update.status == AiDraftStatus.streaming;
          _completed = update.status == AiDraftStatus.completed;
          if (update.status == AiDraftStatus.cancelled) {
            _error = '生成已停止，草稿不会写入正文。';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        final detail = describeAiError(
          error,
          stage: 'segment-draft',
          requestId: requestId,
        );
        setState(() {
          _generating = false;
          _completed = false;
          _error = detail.summary;
          _errorDetail = detail;
        });
      }
    }
  }

  void _stop() {
    final requestId = _requestId;
    if (requestId != null) {
      _cancelGeneration(requestId);
    }
  }

  Future<void> _apply() async {
    if (_draft.trim().isEmpty || _applying) {
      return;
    }
    setState(() => _applying = true);
    try {
      final now = ref.read(utcClockProvider).now();
      final revisionId = ref
          .read(entityIdGeneratorProvider)
          .nextId('segment_revision');
      switch (widget.operation) {
        case SegmentAiUiOperation.rewrite:
          await ref
              .read(rewriteSegmentProvider)
              .apply(
                segmentId: widget.segment.id,
                originalContent: widget.segment.content,
                draft: _draft,
                instruction: _instructionController.text,
                nowUtc: now,
                revisionId: revisionId,
                requestId: _requestId,
              );
        case SegmentAiUiOperation.modify:
          await ref
              .read(modifySegmentWithInstructionProvider)
              .apply(
                segmentId: widget.segment.id,
                originalContent: widget.segment.content,
                draft: _draft,
                instruction: _instructionController.text,
                nowUtc: now,
                revisionId: revisionId,
                requestId: _requestId,
              );
        case SegmentAiUiOperation.selectionModify:
          await ref
              .read(selectionModifySegmentProvider)
              .apply(
                segmentId: widget.segment.id,
                originalContent: widget.segment.content,
                selectionStart: _selectionStart,
                selectionEnd: _selectionEnd,
                replacementDraft: _draft,
                instruction: _instructionController.text,
                nowUtc: now,
                revisionId: revisionId,
                requestId: _requestId,
              );
      }
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        final detail = describeAiError(error, stage: 'revision-save');
        setState(() {
          _applying = false;
          _error = detail.summary;
          _errorDetail = detail;
        });
      }
    }
  }
}
