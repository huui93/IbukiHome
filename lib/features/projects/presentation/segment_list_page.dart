import '../../../application/plugins/novel_plugin_providers.dart';
import '../../../domain/plugins/novel_plugin_models.dart';
import 'novel_branch_sheet.dart';
import 'novel_plugin_page.dart';
import 'novel_reply_content.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/theme/bubble_theme.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../app/widgets/follow_bottom_controller.dart';
import '../../../application/ai/ai_draft_update.dart';
import '../../../application/ai/auto_story_runner.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/projects/novel_direction_drafts.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/projects/project.dart';
import '../../../domain/segments/segment.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import '../../ai/presentation/ai_ui_helpers.dart';
import '../../ai/presentation/ai_model_binding_sheet.dart';
import 'project_flow_widgets.dart';
import 'segment_ai_dialog.dart';
import 'segment_management_pages.dart';
import '../../../app/theme/ibuki_motion.dart';

class SegmentListPage extends ConsumerStatefulWidget {
  const SegmentListPage({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<SegmentListPage> createState() => _SegmentListPageState();
}

class _SegmentListPageState extends ConsumerState<SegmentListPage>
    with WidgetsBindingObserver {
  late final TextEditingController _composerController;
  late final FocusNode _composerFocusNode;
  late FollowBottomController _followBottom;
  late final AutoStoryRunner _autoStoryRunner;
  StreamSubscription<AutoStoryRunUpdate>? _autoStorySubscription;
  final Set<String> _selectedCharacterIds = {};
  final Set<String> _selectedWorldCardIds = {};
  String? _activeRequestId;
  String _aiDraft = '';
  String? _aiError;
  AiUiErrorPresentation? _aiErrorDetail;
  var _generating = false;
  var _retryingConnection = false;
  var _generationStopped = false;
  var _pluginNoticeShown = false;
  var _autoStoryEnabled = false;
  var _extrasExpanded = false;
  var _autoStoryRunning = false;
  var _autoStoryGeneratedCount = 0;
  int? _lastSegmentCount;
  late final void Function(String requestId) _cancelGeneration;

  ScrollController get _scrollController => _followBottom.scrollController;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController(
      text: ref.read(novelDirectionDraftsProvider)[widget.projectId] ?? '',
    )..addListener(_handleComposerChanged);
    _composerFocusNode = FocusNode();
    _followBottom = _createFollowBottom(widget.projectId);
    _autoStoryRunner = ref.read(autoStoryRunnerProvider);
    _autoStorySubscription = _autoStoryRunner.updates.listen(
      _handleAutoStoryUpdate,
    );
    _cancelGeneration = ref.read(generateNextSegmentProvider).cancel;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoStoryRunner.stop(
      projectId: widget.projectId,
      reason: AutoStoryStopReason.pageDisposed,
    );
    unawaited(_autoStorySubscription?.cancel());
    final requestId = _activeRequestId;
    if (requestId != null && !_autoStoryRunning) {
      _cancelGeneration(requestId);
    }
    _composerController.dispose();
    _composerFocusNode.dispose();
    _followBottom.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SegmentListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _autoStoryRunner.stop(
        projectId: oldWidget.projectId,
        reason: AutoStoryStopReason.projectChanged,
      );
      final requestId = _activeRequestId;
      if (requestId != null && !_autoStoryRunning) {
        _cancelGeneration(requestId);
      }
      _followBottom.dispose();
      _followBottom = _createFollowBottom(widget.projectId);
      _activeRequestId = null;
      _aiDraft = '';
      _aiError = null;
      _generating = false;
      _retryingConnection = false;
      _pluginNoticeShown = false;
      _generationStopped = false;
      _autoStoryEnabled = false;
      _extrasExpanded = false;
      _autoStoryRunning = false;
      _autoStoryGeneratedCount = 0;
      _lastSegmentCount = null;
      _composerController.text =
          ref.read(novelDirectionDraftsProvider)[widget.projectId] ?? '';
      _selectedCharacterIds.clear();
      _selectedWorldCardIds.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_autoStoryRunning) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _autoStoryRunner.stop(
        projectId: widget.projectId,
        reason: AutoStoryStopReason.background,
      );
    }
  }

  FollowBottomController _createFollowBottom(String projectId) {
    final controller = FollowBottomController(
      storageId: 'novel-project-$projectId',
      initiallyFollowBottom: false,
    );
    return controller;
  }

  void _observeSegmentList(List<Segment> items) {
    final previousCount = _lastSegmentCount;
    _lastSegmentCount = items.length;
    if (previousCount == null) {
      _followBottom.restoreAfterFirstLayout();
    } else if (items.length > previousCount) {
      _followBottom.onContentAppended();
    }
  }

  void _handleAutoStoryUpdate(AutoStoryRunUpdate update) {
    if (!mounted || update.projectId != widget.projectId) return;
    if (!_pluginNoticeShown && update.pluginNotice != null) {
      _pluginNoticeShown = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(update.pluginNotice!)));
    }
    switch (update.status) {
      case AutoStoryRunStatus.running:
        setState(() {
          _autoStoryRunning = true;
          _autoStoryGeneratedCount = update.generatedCount;
          _generating = false;
          _aiError = null;
          _aiErrorDetail = null;
          _generationStopped = false;
        });
      case AutoStoryRunStatus.streaming:
      case AutoStoryRunStatus.retrying:
        setState(() {
          _autoStoryRunning = true;
          _activeRequestId = update.requestId;
          _aiDraft = update.draft;
          _generating = true;
          _retryingConnection = update.status == AutoStoryRunStatus.retrying;
          _aiError = null;
          _aiErrorDetail = null;
        });
        _followBottom.onContentAppended();
      case AutoStoryRunStatus.segmentCompleted:
        if (update.generatedCount == 1) _composerController.clear();
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.segments],
        );
        ref
            .read(mascotControllerProvider.notifier)
            .perform(MascotAction.celebrate);
        setState(() {
          _autoStoryRunning = true;
          _autoStoryGeneratedCount = update.generatedCount;
          _activeRequestId = null;
          _aiDraft = '';
          _generating = false;
          _retryingConnection = false;
          _aiError = null;
          _aiErrorDetail = null;
        });
        _followBottom.onContentAppended();
      case AutoStoryRunStatus.stopped:
        setState(() {
          _autoStoryRunning = false;
          _autoStoryGeneratedCount = update.generatedCount;
          _activeRequestId = null;
          _generating = false;
          _retryingConnection = false;
          _generationStopped = _aiDraft.trim().isNotEmpty;
          _aiError = _generationStopped ? '生成已停止。草稿尚未保存。' : null;
        });
        ref
            .read(mascotControllerProvider.notifier)
            .perform(MascotAction.settle);
      case AutoStoryRunStatus.paused:
        final error = update.error;
        final detail = error == null
            ? null
            : describeAiError(
                error,
                stage: 'auto-story',
                requestId: update.requestId,
              );
        setState(() {
          _autoStoryRunning = false;
          _autoStoryGeneratedCount = update.generatedCount;
          _activeRequestId = null;
          _generating = false;
          _retryingConnection = false;
          _generationStopped = _aiDraft.trim().isNotEmpty;
          _aiErrorDetail = detail;
          _aiError = detail == null ? '自动剧情已暂停。' : '自动剧情已暂停：${detail.summary}';
        });
        ref
            .read(mascotControllerProvider.notifier)
            .perform(MascotAction.settle);
    }
  }

  void _setAutoStoryEnabled(bool enabled) {
    if (_autoStoryRunning && !enabled) {
      _autoStoryRunner.stop(projectId: widget.projectId);
    }
    setState(() => _autoStoryEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final segments = ref.watch(segmentListProvider(widget.projectId));
    final aiLabel = ref.watch(projectAiLabelProvider(widget.projectId)).value;

    return SafeArea(
      top: false,
      bottom: false,
      child: project.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: '项目不存在',
          message: '没有找到这个项目，请返回项目列表重新选择。',
          onAction: () => context.go(AppRoutes.projects),
        ),
        data: (project) {
          _selectCurrentProjectAfterBuild(project.id);
          return segments.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ProjectFlowErrorView(
              title: '正文读取失败',
              message: '正文段落暂时无法读取，请稍后重试。',
              onAction: () => context.go(AppRoutes.projects),
            ),
            data: (items) => _buildWorkbench(context, project, items, aiLabel),
          );
        },
      ),
    );
  }

  Widget _buildWorkbench(
    BuildContext context,
    Project project,
    List<Segment> items,
    String? aiLabel,
  ) {
    _observeSegmentList(items);
    final hasPlugin =
        ref.watch(novelBoundPluginProvider(project.id)).value != null;
    final branch = ref.watch(novelStoryBranchProvider(project.id)).value;
    final ended = branch?.ended == true;
    return Column(
      key: const Key('segment-list-page'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: _NovelContextToolbar(
            selectedCharacterCount: _selectedCharacterIds.length,
            selectedWorldCount: _selectedWorldCardIds.length,
            onOpenCharacters: _showCharacterContext,
            onOpenWorld: _showWorldContext,
            providerLabel: aiLabel,
            onOpenAiSettings: _generating || _autoStoryRunning
                ? () => _showMessage('请先停止当前生成。')
                : () => showAiModelBindingSheet(
                    context: context,
                    ref: ref,
                    scope: AiModelBindingScope.project,
                    entityId: widget.projectId,
                  ),
          ),
        ),

        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _followBottom.handleScrollNotification,
                  child: KeyedSubtree(
                    key: const Key('continuous-manuscript-list'),
                    child: CustomScrollView(
                      key: PageStorageKey<String>(
                        'continuous-manuscript-list-${widget.projectId}',
                      ),
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTokens.spacingM,
                            AppTokens.spacingM,
                            AppTokens.spacingM,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _ManuscriptHeader(
                              projectId: project.id,
                              segmentCount: items.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppTokens.spacingM),
                        ),
                        if (items.isEmpty)
                          const SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppTokens.spacingM,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: IbukiGlassSurface(
                                key: Key('novel-reading-glass-surface'),
                                strong: true,
                                child: _EmptySegmentsState(),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.spacingM,
                            ),
                            sliver: DecoratedSliver(
                              key: const Key('novel-reading-glass-surface'),
                              decoration: BoxDecoration(
                                color: context.bubbleTheme.glassStrong,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.bubbleRadius,
                                ),
                                border: Border.all(
                                  color: context.bubbleTheme.glassBorder,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.bubbleTheme.shadow,
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              sliver: SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.spacingM,
                                  vertical: AppTokens.spacingS,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: items.length,
                                  itemBuilder: (context, index) => KeyedSubtree(
                                    key: ValueKey(items[index].id),
                                    child: _ContinuousSegment(
                                      segment: items[index],
                                      index: index,
                                      allSegments: items,
                                      pluginEnabled: hasPlugin,
                                      storyEnded: ended,
                                      onFillDraft: ended
                                          ? null
                                          : _fillPluginDraft,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_aiDraft.isNotEmpty ||
                            _generating ||
                            _aiError != null)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.spacingM,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: _AiDraftSegment(
                                draft: _aiDraft,
                                generating: _generating,
                                retryingConnection: _retryingConnection,
                                stopped: _generationStopped,
                                error: _aiError,
                                onShowErrorDetail: _aiErrorDetail == null
                                    ? null
                                    : () => showAiErrorDetails(
                                        context,
                                        _aiErrorDetail!,
                                      ),
                                onKeep: _aiDraft.trim().isEmpty
                                    ? null
                                    : _keepStoppedDraft,
                                onDiscard: _discardDraft,
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppTokens.spacingL),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: AnimatedBuilder(
                  animation: _followBottom,
                  builder: (context, _) => _followBottom.showJumpToBottom
                      ? JumpToBottomButton(
                          buttonKey: const Key('novel-scroll-to-bottom'),
                          onPressed: _followBottom.scrollToBottom,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
        if (ended)
          ListTile(
            key: const Key('novel-branch-ended'),
            leading: const Icon(Icons.lock_outline),
            title: const Text('这条故事线已结束'),
            subtitle: branch?.endedReason == null
                ? null
                : Text(branch!.endedReason!),
            trailing: TextButton(
              onPressed: () => showNovelBranches(context, ref, project.id),
              child: const Text('故事线'),
            ),
          )
        else
          _NovelDirectionComposer(
            controller: _composerController,
            focusNode: _composerFocusNode,
            extrasExpanded: _extrasExpanded,
            onExtrasToggle: () {
              _composerFocusNode.unfocus();
              setState(() => _extrasExpanded = !_extrasExpanded);
            },
            onManualAdd: _openManualSegment,
            onPluginMode: hasPlugin ? _choosePluginMode : null,
            hasManuscript: items.isNotEmpty,
            onGenerate: _generateNext,
            onStop: _stopGeneration,
            generating: _generating,
            autoStoryEnabled: _autoStoryEnabled,
            autoStoryRunning: _autoStoryRunning,
            autoStoryGeneratedCount: _autoStoryGeneratedCount,
            onAutoStoryChanged: _setAutoStoryEnabled,
          ),
      ],
    );
  }

  void _selectCurrentProjectAfterBuild(String projectId) {
    if (ref.read(currentProjectControllerProvider) == projectId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(currentProjectControllerProvider.notifier)
          .selectProject(projectId);
    });
  }

  void _handleComposerChanged() {
    if (!mounted) {
      return;
    }
    ref
        .read(novelDirectionDraftsProvider.notifier)
        .save(widget.projectId, _composerController.text);
    if (_composerController.text.isNotEmpty) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    }
  }

  Future<void> _openManualSegment() async {
    setState(() => _extrasExpanded = false);
    final inCreation = GoRouterState.of(context).uri.path.startsWith('/novel/');
    await context.push(
      '${AppRoutes.newSegment(widget.projectId)}${inCreation ? '?return=creation' : ''}',
    );
    if (!mounted) return;
  }

  void _fillPluginDraft(String text) {
    if (_generating || _autoStoryRunning) return;
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _handleComposerChanged();
    _composerFocusNode.requestFocus();
  }

  Future<void> _choosePluginMode(NovelGenerationMode mode) async {
    if (_generating || _autoStoryRunning) return;
    String? speakerId;
    if (mode == NovelGenerationMode.group) {
      final cards = await ref.read(
        characterListProvider(widget.projectId).future,
      );
      if (!mounted) return;
      final available = cards.where(
        (c) =>
            _selectedCharacterIds.isEmpty ||
            _selectedCharacterIds.contains(c.id),
      );
      if (available.isEmpty) {
        _showMessage('先为作品添加角色卡。');
        return;
      }
      speakerId = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('选择本轮发言角色'),
          children: [
            for (final card in available)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, card.id),
                child: Text(card.name),
              ),
          ],
        ),
      );
      if (!mounted || speakerId == null) return;
    }
    await _generateSingleNext(mode: mode, speakerId: speakerId);
  }

  Future<void> _generateNext() async {
    if (_autoStoryEnabled) {
      _startAutoStory();
      return;
    }
    await _generateSingleNext();
  }

  void _startAutoStory() {
    if (_generating || _autoStoryRunning || _autoStoryRunner.isRunning) return;
    setState(() {
      _autoStoryRunning = true;
      _autoStoryGeneratedCount = 0;
      _aiDraft = '';
      _aiError = null;
      _aiErrorDetail = null;
      _generationStopped = false;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    unawaited(
      _autoStoryRunner.start(
        projectId: widget.projectId,
        initialInstruction: _composerController.text,
        selectedCharacterIds: Set.unmodifiable(_selectedCharacterIds),
        selectedWorldCardIds: Set.unmodifiable(_selectedWorldCardIds),
      ),
    );
  }

  Future<void> _generateSingleNext({
    NovelGenerationMode mode = NovelGenerationMode.normal,
    String? speakerId,
  }) async {
    if (_generating) {
      return;
    }
    final requestId = ref.read(entityIdGeneratorProvider).nextId('ai_request');
    final segmentId = ref.read(entityIdGeneratorProvider).nextId('segment');
    setState(() {
      _activeRequestId = requestId;
      _aiDraft = '';
      _aiError = null;
      _aiErrorDetail = null;
      _generationStopped = false;
      _generating = true;
      _retryingConnection = false;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final stream = ref.read(generateNextSegmentProvider)(
        projectId: widget.projectId,
        userInstruction: mode == NovelGenerationMode.empty
            ? ''
            : _composerController.text,
        mode: mode,
        speakerId: speakerId,
        selectedCharacterIds: Set.unmodifiable(_selectedCharacterIds),
        selectedWorldCardIds: Set.unmodifiable(_selectedWorldCardIds),
        requestId: requestId,
        segmentId: segmentId,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      await for (final update in stream) {
        if (!mounted || update.requestId != _activeRequestId) {
          continue;
        }
        if (!_pluginNoticeShown && update.pluginNotice != null) {
          _pluginNoticeShown = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(update.pluginNotice!)));
        }
        setState(() {
          _aiDraft = update.draft;
          _generating =
              update.status == AiDraftStatus.streaming ||
              update.status == AiDraftStatus.retrying;
          _retryingConnection = update.status == AiDraftStatus.retrying;
          _generationStopped = update.status == AiDraftStatus.cancelled;
          if (_generationStopped) {
            _aiError = '生成已停止。草稿尚未保存。';
          }
        });
        _followBottom.onContentAppended();
        if (update.status == AiDraftStatus.completed) {
          if (mode == NovelGenerationMode.impersonate) {
            _fillPluginDraft(update.draft);
          } else {
            _composerController.clear();
            notifyRepositoryChanged(
              ref,
              areas: const [RepositoryDataArea.segments],
            );
          }
          if (update.storyEnded) {
            ref.invalidate(novelStoryBranchProvider(widget.projectId));
          }
          ref
              .read(mascotControllerProvider.notifier)
              .perform(MascotAction.celebrate);
          setState(() {
            _aiDraft = '';
            _aiError = null;
            _activeRequestId = null;
            _retryingConnection = false;
          });
          _followBottom.onContentAppended();
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final detail = describeAiError(
        error,
        stage: 'generate-next-segment',
        requestId: requestId,
      );
      final message = detail.summary;
      setState(() {
        _aiError = message;
        _aiErrorDetail = detail;
        _generating = false;
        _retryingConnection = false;
      });
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: '详情',
            onPressed: () => showAiErrorDetails(context, detail),
          ),
        ),
      );
    } finally {
      if (mounted && _activeRequestId == requestId) {
        setState(() => _generating = false);
      }
    }
  }

  void _stopGeneration() {
    if (_autoStoryRunning) {
      _autoStoryRunner.stop(projectId: widget.projectId);
      return;
    }
    final requestId = _activeRequestId;
    if (requestId != null) {
      _cancelGeneration(requestId);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _keepStoppedDraft() async {
    if (_aiDraft.trim().isEmpty) {
      return;
    }
    try {
      await ref.read(createSegmentProvider)(
        projectId: widget.projectId,
        content: _aiDraft,
        id: ref.read(entityIdGeneratorProvider).nextId('segment'),
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      _discardDraft();
      _followBottom.onContentAppended();
    } catch (error) {
      if (mounted) {
        final detail = describeAiError(error, stage: 'segment-save');
        setState(() {
          _aiError = detail.summary;
          _aiErrorDetail = detail;
        });
      }
    }
  }

  void _discardDraft() {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeRequestId = null;
      _aiDraft = '';
      _aiError = null;
      _aiErrorDetail = null;
      _generationStopped = false;
      _generating = false;
      _retryingConnection = false;
    });
  }

  Future<void> _showCharacterContext() async {
    try {
      final characters = await ref.read(
        characterListProvider(widget.projectId).future,
      );
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        useRootNavigator: true,
        context: context,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Column(
              key: const Key('novel-character-context-sheet'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('本次重点参考角色'),
                  subtitle: Text('仅保存当前页面的选择，尚未发送给 AI。'),
                ),
                if (characters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppTokens.spacingL),
                    child: Text('这个作品还没有角色卡。'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final character in characters)
                          CheckboxListTile(
                            key: Key('novel-character-${character.id}'),
                            value: _selectedCharacterIds.contains(character.id),
                            title: Text(character.name),
                            subtitle: character.content.trim().isEmpty
                                ? null
                                : Text(
                                    character.content.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            secondary: IconButton(
                              tooltip: '查看角色卡',
                              onPressed: () => context.push(
                                AppRoutes.character(
                                  character.projectId,
                                  character.id,
                                ),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                            onChanged: (selected) {
                              setState(() {
                                if (selected ?? false) {
                                  _selectedCharacterIds.add(character.id);
                                } else {
                                  _selectedCharacterIds.remove(character.id);
                                }
                              });
                              setSheetState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showSegmentSnack(context, '角色卡暂时无法读取。');
      }
    }
  }

  Future<void> _showWorldContext() async {
    try {
      final cards = await ref.read(
        worldCardListProvider(widget.projectId).future,
      );
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        useRootNavigator: true,
        context: context,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Column(
              key: const Key('novel-world-context-sheet'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('本次参考设定'),
                  subtitle: Text('仅保存当前页面的选择，尚未发送给 AI。'),
                ),
                if (cards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppTokens.spacingL),
                    child: Text('这个作品还没有世界观卡。'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final card in cards)
                          CheckboxListTile(
                            key: Key('novel-world-${card.id}'),
                            value: _selectedWorldCardIds.contains(card.id),
                            title: Text(card.title),
                            subtitle: card.content.trim().isEmpty
                                ? null
                                : Text(
                                    card.content.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            secondary: IconButton(
                              tooltip: '查看世界观',
                              onPressed: () => context.push(
                                AppRoutes.worldCard(card.projectId, card.id),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                            onChanged: (selected) {
                              setState(() {
                                if (selected ?? false) {
                                  _selectedWorldCardIds.add(card.id);
                                } else {
                                  _selectedWorldCardIds.remove(card.id);
                                }
                              });
                              setSheetState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showSegmentSnack(context, '世界观暂时无法读取。');
      }
    }
  }
}

class _ManuscriptHeader extends StatelessWidget {
  const _ManuscriptHeader({
    required this.projectId,
    required this.segmentCount,
  });

  final String projectId;
  final int segmentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '正文 · $segmentCount 段',
                key: const Key('segment-count-label'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const Key('deleted-segments-button'),
              tooltip: '已删除正文',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () =>
                  context.push(AppRoutes.deletedSegments(projectId)),
            ),
          ],
        ),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
      ],
    );
  }
}

class _EmptySegmentsState extends StatelessWidget {
  const _EmptySegmentsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('empty-segments-state'),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingXl),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.spacingM),
          Text('还没有正文', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spacingS),
          Text(
            '在下方写下创作方向，或从「额外创作」手动添加正文。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinuousSegment extends ConsumerWidget {
  const _ContinuousSegment({
    required this.segment,
    required this.index,
    required this.allSegments,
    required this.pluginEnabled,
    required this.storyEnded,
    this.onFillDraft,
  });

  final Segment segment;
  final int index;
  final List<Segment> allSegments;
  final bool pluginEnabled;
  final bool storyEnded;
  final ValueChanged<String>? onFillDraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyCount = ref
        .watch(segmentRevisionCountProvider(segment.id))
        .maybeWhen(data: (count) => count, orElse: () => 0);
    final theme = Theme.of(context);
    final body = segment.content.isEmpty ? '空白段落' : segment.content;

    return Column(
      key: Key('continuous-segment-${segment.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('segment-tile-${segment.id}'),
            onTap: () =>
                context.push(AppRoutes.segment(segment.projectId, segment.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spacingXs,
                vertical: AppTokens.spacingM,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '第 ${index + 1} 段',
                          key: Key('segment-number-${segment.id}'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PopupMenuButton<_SegmentMenuAction>(
                        useRootNavigator: true,
                        key: Key('segment-menu-${segment.id}'),
                        tooltip: '段落更多操作',
                        onSelected: (action) =>
                            _handleAction(context, ref, action),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.edit,
                            child: const Text('手动编辑'),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.aiRewrite,
                            child: const Text('AI 重写这一段'),
                          ),
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.aiModify,
                            child: const Text('按要求修改'),
                          ),
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.aiPartialRewrite,
                            child: const Text('选择性修改'),
                          ),
                          const PopupMenuItem(
                            value: _SegmentMenuAction.aiInsertAfter,
                            enabled: false,
                            child: Text('在后面生成 · AI 接入后开放'),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.insertBefore,
                            child: const Text('在前面插入'),
                          ),
                          PopupMenuItem(
                            enabled: !storyEnded,
                            value: _SegmentMenuAction.insertAfter,
                            child: const Text('在后面插入'),
                          ),
                          PopupMenuItem(
                            value: _SegmentMenuAction.moveUp,
                            enabled: index > 0,
                            child: const Text('上移'),
                          ),
                          PopupMenuItem(
                            value: _SegmentMenuAction.moveDown,
                            enabled: index < allSegments.length - 1,
                            child: const Text('下移'),
                          ),
                          const PopupMenuItem(
                            value: _SegmentMenuAction.history,
                            child: Text('查看历史'),
                          ),
                          if (pluginEnabled || storyEnded)
                            const PopupMenuItem(
                              value: _SegmentMenuAction.candidates,
                              child: Text('候选与分叉'),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _SegmentMenuAction.delete,
                            child: Text('删除'),
                          ),
                        ],
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.ibukiColors.primarySoft,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusM,
                            ),
                          ),
                          child: const SizedBox.square(
                            dimension: AppTokens.compactButtonHeight,
                            child: Icon(Icons.more_horiz_rounded, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // SelectableText has its own internal scrollable. Give it a
                  // separate storage key so it cannot reset manuscript scroll.
                  KeyedSubtree(
                    key: PageStorageKey('segment-selection-${segment.id}'),
                    child: pluginEnabled
                        ? NovelReplyContent(
                            segment: segment,
                            textKey: Key('segment-preview-${segment.id}'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.75,
                            ),
                            onFillDraft: onFillDraft,
                            onOpenPanel: () =>
                                showNovelPluginPage(context, segment.projectId),
                          )
                        : SelectableText(
                            body,
                            key: Key('segment-preview-${segment.id}'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.75,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppTokens.spacingS),
                  Text(
                    '更新 ${formatLocalDateTime(segment.updatedAt)}'
                    '${historyCount == 0 ? '' : ' · $historyCount 个历史版本'}',
                    key: Key('segment-revision-${segment.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _SegmentMenuAction action,
  ) async {
    switch (action) {
      case _SegmentMenuAction.edit:
        await context.push(
          AppRoutes.editSegment(segment.projectId, segment.id),
        );
      case _SegmentMenuAction.insertBefore:
        await context.push(
          AppRoutes.insertSegment(segment.projectId, segment.id, before: true),
        );
      case _SegmentMenuAction.insertAfter:
        await context.push(
          AppRoutes.insertSegment(segment.projectId, segment.id, before: false),
        );
      case _SegmentMenuAction.history:
        await context.push(
          AppRoutes.segmentHistory(segment.projectId, segment.id),
        );
      case _SegmentMenuAction.moveUp:
        await _move(context, ref, -1);
      case _SegmentMenuAction.moveDown:
        await _move(context, ref, 1);
      case _SegmentMenuAction.delete:
        await _delete(context, ref);
      case _SegmentMenuAction.aiRewrite:
        await showSegmentAiDialog(
          context,
          segment: segment,
          operation: SegmentAiUiOperation.rewrite,
        );
      case _SegmentMenuAction.aiModify:
        await showSegmentAiDialog(
          context,
          segment: segment,
          operation: SegmentAiUiOperation.modify,
        );
      case _SegmentMenuAction.aiPartialRewrite:
        await context.push(
          AppRoutes.editSegment(segment.projectId, segment.id),
        );
      case _SegmentMenuAction.candidates:
        await showNovelCandidates(context, ref, segment);
      case _SegmentMenuAction.aiInsertAfter:
        return;
    }
  }

  Future<void> _move(BuildContext context, WidgetRef ref, int offset) async {
    final target = index + offset;
    if (target < 0 || target >= allSegments.length) {
      return;
    }
    final orderedIds = allSegments.map((item) => item.id).toList();
    final moved = orderedIds.removeAt(index);
    orderedIds.insert(target, moved);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(reorderSegmentsProvider)(
        projectId: segment.projectId,
        orderedIds: orderedIds,
        updatedAt: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      showSegmentSnack(context, friendlySegmentError(error));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await showSegmentDeleteDialog(context)) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(softDeleteSegmentProvider)(
        projectId: segment.projectId,
        segmentId: segment.id,
        deletedAt: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      showSegmentSnack(context, friendlySegmentError(error));
    }
  }
}

class _AiDraftSegment extends StatelessWidget {
  const _AiDraftSegment({
    required this.draft,
    required this.generating,
    required this.retryingConnection,
    required this.stopped,
    required this.error,
    required this.onShowErrorDetail,
    required this.onKeep,
    required this.onDiscard,
  });

  final String draft;
  final bool generating;
  final bool retryingConnection;
  final bool stopped;
  final String? error;
  final VoidCallback? onShowErrorDetail;
  final VoidCallback? onKeep;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('novel-streaming-draft'),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingM),
      child: IbukiGlassSurface(
        strong: true,
        radius: AppTokens.bubbleRadius,
        padding: const EdgeInsets.all(AppTokens.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  generating
                      ? Icons.auto_awesome_rounded
                      : Icons.edit_note_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppTokens.spacingS),
                Text(
                  generating
                      ? retryingConnection
                            ? '连接意外中断，正在重新尝试……'
                            : '伊吹正在写……'
                      : stopped
                      ? '生成已停止'
                      : 'AI 草稿',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            if (draft.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spacingS),
              KeyedSubtree(
                key: const PageStorageKey('novel-draft-selection'),
                child: SelectableText(draft, style: theme.textTheme.bodyLarge),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: AppTokens.spacingS),
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              if (onShowErrorDetail != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('novel-ai-error-detail-button'),
                    onPressed: onShowErrorDetail,
                    child: const Text('查看详情'),
                  ),
                ),
            ],
            if (stopped && draft.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spacingS),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppTokens.spacingS,
                children: [
                  TextButton(onPressed: onDiscard, child: const Text('丢弃')),
                  FilledButton.tonal(
                    key: const Key('keep-stopped-novel-draft'),
                    onPressed: onKeep,
                    child: const Text('保留草稿'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NovelContextToolbar extends StatelessWidget {
  const _NovelContextToolbar({
    required this.selectedCharacterCount,
    required this.selectedWorldCount,
    required this.onOpenCharacters,
    required this.onOpenWorld,
    required this.onOpenAiSettings,
    required this.providerLabel,
  });
  final int selectedCharacterCount, selectedWorldCount;
  final VoidCallback onOpenCharacters, onOpenWorld, onOpenAiSettings;
  final String? providerLabel;
  @override
  Widget build(BuildContext context) => IbukiGlassSurface(
    key: const Key('novel-context-toolbar'),
    strong: true,
    radius: 20,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: TextButton.icon(
            key: const Key('novel-character-context'),
            onPressed: onOpenCharacters,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              backgroundColor: context.ibukiColors.primarySoft,
            ),
            icon: const Icon(Icons.people_outline_rounded, size: 18),
            label: Text(
              selectedCharacterCount == 0 ? '角色' : '角色 $selectedCharacterCount',
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spacingXs),
        Expanded(
          child: TextButton.icon(
            key: const Key('novel-world-context'),
            onPressed: onOpenWorld,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              backgroundColor: context.ibukiColors.accentSoft,
              foregroundColor: context.ibukiColors.accent,
            ),
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: Text(
              selectedWorldCount == 0 ? '世界' : '世界 $selectedWorldCount',
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spacingXs),
        Expanded(
          flex: 2,
          child: TextButton.icon(
            key: const Key('novel-ai-provider'),
            onPressed: onOpenAiSettings,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(
              providerLabel ?? '尚未配置 AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),
  );
}

class _NovelDirectionComposer extends StatelessWidget {
  const _NovelDirectionComposer({
    required this.controller,
    required this.focusNode,
    required this.onManualAdd,
    this.onPluginMode,
    required this.hasManuscript,
    required this.extrasExpanded,
    required this.onExtrasToggle,
    required this.onGenerate,
    required this.onStop,
    required this.generating,
    required this.autoStoryEnabled,
    required this.autoStoryRunning,
    required this.autoStoryGeneratedCount,
    required this.onAutoStoryChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onManualAdd;
  final ValueChanged<NovelGenerationMode>? onPluginMode;
  final bool hasManuscript;
  final bool extrasExpanded;
  final VoidCallback onExtrasToggle;
  final VoidCallback onGenerate;
  final VoidCallback onStop;
  final bool generating;
  final bool autoStoryEnabled;
  final bool autoStoryRunning;
  final int autoStoryGeneratedCount;
  final ValueChanged<bool> onAutoStoryChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyedSubtree(
      key: const Key('novel-composer'),
      child: SafeArea(
        top: false,
        bottom: false,
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.bubbleComposerRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spacingM,
                AppTokens.spacingS,
                AppTokens.spacingM,
                AppTokens.spacingS,
              ),
              decoration: BoxDecoration(
                color: context.bubbleTheme.glassStrong,
                borderRadius: BorderRadius.circular(
                  AppTokens.bubbleComposerRadius,
                ),
                border: Border.all(color: context.bubbleTheme.glassBorder),
                boxShadow: [
                  BoxShadow(
                    color: context.bubbleTheme.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                key: const Key('novel-direction-composer'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: IbukiMotion.durationOf(
                      context,
                      IbukiMotion.enter,
                    ),
                    curve: IbukiMotion.curve,
                    alignment: Alignment.bottomCenter,
                    child: extrasExpanded
                        ? Padding(
                            key: const Key('novel-extra-creation-panel'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              children: [
                                Center(
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: context.ibukiColors.textMuted
                                          .withValues(alpha: .35),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        key: const Key('new-segment-button'),
                                        onPressed:
                                            generating || autoStoryRunning
                                            ? null
                                            : onManualAdd,
                                        icon: const Icon(
                                          Icons.edit_note_outlined,
                                        ),
                                        label: const Text('手动添加'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilterChip(
                                        key: const Key(
                                          'novel-auto-story-toggle',
                                        ),
                                        selected: autoStoryEnabled,
                                        onSelected:
                                            generating && !autoStoryRunning
                                            ? null
                                            : onAutoStoryChanged,
                                        avatar: const Icon(
                                          Icons.playlist_play_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('自动剧情'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  autoStoryRunning
                                      ? '已生成 $autoStoryGeneratedCount 段，可随时停止。'
                                      : '开启自动剧情后，会连续生成直到你停止。',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: context.ibukiColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppTokens.spacingXs),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 17,
                        color: context.ibukiColors.accent,
                      ),
                      const SizedBox(width: AppTokens.spacingXs),
                      Expanded(
                        child: Text(
                          '下一段想发生什么？',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (onPluginMode != null)
                        PopupMenuButton<NovelGenerationMode>(
                          key: const Key('novel-plugin-generation-modes'),
                          tooltip: '插件生成模式',
                          enabled: !generating && !autoStoryRunning,
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 20,
                          ),
                          onSelected: onPluginMode,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: NovelGenerationMode.continueReply,
                              enabled: hasManuscript,
                              child: const Text('接着上一段续写'),
                            ),
                            const PopupMenuItem(
                              value: NovelGenerationMode.impersonate,
                              child: Text('代写作者草稿'),
                            ),
                            const PopupMenuItem(
                              value: NovelGenerationMode.group,
                              child: Text('指定角色发言'),
                            ),
                            const PopupMenuItem(
                              value: NovelGenerationMode.empty,
                              child: Text('空发推进'),
                            ),
                          ],
                        ),
                      const SizedBox(width: AppTokens.spacingXs),
                      TextButton.icon(
                        key: const Key('novel-extra-creation'),
                        onPressed: onExtrasToggle,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: autoStoryEnabled
                              ? theme.colorScheme.primary
                              : context.ibukiColors.textMuted,
                        ),
                        icon: Icon(
                          extrasExpanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          size: 18,
                        ),
                        label: const Text('额外创作'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spacingXs),
                  TextField(
                    key: const Key('novel-composer-field'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 2,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '告诉伊吹，接下来想怎么写……',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppTokens.spacingM,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingS),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('novel-generate-next'),
                          onPressed: generating || autoStoryRunning
                              ? onStop
                              : onGenerate,
                          icon: Icon(
                            generating || autoStoryRunning
                                ? Icons.stop_rounded
                                : Icons.auto_awesome_outlined,
                          ),
                          label: Text(
                            autoStoryRunning
                                ? '停止自动剧情'
                                : generating
                                ? '停止'
                                : autoStoryEnabled
                                ? '开始自动剧情'
                                : '生成下一段',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SegmentMenuAction {
  candidates,
  edit,
  aiRewrite,
  aiModify,
  aiPartialRewrite,
  aiInsertAfter,
  insertBefore,
  insertAfter,
  moveUp,
  moveDown,
  history,
  delete,
}
