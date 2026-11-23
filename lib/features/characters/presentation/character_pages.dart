import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation/app_workspace_mode.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../application/ai/card_completion.dart';
import '../../../domain/characters/character_card.dart';
import '../../../domain/common/entity_metadata.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import '../../projects/presentation/project_flow_widgets.dart';
import '../../ai/presentation/card_completion_dialog.dart';

class CharacterListPage extends ConsumerWidget {
  const CharacterListPage({
    required this.projectId,
    this.workspaceMode = AppWorkspaceMode.novel,
    super.key,
  });

  final String projectId;
  final AppWorkspaceMode workspaceMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final characters = ref.watch(characterListProvider(projectId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context, workspaceMode),
        data: (project) {
          if (project.deletedAt != null) {
            return _deletedProject(context, workspaceMode);
          }
          _selectCurrentProject(ref, project.id);
          return characters.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ProjectFlowErrorView(
              title: '角色读取失败',
              message: _friendlyError(error),
            ),
            data: (items) => ListView(
              key: const Key('character-list-page'),
              padding: const EdgeInsets.all(AppTokens.spacingM),
              children: [
                _ListHeader(
                  title: '角色',
                  projectTitle: project.title,
                  countLabel: '角色 ${items.length}',
                  newKey: const Key('new-character-button'),
                  deletedKey: const Key('deleted-characters-button'),
                  newLabel: '新建角色',
                  onNew: () => context.push(
                    _workspacePath(
                      AppRoutes.newCharacter(project.id),
                      workspaceMode,
                    ),
                  ),
                  onDeleted: () => context.push(
                    _workspacePath(
                      AppRoutes.deletedCharacters(project.id),
                      workspaceMode,
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spacingM),
                if (items.isEmpty)
                  const _CharacterEmptyState()
                else
                  for (var index = 0; index < items.length; index += 1)
                    _CharacterTile(
                      character: items[index],
                      index: index,
                      count: items.length,
                      workspaceMode: workspaceMode,
                      onMove: (delta) =>
                          _move(context, ref, items, index, delta),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<CharacterCard> items,
    int index,
    int delta,
  ) async {
    final target = index + delta;
    if (target < 0 || target >= items.length) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    final ordered = items.map((item) => item.id).toList();
    final moved = ordered.removeAt(index);
    ordered.insert(target, moved);
    try {
      await ref.read(reorderCharacterCardsProvider)(
        projectId: projectId,
        orderedIds: ordered,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.characters],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

class NewCharacterPage extends ConsumerStatefulWidget {
  const NewCharacterPage({
    required this.projectId,
    this.workspaceMode = AppWorkspaceMode.novel,
    this.returnOnComplete = false,
    super.key,
  });

  final String projectId;
  final AppWorkspaceMode workspaceMode;
  final bool returnOnComplete;

  @override
  ConsumerState<NewCharacterPage> createState() => _NewCharacterPageState();
}

class _NewCharacterPageState extends ConsumerState<NewCharacterPage> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  late final TextEditingController _sourceWork;
  late final TextEditingController _sourceCharacter;
  late final TextEditingController _sourceVersion;
  late final TextEditingController _adaptation;
  late final TextEditingController _originalIdea;
  CharacterCardMode? _mode = CharacterCardMode.original;
  var _saving = false;
  String? _nameError;
  String? _modeError;
  String? _sourceWorkError;
  String? _sourceCharacterError;

  bool get _hasUnsaved =>
      !_saving &&
      [
        _name,
        _content,
        _sourceWork,
        _sourceCharacter,
        _sourceVersion,
        _adaptation,
        _originalIdea,
      ].any((controller) => controller.text.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onInput);
    _content = TextEditingController()..addListener(_onInput);
    _sourceWork = TextEditingController()..addListener(_onInput);
    _sourceCharacter = TextEditingController()..addListener(_onInput);
    _sourceVersion = TextEditingController()..addListener(_onInput);
    _adaptation = TextEditingController()..addListener(_onInput);
    _originalIdea = TextEditingController()..addListener(_onInput);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _sourceWork.dispose();
    _sourceCharacter.dispose();
    _sourceVersion.dispose();
    _adaptation.dispose();
    _originalIdea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmDiscard() && context.mounted) {
          context.pop();
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _missingProject(context, widget.workspaceMode),
          data: (project) => project.deletedAt != null
              ? _deletedProject(context, widget.workspaceMode)
              : _CharacterForm(
                  pageKey: const Key('new-character-page'),
                  onBack: () => _backFromCharacterForm(
                    context,
                    widget.projectId,
                    widget.workspaceMode,
                  ),
                  name: _name,
                  content: _content,
                  mode: _mode,
                  onModeChanged: (value) => setState(() {
                    _mode = value;
                    _modeError = null;
                  }),
                  sourceWork: _sourceWork,
                  sourceCharacter: _sourceCharacter,
                  sourceVersion: _sourceVersion,
                  adaptation: _adaptation,
                  sourceWorkError: _sourceWorkError,
                  sourceCharacterError: _sourceCharacterError,
                  nameError: _nameError,
                  modeError: _modeError,
                  saving: _saving,
                  saveLabel: '创建角色',
                  onAiComplete: _mode == CharacterCardMode.fanfic
                      ? _completeWithAi
                      : null,
                  aiLabel: 'AI 参考原作',
                  onSave: _save,
                ),
        ),
      ),
    );
  }

  void _onInput() {
    if (!mounted || _saving) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    if (_nameError != null && _name.text.trim().isNotEmpty) {
      _nameError = null;
    }
    if (_sourceWorkError != null && _sourceWork.text.trim().isNotEmpty) {
      _sourceWorkError = null;
    }
    if (_sourceCharacterError != null &&
        _sourceCharacter.text.trim().isNotEmpty) {
      _sourceCharacterError = null;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_mode == null) {
      setState(() => _modeError = '请先选择同人角色或原创角色');
      return;
    }
    if (_mode == CharacterCardMode.fanfic &&
        (_sourceWork.text.trim().isEmpty ||
            _sourceCharacter.text.trim().isEmpty)) {
      setState(() {
        _sourceWorkError = _sourceWork.text.trim().isEmpty ? '请填写作品名称' : null;
        _sourceCharacterError = _sourceCharacter.text.trim().isEmpty
            ? '请填写原作角色名称'
            : null;
      });
      return;
    }
    if (_content.text.trim().isEmpty &&
        !await _confirmEmpty(context, '创建空内容角色？', '可以先保存名字，之后再补充角色设定。')) {
      return;
    }
    setState(() => _saving = true);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final character = await ref.read(createCharacterCardProvider)(
        projectId: widget.projectId,
        name: _name.text.trim().isEmpty && _mode == CharacterCardMode.fanfic
            ? _sourceCharacter.text
            : _name.text,
        content: _content.text,
        mode: _mode!,
        sourceWorkTitle: _sourceWork.text,
        sourceCharacterName: _sourceCharacter.text,
        sourceVersionHint: _sourceVersion.text,
        fanficAdaptationNotes: _adaptation.text,
        originalIdea: _originalIdea.text,
        id: ref.read(entityIdGeneratorProvider).nextId('character'),
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.characters],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      if (widget.returnOnComplete && context.canPop()) {
        context.pop(character);
        return;
      }
      context.go(
        _workspacePath(
          AppRoutes.character(widget.projectId, character.id),
          widget.workspaceMode,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(context, _friendlyError(error));
      setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsaved) {
      return true;
    }
    return _confirmDiscardChanges(context);
  }

  Future<void> _completeWithAi() async {
    if (_mode != CharacterCardMode.fanfic) return;
    if (_mode == CharacterCardMode.fanfic &&
        (_sourceWork.text.trim().isEmpty ||
            _sourceCharacter.text.trim().isEmpty)) {
      setState(() {
        _sourceWorkError = _sourceWork.text.trim().isEmpty ? '请先填写作品名称' : null;
        _sourceCharacterError = _sourceCharacter.text.trim().isEmpty
            ? '请先填写原作角色名称'
            : null;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final now = ref.read(utcClockProvider).now();
      final draft = CharacterCard(
        metadata: EntityMetadata(
          id: 'character-draft',
          createdAt: now,
          updatedAt: now,
          revision: 0,
        ),
        projectId: widget.projectId,
        name: _name.text,
        content: _content.text,
        sortOrder: 0,
        mode: _mode!,
        sourceWorkTitle: _sourceWork.text,
        sourceCharacterName: _sourceCharacter.text,
        sourceVersionHint: _sourceVersion.text,
        fanficAdaptationNotes: _adaptation.text,
        originalIdea: _originalIdea.text,
      );
      const mode = CardCompletionMode.canonReference;
      final suggestions = await ref
          .read(cardCompletionServiceProvider)
          .completeCharacter(
            card: draft,
            mode: mode,
            instruction: '',
            requestId: ref
                .read(entityIdGeneratorProvider)
                .nextId('card_completion'),
          );
      if (!mounted) return;
      final accepted = await showCardCompletionPreview(
        context: context,
        suggestions: suggestions,
        mode: mode,
      );
      if (accepted == null || !mounted) return;
      if (accepted['name'] != null) _name.text = accepted['name']!;
      if (accepted['content'] != null) _content.text = accepted['content']!;
      setState(() {});
    } catch (error) {
      if (mounted) _showSnack(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class CharacterDetailPage extends ConsumerWidget {
  const CharacterDetailPage({
    required this.projectId,
    required this.characterId,
    this.workspaceMode = AppWorkspaceMode.novel,
    super.key,
  });

  final String projectId;
  final String characterId;
  final AppWorkspaceMode workspaceMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final character = ref.watch(characterByIdProvider(characterId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context, workspaceMode),
        data: (project) => project.deletedAt != null
            ? _deletedProject(context, workspaceMode)
            : character.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    _missingCharacter(context, projectId, workspaceMode),
                data: (character) {
                  if (character.projectId != projectId ||
                      character.deletedAt != null) {
                    return _missingCharacter(context, projectId, workspaceMode);
                  }
                  return ListView(
                    key: const Key('character-detail-page'),
                    padding: const EdgeInsets.all(AppTokens.spacingM),
                    children: [
                      Text(
                        character.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppTokens.spacingXs),
                      Text('所属项目：${project.title}'),
                      const SizedBox(height: AppTokens.spacingS),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          key: const Key('character-mode-chip'),
                          avatar: Icon(
                            character.mode == CharacterCardMode.fanfic
                                ? Icons.auto_stories_outlined
                                : character.mode == CharacterCardMode.original
                                ? Icons.draw_outlined
                                : Icons.help_outline,
                            size: 18,
                          ),
                          label: Text(_modeLabel(character.mode)),
                        ),
                      ),
                      if (character.sourceFormat.isNotEmpty) ...[
                        const SizedBox(height: AppTokens.spacingS),
                        ListTile(
                          key: const Key('character-compatibility-source'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.move_to_inbox_outlined),
                          title: Text(
                            '来源：${_sourceFormatLabel(character.sourceFormat)}',
                          ),
                          subtitle: const Text('角色设定已映射到 IbukiHome 原生角色'),
                          trailing: character.compatibilityPayloadId == null
                              ? null
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: character.compatibilityPayloadId == null
                              ? null
                              : () => context.push(
                                  AppRoutes.sillyTavernCompatibility(
                                    character.compatibilityPayloadId!,
                                  ),
                                ),
                        ),
                      ],
                      if (character.mode == CharacterCardMode.fanfic) ...[
                        const SizedBox(height: AppTokens.spacingS),
                        Text(
                          '原作来源',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                                character.sourceWorkTitle,
                                character.sourceCharacterName,
                                character.sourceVersionHint,
                              ]
                              .where((value) => value.trim().isNotEmpty)
                              .join(' · '),
                        ),
                        if (character.fanficAdaptationNotes
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: AppTokens.spacingS),
                          Text(
                            '二创设定 / 与原作不同之处',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          SelectableText(character.fanficAdaptationNotes),
                        ],
                        const SizedBox(height: AppTokens.spacingXs),
                        Text(
                          '当前只有模型知识时，App 会标记为“AI 参考”，不会伪装成联网核对。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (character.mode == CharacterCardMode.original &&
                          character.originalIdea.trim().isNotEmpty) ...[
                        const SizedBox(height: AppTokens.spacingS),
                        Text(
                          '初始构想',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SelectableText(character.originalIdea),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('edit-character-button'),
                              onPressed: () => context.push(
                                _workspacePath(
                                  AppRoutes.editCharacter(
                                    projectId,
                                    character.id,
                                  ),
                                  workspaceMode,
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(context.tr('编辑')),
                            ),
                          ),
                          const SizedBox(width: AppTokens.spacingS),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('delete-character-button'),
                              onPressed: () => _delete(context, ref, character),
                              icon: const Icon(Icons.delete_outline),
                              label: Text(context.tr('删除')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spacingS),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              key: const Key('confirm-character-settings'),
                              onPressed: () {
                                if (context.canPop()) {
                                  context.pop(character);
                                } else {
                                  context.go(
                                    _workspacePath(
                                      AppRoutes.projectCharacters(projectId),
                                      workspaceMode,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: Text(context.tr('确定角色设置')),
                            ),
                          ),
                          const SizedBox(width: AppTokens.spacingS),
                          const Spacer(),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CharacterCard character,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-character-dialog'),
        title: const Text('删除角色？'),
        content: Text('“${character.name}”会移到已删除角色中，之后仍可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-delete-character-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(softDeleteCharacterCardProvider)(
        projectId: projectId,
        characterId: character.id,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.characters],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(
        _workspacePath(AppRoutes.projectCharacters(projectId), workspaceMode),
      );
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

class EditCharacterPage extends ConsumerStatefulWidget {
  const EditCharacterPage({
    required this.projectId,
    required this.characterId,
    this.workspaceMode = AppWorkspaceMode.novel,
    super.key,
  });

  final String projectId;
  final String characterId;
  final AppWorkspaceMode workspaceMode;

  @override
  ConsumerState<EditCharacterPage> createState() => _EditCharacterPageState();
}

class _EditCharacterPageState extends ConsumerState<EditCharacterPage> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  late final TextEditingController _sourceWork;
  late final TextEditingController _sourceCharacter;
  late final TextEditingController _sourceVersion;
  late final TextEditingController _adaptation;
  late final TextEditingController _originalIdea;
  CharacterCard? _loaded;
  var _originalName = '';
  var _originalContent = '';
  CharacterCardMode? _mode;
  CharacterCardMode? _originalMode;
  var _originalSourceWork = '';
  var _originalSourceCharacter = '';
  var _originalSourceVersion = '';
  var _originalAdaptation = '';
  var _originalIdeaValue = '';
  var _saving = false;
  var _syncing = false;
  String? _nameError;
  String? _sourceWorkError;
  String? _sourceCharacterError;

  bool get _hasUnsaved =>
      !_saving &&
      (_name.text != _originalName ||
          _content.text != _originalContent ||
          _mode != _originalMode ||
          _sourceWork.text != _originalSourceWork ||
          _sourceCharacter.text != _originalSourceCharacter ||
          _sourceVersion.text != _originalSourceVersion ||
          _adaptation.text != _originalAdaptation ||
          _originalIdea.text != _originalIdeaValue);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onInput);
    _content = TextEditingController()..addListener(_onInput);
    _sourceWork = TextEditingController()..addListener(_onInput);
    _sourceCharacter = TextEditingController()..addListener(_onInput);
    _sourceVersion = TextEditingController()..addListener(_onInput);
    _adaptation = TextEditingController()..addListener(_onInput);
    _originalIdea = TextEditingController()..addListener(_onInput);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _sourceWork.dispose();
    _sourceCharacter.dispose();
    _sourceVersion.dispose();
    _adaptation.dispose();
    _originalIdea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final character = ref.watch(characterByIdProvider(widget.characterId));
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop &&
            await _confirmDiscardChanges(context) &&
            context.mounted) {
          context.pop();
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _missingProject(context, widget.workspaceMode),
          data: (project) => project.deletedAt != null
              ? _deletedProject(context, widget.workspaceMode)
              : character.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _missingCharacter(
                    context,
                    widget.projectId,
                    widget.workspaceMode,
                  ),
                  data: (character) {
                    if (character.projectId != widget.projectId ||
                        character.deletedAt != null) {
                      return _missingCharacter(
                        context,
                        widget.projectId,
                        widget.workspaceMode,
                      );
                    }
                    _sync(character);
                    return _CharacterForm(
                      pageKey: const Key('edit-character-page'),
                      onBack: () => _backFromCharacterForm(
                        context,
                        widget.projectId,
                        widget.workspaceMode,
                      ),
                      name: _name,
                      content: _content,
                      mode: _mode,
                      onModeChanged: (value) => setState(() => _mode = value),
                      sourceWork: _sourceWork,
                      sourceCharacter: _sourceCharacter,
                      sourceVersion: _sourceVersion,
                      adaptation: _adaptation,
                      sourceWorkError: _sourceWorkError,
                      sourceCharacterError: _sourceCharacterError,
                      nameError: _nameError,
                      saving: _saving,
                      saveLabel: '保存修改',
                      onAiComplete: _mode == CharacterCardMode.fanfic
                          ? () => _completeWithAi(character)
                          : null,
                      aiLabel: 'AI 参考原作',
                      onSave: _save,
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _sync(CharacterCard character) {
    if (_loaded?.id == character.id) {
      return;
    }
    _loaded = character;
    _originalName = character.name;
    _originalContent = character.content;
    _originalMode = character.mode;
    _originalSourceWork = character.sourceWorkTitle;
    _originalSourceCharacter = character.sourceCharacterName;
    _originalSourceVersion = character.sourceVersionHint;
    _originalAdaptation = character.fanficAdaptationNotes;
    _originalIdeaValue = character.originalIdea;
    _mode = character.mode;
    _syncing = true;
    _name.text = character.name;
    _content.text = character.content;
    _sourceWork.text = character.sourceWorkTitle;
    _sourceCharacter.text = character.sourceCharacterName;
    _sourceVersion.text = character.sourceVersionHint;
    _adaptation.text = character.fanficAdaptationNotes;
    _originalIdea.text = character.originalIdea;
    _syncing = false;
  }

  void _onInput() {
    if (!mounted || _saving || _syncing) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    if (_nameError != null && _name.text.trim().isNotEmpty) {
      _nameError = null;
    }
    if (_sourceWorkError != null && _sourceWork.text.trim().isNotEmpty) {
      _sourceWorkError = null;
    }
    if (_sourceCharacterError != null &&
        _sourceCharacter.text.trim().isNotEmpty) {
      _sourceCharacterError = null;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '角色名称不能为空');
      return;
    }
    if (_mode == CharacterCardMode.fanfic &&
        (_sourceWork.text.trim().isEmpty ||
            _sourceCharacter.text.trim().isEmpty)) {
      setState(() {
        _sourceWorkError = _sourceWork.text.trim().isEmpty ? '请填写作品名称' : null;
        _sourceCharacterError = _sourceCharacter.text.trim().isEmpty
            ? '请填写原作角色名称'
            : null;
      });
      return;
    }
    setState(() => _saving = true);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final updated = await ref.read(saveCharacterCardProvider)(
        projectId: widget.projectId,
        characterId: widget.characterId,
        name: _name.text,
        content: _content.text,
        mode: _mode,
        sourceWorkTitle: _sourceWork.text,
        sourceCharacterName: _sourceCharacter.text,
        sourceVersionHint: _sourceVersion.text,
        fanficAdaptationNotes: _adaptation.text,
        originalIdea: _originalIdea.text,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      _loaded = updated;
      _originalName = updated.name;
      _originalContent = updated.content;
      _originalMode = updated.mode;
      _originalSourceWork = updated.sourceWorkTitle;
      _originalSourceCharacter = updated.sourceCharacterName;
      _originalSourceVersion = updated.sourceVersionHint;
      _originalAdaptation = updated.fanficAdaptationNotes;
      _originalIdeaValue = updated.originalIdea;
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.characters],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      setState(() => _saving = false);
      _showSnack(context, '角色已保存。');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(context, _friendlyError(error));
      setState(() => _saving = false);
    }
  }

  Future<void> _completeWithAi(CharacterCard card) async {
    final options = await showCardCompletionOptions(
      context,
      characterMode: _mode,
    );
    if (options == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final suggestions = await ref
          .read(cardCompletionServiceProvider)
          .completeCharacter(
            card: card.copyWith(
              name: _name.text,
              content: _content.text,
              mode: _mode,
              sourceWorkTitle: _sourceWork.text,
              sourceCharacterName: _sourceCharacter.text,
              sourceVersionHint: _sourceVersion.text,
              fanficAdaptationNotes: _adaptation.text,
              originalIdea: _originalIdea.text,
            ),
            mode: options.mode,
            instruction: options.instruction,
            requestId: ref
                .read(entityIdGeneratorProvider)
                .nextId('card_completion'),
          );
      if (!mounted) return;
      final accepted = await showCardCompletionPreview(
        context: context,
        suggestions: suggestions,
        mode: options.mode,
      );
      if (accepted == null || !mounted) return;
      _syncing = true;
      if (accepted['name'] != null) _name.text = accepted['name']!;
      if (accepted['content'] != null) _content.text = accepted['content']!;
      _syncing = false;
      setState(() {});
    } catch (error) {
      if (mounted) _showSnack(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class DeletedCharacterListPage extends ConsumerWidget {
  const DeletedCharacterListPage({
    required this.projectId,
    this.workspaceMode = AppWorkspaceMode.novel,
    super.key,
  });

  final String projectId;
  final AppWorkspaceMode workspaceMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final characters = ref.watch(deletedCharacterListProvider(projectId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context, workspaceMode),
        data: (project) => project.deletedAt != null
            ? _deletedProject(context, workspaceMode)
            : characters.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ProjectFlowErrorView(
                  title: '已删除角色读取失败',
                  message: _friendlyError(error),
                ),
                data: (items) => ListView(
                  key: const Key('deleted-character-list-page'),
                  padding: const EdgeInsets.all(AppTokens.spacingM),
                  children: [
                    Text(
                      '已删除角色',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text('${project.title} · ${items.length} 个'),
                    const SizedBox(height: AppTokens.spacingM),
                    if (items.isEmpty)
                      const _SimpleEmptyState(
                        key: Key('empty-deleted-characters'),
                        icon: Icons.restore_from_trash_outlined,
                        title: '没有已删除角色。',
                        message: '删除的角色会保留在这里，方便之后恢复。',
                      )
                    else
                      for (final character in items)
                        Card(
                          child: ListTile(
                            key: Key('deleted-character-${character.id}'),
                            title: Text(character.name),
                            subtitle: Text(
                              '${_preview(character.content)}\n'
                              '删除 ${formatLocalDateTime(character.deletedAt!)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: FilledButton.tonal(
                              key: Key('restore-character-${character.id}'),
                              onPressed: () =>
                                  _restore(context, ref, character),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    CharacterCard character,
  ) async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(restoreCharacterCardProvider)(
        projectId: projectId,
        characterId: character.id,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.characters],
      );
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      if (context.mounted) {
        _showSnack(context, '角色已恢复。');
      }
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

Future<void> _backFromCharacterForm(
  BuildContext context,
  String projectId,
  AppWorkspaceMode workspaceMode,
) async {
  final handled = await Navigator.of(context).maybePop();
  if (!handled && context.mounted) {
    context.go(
      _workspacePath(AppRoutes.projectCharacters(projectId), workspaceMode),
    );
  }
}

class _CharacterForm extends StatelessWidget {
  const _CharacterForm({
    required this.pageKey,
    required this.onBack,
    required this.name,
    required this.content,
    required this.mode,
    required this.onModeChanged,
    required this.sourceWork,
    required this.sourceCharacter,
    required this.sourceVersion,
    required this.adaptation,
    required this.nameError,
    required this.saving,
    required this.saveLabel,
    required this.onSave,
    this.onAiComplete,
    this.aiLabel = 'AI 参考原作',
    this.modeError,
    this.sourceWorkError,
    this.sourceCharacterError,
  });

  final Key pageKey;
  final VoidCallback onBack;
  final TextEditingController name;
  final TextEditingController content;
  final CharacterCardMode? mode;
  final ValueChanged<CharacterCardMode> onModeChanged;
  final TextEditingController sourceWork;
  final TextEditingController sourceCharacter;
  final TextEditingController sourceVersion;
  final TextEditingController adaptation;
  final String? nameError;
  final String? modeError;
  final String? sourceWorkError;
  final String? sourceCharacterError;
  final bool saving;
  final String saveLabel;
  final VoidCallback onSave;
  final VoidCallback? onAiComplete;
  final String aiLabel;

  @override
  Widget build(BuildContext context) {
    final fanfic = mode == CharacterCardMode.fanfic;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: pageKey,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                BackButton(
                  key: const Key('shell-back-button'),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AbsorbPointer(
                    absorbing: saving,
                    child: CupertinoSlidingSegmentedControl<CharacterCardMode>(
                      key: const Key('character-mode-selector'),
                      groupValue: mode ?? CharacterCardMode.original,
                      backgroundColor: scheme.surfaceContainerHigh,
                      thumbColor: scheme.primaryContainer,
                      padding: const EdgeInsets.all(4),
                      children: {
                        for (final item in [
                          CharacterCardMode.original,
                          CharacterCardMode.fanfic,
                        ])
                          item: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              item == CharacterCardMode.original
                                  ? '原创角色'
                                  : '同人角色',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color:
                                    (mode ?? CharacterCardMode.original) == item
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight:
                                    (mode ?? CharacterCardMode.original) == item
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                      },
                      onValueChanged: (value) {
                        if (value != null && !saving) onModeChanged(value);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (modeError != null)
                Text(
                  modeError!,
                  key: const Key('character-mode-error'),
                  style: TextStyle(color: scheme.error),
                ),
              if (fanfic) ...[
                TextField(
                  key: const Key('character-source-work-field'),
                  controller: sourceWork,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '原作名称',
                    errorText: sourceWorkError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('character-source-name-field'),
                  controller: sourceCharacter,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '原作角色',
                    errorText: sourceCharacterError,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('character-name-field'),
                controller: name,
                enabled: !saving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: fanfic ? '本作名称（选填）' : '名称',
                  hintText: fanfic ? '留空使用原作角色名' : null,
                  errorText: nameError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('character-content-field'),
                controller: content,
                enabled: !saving,
                keyboardType: TextInputType.multiline,
                minLines: fanfic ? 6 : 8,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: '角色内容',
                  hintText: '性格、经历、关系与其他设定',
                  alignLabelWithHint: true,
                ),
              ),
              if (fanfic) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  key: const Key('character-fanfic-details'),
                  initiallyExpanded:
                      sourceVersion.text.isNotEmpty ||
                      adaptation.text.isNotEmpty,
                  tilePadding: EdgeInsets.zero,
                  title: const Text('补充设定（选填）'),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [
                    TextField(
                      key: const Key('character-source-version-field'),
                      controller: sourceVersion,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: '版本 / 形态'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('character-adaptation-field'),
                      controller: adaptation,
                      enabled: !saving,
                      minLines: 3,
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: '二创差异',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ],
              if (fanfic && onAiComplete != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('character-ai-completion'),
                  onPressed: saving ? null : onAiComplete,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(aiLabel),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-character-button'),
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(saving ? '保存中' : saveLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.index,
    required this.count,
    required this.workspaceMode,
    required this.onMove,
  });

  final CharacterCard character;
  final int index;
  final int count;
  final AppWorkspaceMode workspaceMode;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: Key('character-tile-${character.id}'),
        title: Text(character.name),
        subtitle: Text(
          '${_modeLabel(character.mode)} · ${_preview(character.content)}\n'
          'revision ${character.revision} · '
          '更新 ${formatLocalDateTime(character.updatedAt)}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: () => context.push(
          _workspacePath(
            AppRoutes.character(character.projectId, character.id),
            workspaceMode,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('move-character-up-${character.id}'),
              tooltip: '上移',
              onPressed: index == 0 ? null : () => onMove(-1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              key: Key('move-character-down-${character.id}'),
              tooltip: '下移',
              onPressed: index == count - 1 ? null : () => onMove(1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterEmptyState extends StatelessWidget {
  const _CharacterEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _SimpleEmptyState(
      key: Key('empty-characters-state'),
      icon: Icons.badge_outlined,
      title: '这个项目还没有角色。',
      message: '先写下一个名字，再慢慢补充她的性格、经历与关系。',
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.projectTitle,
    required this.countLabel,
    required this.newKey,
    required this.deletedKey,
    required this.newLabel,
    required this.onNew,
    required this.onDeleted,
  });

  final String title;
  final String projectTitle;
  final String countLabel;
  final Key newKey;
  final Key deletedKey;
  final String newLabel;
  final VoidCallback onNew;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text('$projectTitle · $countLabel'),
        const SizedBox(height: AppTokens.spacingS),
        Wrap(
          spacing: AppTokens.spacingS,
          runSpacing: AppTokens.spacingS,
          children: [
            FilledButton.icon(
              key: newKey,
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: Text(newLabel),
            ),
            OutlinedButton.icon(
              key: deletedKey,
              onPressed: onDeleted,
              icon: const Icon(Icons.restore_from_trash_outlined),
              label: const Text('已删除'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SimpleEmptyState extends StatelessWidget {
  const _SimpleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Column(
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: AppTokens.spacingM),
            Text(title),
            const SizedBox(height: AppTokens.spacingS),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _missingProject(BuildContext context, AppWorkspaceMode workspaceMode) {
  return ProjectFlowErrorView(
    title: '项目不存在',
    message: '没有找到这个项目，请返回项目列表重新选择。',
    onAction: () => context.go(AppRoutes.projects),
  );
}

Widget _deletedProject(BuildContext context, AppWorkspaceMode workspaceMode) {
  return ProjectFlowErrorView(
    title: '项目已删除',
    message: '这个项目已被删除，不能继续编辑角色。',
    onAction: () => context.go(AppRoutes.projects),
  );
}

Widget _missingCharacter(
  BuildContext context,
  String projectId,
  AppWorkspaceMode workspaceMode,
) {
  return ProjectFlowErrorView(
    title: '角色不存在',
    message: '没有找到这个角色，或它不属于当前项目。',
    onAction: () => context.go(
      _workspacePath(AppRoutes.projectCharacters(projectId), workspaceMode),
    ),
    actionLabel: '返回角色列表',
  );
}

String _workspacePath(String path, AppWorkspaceMode workspaceMode) {
  return AppRoutes.forWorkspace(path, workspaceMode);
}

void _selectCurrentProject(WidgetRef ref, String projectId) {
  if (ref.read(currentProjectControllerProvider) == projectId) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref
        .read(currentProjectControllerProvider.notifier)
        .selectProject(projectId);
  });
}

Future<bool> _confirmDiscardChanges(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-character-changes-dialog'),
      title: const Text('放弃未保存的修改？'),
      content: const Text('返回后，这次输入的内容不会保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          key: const Key('confirm-discard-character-changes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('放弃修改'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> _confirmEmpty(
  BuildContext context,
  String title,
  String message,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('empty-character-content-dialog'),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续填写'),
        ),
        FilledButton(
          key: const Key('confirm-empty-character'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result ?? false;
}

String _preview(String content) {
  final value = content.trim();
  return value.isEmpty ? '内容为空' : value.replaceAll(RegExp(r'\s+'), ' ');
}

String _modeLabel(CharacterCardMode? mode) => switch (mode) {
  CharacterCardMode.fanfic => '同人角色',
  CharacterCardMode.original => '原创角色',
  null => '旧角色卡（待选择）',
};

String _sourceFormatLabel(String sourceFormat) {
  if (sourceFormat.startsWith('chara_card_v3')) {
    return 'SillyTavern Character Card V3';
  }
  if (sourceFormat.startsWith('chara_card_v2')) {
    return 'SillyTavern Character Card V2';
  }
  return sourceFormat;
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('名称不能为空')) {
    return '角色名称不能为空。';
  }
  if (text.contains('不属于当前项目')) {
    return '角色不属于当前项目。';
  }
  if (text.contains('已删除')) {
    return '该项目或角色已删除。';
  }
  return '操作失败，请稍后重试。';
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
