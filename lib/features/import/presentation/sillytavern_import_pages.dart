import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/import/sillytavern_import_plan.dart';
import '../../../application/import/sillytavern_import_providers.dart';
import '../../../application/import/sillytavern_parser.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../application/world_roleplay/world_roleplay_providers.dart';
import '../../../application/world_roleplay/world_prompt_layer.dart';
import '../../../domain/import/sillytavern_models.dart';
import '../../../domain/projects/project.dart';
import '../../../domain/world_roleplay/world_roleplay_models.dart';

class SillyTavernImportPage extends ConsumerStatefulWidget {
  const SillyTavernImportPage({
    this.expectedKind,
    this.initialProjectId,
    this.initialWorldId,
    this.returnOnComplete = false,
    this.deferForStory = false,
    super.key,
  });

  final SillyTavernAssetKind? expectedKind;
  final String? initialProjectId;
  final String? initialWorldId;
  final bool returnOnComplete;
  final bool deferForStory;

  @override
  ConsumerState<SillyTavernImportPage> createState() =>
      _SillyTavernImportPageState();
}

class _SillyTavernImportPageState extends ConsumerState<SillyTavernImportPage> {
  SillyTavernImportInspection? _inspection;
  String? _projectId;
  String? _worldId;
  String? _worldSessionId;
  String? _worldBookId;
  final _newProjectTitle = TextEditingController(text: '角色收藏');
  var _bookMode = SillyTavernCharacterBookImportMode.preserveOnly;
  var _personaVisibility = SillyTavernPersonaVisibility.public;
  var _promptMode = SillyTavernPromptImportMode.skip;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _projectId = widget.initialProjectId;
    _worldId = widget.initialWorldId;
  }

  @override
  void dispose() {
    _newProjectTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectListProvider).value ?? const <Project>[];
    final worlds =
        ref.watch(roleplayWorldListProvider).value ?? const <RoleplayWorld>[];
    _projectId = _validSelection(_projectId, projects.map((item) => item.id));
    _worldId = _validSelection(_worldId, worlds.map((item) => item.id));
    final inspection = _inspection;
    return ListView(
      key: const Key('sillytavern-import-page'),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spacingM,
        AppTokens.spacingS,
        AppTokens.spacingM,
        AppTokens.spacingXl,
      ),
      children: [
        if (inspection == null) ...[
          _ImportWelcome(onPick: _working ? null : _pick),
          const SizedBox(height: AppTokens.spacingM),
          const _ImportSafetyNote(),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spacingM),
            Text(
              _error!,
              key: const Key('sillytavern-import-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTokens.spacingL),
          _CompatibilityRecords(),
        ] else ...[
          _ImportPreviewHeader(inspection: inspection),
          if (inspection.existingPayloadIds.isNotEmpty)
            TextButton.icon(
              key: const Key('view-existing-import'),
              icon: const Icon(Icons.open_in_new),
              onPressed: () => context.push(
                AppRoutes.sillyTavernCompatibility(
                  inspection.existingPayloadIds.first,
                ),
              ),
              label: const Text('查看已有资产'),
            ),
          const SizedBox(height: AppTokens.spacingM),
          _AssetSummary(inspection: inspection),
          const SizedBox(height: AppTokens.spacingM),
          _destinationControls(inspection, projects: projects, worlds: worlds),
          const SizedBox(height: AppTokens.spacingM),
          _CompatibilitySections(inspection: inspection),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spacingM),
            Text(
              _error!,
              key: const Key('sillytavern-import-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTokens.spacingL),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                          _inspection = null;
                          _error = null;
                        }),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: AppTokens.spacingS),
              Expanded(
                child: FilledButton(
                  key: const Key('confirm-sillytavern-import'),
                  onPressed: _working ? null : _import,
                  child: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_importButtonLabel(inspection.asset.kind)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _destinationControls(
    SillyTavernImportInspection inspection, {
    required List<Project> projects,
    required List<RoleplayWorld> worlds,
  }) {
    final kind = inspection.asset.kind;
    return IbukiGlassSurface(
      key: const Key('sillytavern-import-destination'),
      strong: true,
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '导入到',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTokens.spacingS),
          if (kind == SillyTavernAssetKind.characterCard && projects.isEmpty)
            TextField(
              key: const Key('import-new-project-title'),
              controller: _newProjectTitle,
              decoration: const InputDecoration(labelText: '新建角色收藏项目'),
            ),
          if (kind == SillyTavernAssetKind.characterCard && projects.isNotEmpty)
            _ProjectSelector(
              projects: projects,
              value: _projectId,
              onChanged: (value) => setState(() => _projectId = value),
            ),
          if (_deferredStoryKind(kind)) const Text('用于当前新故事，开始故事时保存。'),
          if (kind != SillyTavernAssetKind.characterCard &&
              !_deferredStoryKind(kind))
            _WorldSelector(
              worlds: worlds,
              value: _worldId,
              onChanged: (value) => setState(() {
                _worldId = value;
                _worldBookId = null;
                _worldSessionId = null;
              }),
            ),
          if (kind == SillyTavernAssetKind.characterCard &&
              inspection.asset.characterCard?.characterBook != null) ...[
            const SizedBox(height: AppTokens.spacingM),
            DropdownButtonFormField<SillyTavernCharacterBookImportMode>(
              key: const Key('sillytavern-character-book-mode'),
              initialValue: _bookMode,
              decoration: const InputDecoration(labelText: '角色附带世界书'),
              items: const [
                DropdownMenuItem(
                  value: SillyTavernCharacterBookImportMode.preserveOnly,
                  child: Text('仅随角色保存'),
                ),
                DropdownMenuItem(
                  value: SillyTavernCharacterBookImportMode.createNewWorldBook,
                  child: Text('导入为新的世界书'),
                ),
                DropdownMenuItem(
                  value: SillyTavernCharacterBookImportMode.existingWorldBook,
                  child: Text('添加到已有世界书'),
                ),
              ],
              onChanged: (value) => setState(
                () => _bookMode =
                    value ?? SillyTavernCharacterBookImportMode.preserveOnly,
              ),
            ),
            if (_bookMode !=
                SillyTavernCharacterBookImportMode.preserveOnly) ...[
              const SizedBox(height: AppTokens.spacingS),
              _WorldSelector(
                worlds: worlds,
                value: _worldId,
                onChanged: (value) => setState(() {
                  _worldId = value;
                  _worldBookId = null;
                }),
              ),
              if (_bookMode ==
                      SillyTavernCharacterBookImportMode.existingWorldBook &&
                  _worldId != null)
                _WorldBookSelector(
                  worldId: _worldId!,
                  value: _worldBookId,
                  onChanged: (value) => setState(() => _worldBookId = value),
                ),
            ],
          ],
          if (kind == SillyTavernAssetKind.persona) ...[
            const SizedBox(height: AppTokens.spacingM),
            Text('其他角色会知道哪些信息？', style: Theme.of(context).textTheme.labelLarge),
            RadioGroup<SillyTavernPersonaVisibility>(
              groupValue: _personaVisibility,
              onChanged: (value) => setState(() => _personaVisibility = value!),
              child: const Column(
                children: [
                  RadioListTile(
                    value: SillyTavernPersonaVisibility.public,
                    title: Text('角色可见'),
                    subtitle: Text('其他角色会将描述视为关于你的已知信息'),
                  ),
                  RadioListTile(
                    value: SillyTavernPersonaVisibility.directorOnly,
                    title: Text('仅世界导演知道'),
                    subtitle: Text('不会直接作为角色已知信息'),
                  ),
                ],
              ),
            ),
          ],
          if (kind == SillyTavernAssetKind.promptPreset) ...[
            const SizedBox(height: AppTokens.spacingM),
            ExpansionTile(
              title: const Text('对比提示词'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    '当前世界提示词\n${worlds.where((world) => world.id == _worldId).map(WorldPromptMetadata.worldSystemPrompt).firstOrNull ?? "尚未选择世界"}\n\n导入候选\n${inspection.asset.promptPreset!.mainPrompt}',
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<SillyTavernPromptImportMode>(
              key: const Key('sillytavern-prompt-mode'),
              initialValue: _promptMode,
              decoration: const InputDecoration(labelText: '世界提示词处理'),
              items: const [
                DropdownMenuItem(
                  value: SillyTavernPromptImportMode.skip,
                  child: Text('暂不导入（推荐）'),
                ),
                DropdownMenuItem(
                  value: SillyTavernPromptImportMode.append,
                  child: Text('追加到现有提示词'),
                ),
                DropdownMenuItem(
                  value: SillyTavernPromptImportMode.replace,
                  child: Text('替换现有提示词'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _promptMode = value ?? _promptMode),
            ),
            if (_worldId != null)
              _WorldSessionSelector(
                worldId: _worldId!,
                value: _worldSessionId,
                onChanged: (value) => setState(() => _worldSessionId = value),
              ),
          ],
          if ((kind != SillyTavernAssetKind.characterCard &&
              worlds.isEmpty &&
              !_deferredStoryKind(kind)))
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spacingS),
              child: Text(
                '请先开始一个故事，用于保存我的角色或世界书。',
                style: TextStyle(color: context.ibukiColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final source = await ref.read(sillyTavernImportPickerProvider).pick();
      if (source == null) return;
      final inspection = await ref
          .read(sillyTavernImportServiceProvider)
          .inspect(source);
      if (widget.expectedKind != null &&
          inspection.asset.kind != widget.expectedKind) {
        throw SillyTavernParseException(
          '这里需要${_kindName(widget.expectedKind!)}，所选文件是${_kindName(inspection.asset.kind)}。',
        );
      }
      if (!mounted) return;
      setState(() {
        _inspection = inspection;
        _bookMode = SillyTavernCharacterBookImportMode.preserveOnly;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    final inspection = _inspection;
    if (inspection == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (_deferredStoryKind(inspection.asset.kind)) {
        var allowDuplicate = false;
        if (inspection.isDuplicate) {
          allowDuplicate = await _confirmConflicts(['该资产已经导入。']);
          if (!allowDuplicate) return;
        }
        if (!mounted) return;
        context.pop(
          SillyTavernStoryImport(
            inspection: inspection,
            personaVisibility: _personaVisibility,
            allowDuplicateSource: allowDuplicate,
          ),
        );
        return;
      }
      var destination = _destination();
      var plan = await ref
          .read(sillyTavernImportServiceProvider)
          .buildPlan(inspection: inspection, destination: destination);
      if (!plan.canImport) {
        final allowCopy = await _confirmConflicts(plan.conflicts);
        if (!allowCopy) return;
        destination = _destination(
          allowDuplicateSource: true,
          allowSameNameCopy: true,
        );
        plan = await ref
            .read(sillyTavernImportServiceProvider)
            .buildPlan(inspection: inspection, destination: destination);
      }
      final result = await ref
          .read(sillyTavernImportServiceProvider)
          .execute(plan);
      ref.read(sillyTavernImportRevisionProvider.notifier).bump();
      notifyRepositoryChanged(
        ref,
        areas: const [
          RepositoryDataArea.characters,
          RepositoryDataArea.projects,
        ],
      );
      notifyWorldRoleplayChanged(ref);
      if (!mounted) return;
      if (widget.returnOnComplete) {
        context.pop(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${inspection.asset.displayName} 已导入。')),
        );
        context.go(AppRoutes.sillyTavernCompatibility(result.payload.id));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _deferredStoryKind(SillyTavernAssetKind kind) =>
      widget.deferForStory &&
      (kind == SillyTavernAssetKind.persona ||
          kind == SillyTavernAssetKind.lorebook);

  SillyTavernImportDestination _destination({
    bool allowDuplicateSource = false,
    bool allowSameNameCopy = false,
  }) {
    return SillyTavernImportDestination(
      projectId: _projectId,
      newProjectTitle: (ref.read(projectListProvider).value?.isEmpty ?? false)
          ? _newProjectTitle.text
          : null,
      worldId: _worldId,
      worldSessionId: _worldSessionId,
      worldBookId: _worldBookId,
      characterBookMode: _bookMode,
      personaVisibility: _personaVisibility,
      promptMode: _promptMode,
      allowDuplicateSource: allowDuplicateSource,
      allowSameNameCopy: allowSameNameCopy,
    );
  }

  Future<bool> _confirmConflicts(List<String> conflicts) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('sillytavern-import-conflict-dialog'),
            title: const Text('确认导入副本'),
            content: Text(conflicts.join('\n\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('导入副本'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class SillyTavernCompatibilityDetailPage extends ConsumerWidget {
  const SillyTavernCompatibilityDetailPage({
    required this.payloadId,
    super.key,
  });

  final String payloadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = ref.watch(compatibilityPayloadByIdProvider(payloadId));
    return payload.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('兼容信息不存在。')),
      data: (item) => ListView(
        key: const Key('sillytavern-compatibility-detail'),
        padding: const EdgeInsets.all(AppTokens.spacingM),
        children: [
          IbukiGlassSurface(
            strong: true,
            padding: const EdgeInsets.all(AppTokens.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sourceFormat,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppTokens.spacingS),
                _detailRow('Source Version', item.sourceVersion),
                _detailRow('SHA-256', item.sourceSha256),
                _detailRow('关联资产', item.linkedEntityType),
                _detailRow('导入时间', item.createdAt.toLocal().toString()),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spacingM),
          _PayloadExpansion(title: '已映射字段', values: item.normalizedPayload),
          _PayloadExpansion(title: '已保存但暂不支持', values: item.unsupportedPayload),
          _StringExpansion(title: '安全标记', values: item.securityFlags),
          _StringExpansion(title: '导入提示', values: item.importWarnings),
          const SizedBox(height: AppTokens.spacingS),
          Text(
            '这些兼容数据仅按需读取。脚本不会执行，远程资源不会下载。',
            style: TextStyle(color: context.ibukiColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ImportWelcome extends StatelessWidget {
  const _ImportWelcome({required this.onPick});

  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      strong: true,
      padding: const EdgeInsets.all(AppTokens.spacingL),
      child: Column(
        children: [
          Icon(
            Icons.move_to_inbox_outlined,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.spacingM),
          Text(
            '从 SillyTavern 导入',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTokens.spacingS),
          const Text(
            '支持角色、我的角色、世界书与 Prompt / Preset JSON。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.spacingL),
          FilledButton.icon(
            key: const Key('pick-sillytavern-file'),
            onPressed: onPick,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('选择 .png 或 .json'),
          ),
        ],
      ),
    );
  }
}

class _ImportSafetyNote extends StatelessWidget {
  const _ImportSafetyNote();

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined),
          SizedBox(width: AppTokens.spacingS),
          Expanded(child: Text('扩展脚本只会被识别并保存，不会运行；远程链接不会被访问。')),
        ],
      ),
    );
  }
}

class _CompatibilityRecords extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(compatibilityPayloadListProvider);
    return records.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('兼容资产记录暂时无法读取。'),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '兼容资产记录',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTokens.spacingS),
            for (final item in items)
              ListTile(
                key: Key('compatibility-record-${item.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(item.sourceFormat),
                subtitle: Text(
                  '${item.linkedEntityType} · ${item.sourceSha256.substring(0, 12)}…',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    context.push(AppRoutes.sillyTavernCompatibility(item.id)),
              ),
          ],
        );
      },
    );
  }
}

class _ImportPreviewHeader extends StatelessWidget {
  const _ImportPreviewHeader({required this.inspection});

  final SillyTavernImportInspection inspection;

  @override
  Widget build(BuildContext context) {
    final asset = inspection.asset;
    return IbukiGlassSurface(
      key: const Key('sillytavern-import-preview'),
      strong: true,
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreviewImage(bytes: inspection.imageBytes, name: asset.displayName),
          const SizedBox(width: AppTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_formatLabel(asset)),
                const SizedBox(height: AppTokens.spacingS),
                Text(_kindDescription(asset.kind)),
                if (inspection.isDuplicate) ...[
                  const SizedBox(height: AppTokens.spacingS),
                  Text(
                    '这个资产已经导入。默认不会创建重复副本。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetSummary extends StatelessWidget {
  const _AssetSummary({required this.inspection});

  final SillyTavernImportInspection inspection;

  @override
  Widget build(BuildContext context) {
    final asset = inspection.asset;
    final card = asset.characterCard;
    final loreEntries =
        card?.characterBook?.entries ?? asset.lorebook?.entries ?? const [];
    final rows = <String>[
      if (card != null) '角色设定',
      if (card?.firstMessage.isNotEmpty == true) '开场白 1',
      if (card?.alternateGreetings.isNotEmpty == true)
        '备用开场白 ${card!.alternateGreetings.length}',
      if (card?.exampleMessages.isNotEmpty == true) '示例对话',
      if (loreEntries.isNotEmpty) '世界书条目 ${loreEntries.length}',
      if (card?.systemPrompt.isNotEmpty == true ||
          card?.postHistoryInstructions.isNotEmpty == true)
        '角色 Prompt 信息',
      if (asset.persona != null) '我的角色描述',
      if (asset.promptPreset != null) 'Prompt / Preset 信息',
    ];
    return IbukiGlassSurface(
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将导入', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spacingS),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(row)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CompatibilitySections extends StatelessWidget {
  const _CompatibilitySections({required this.inspection});

  final SillyTavernImportInspection inspection;

  @override
  Widget build(BuildContext context) {
    final asset = inspection.asset;
    return IbukiGlassSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ExpansionTile(
            title: const Text('Prompt 映射'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [Text(_promptSummary(asset), textAlign: TextAlign.left)],
          ),
          ExpansionTile(
            title: Text('Extensions ${asset.extensionSummaries.length}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (asset.extensionSummaries.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('没有扩展字段。'),
                )
              else
                for (final extension in asset.extensionSummaries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(extension.key),
                    subtitle: Text(
                      '${extension.kind.name} · ${extension.encodedChars} 字符',
                    ),
                  ),
              if (asset.security.scriptLikePaths.isNotEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('这些扩展会被保存，但不会自动运行。'),
                ),
            ],
          ),
          ExpansionTile(
            title: const Text('安全与兼容'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final warning in asset.warnings)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $warning'),
                  ),
                ),
              if (asset.unsupportedPayload.isNotEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('不支持字段将安全保存，供未来重新映射。'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectSelector extends StatelessWidget {
  const _ProjectSelector({
    required this.projects,
    required this.value,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('sillytavern-project-target'),
      initialValue: value,
      decoration: const InputDecoration(labelText: '角色所属项目'),
      items: [
        for (final project in projects)
          DropdownMenuItem(value: project.id, child: Text(project.title)),
      ],
      onChanged: onChanged,
    );
  }
}

class _WorldSelector extends StatelessWidget {
  const _WorldSelector({
    required this.worlds,
    required this.value,
    required this.onChanged,
  });

  final List<RoleplayWorld> worlds;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('sillytavern-world-target'),
      initialValue: value,
      decoration: const InputDecoration(labelText: '故事世界'),
      items: [
        for (final world in worlds)
          DropdownMenuItem(value: world.id, child: Text(world.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _WorldBookSelector extends ConsumerWidget {
  const _WorldBookSelector({
    required this.worldId,
    required this.value,
    required this.onChanged,
  });

  final String worldId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(worldBookListProvider(worldId)).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spacingS),
      child: DropdownButtonFormField<String>(
        key: const Key('sillytavern-world-book-target'),
        initialValue: _validSelection(value, books.map((item) => item.id)),
        decoration: const InputDecoration(labelText: '已有世界书'),
        items: [
          for (final book in books)
            DropdownMenuItem(value: book.id, child: Text(book.name)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _WorldSessionSelector extends ConsumerWidget {
  const _WorldSessionSelector({
    required this.worldId,
    required this.value,
    required this.onChanged,
  });

  final String worldId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(worldSessionListProvider(worldId)).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spacingS),
      child: DropdownButtonFormField<String?>(
        key: const Key('sillytavern-world-session-target'),
        initialValue: _validSelection(value, sessions.map((item) => item.id)),
        decoration: const InputDecoration(labelText: '当前故事补充指令（可选）'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('仅世界提示词')),
          for (final session in sessions)
            DropdownMenuItem<String?>(
              value: session.id,
              child: Text(session.name),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.bytes, required this.name});

  final Uint8List? bytes;
  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 76,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: bytes == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Center(
                  child: Text(
                    name.characters.firstOrNull ?? '?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              )
            : Image.memory(bytes!, fit: BoxFit.contain, cacheWidth: 256),
      ),
    );
  }
}

class _PayloadExpansion extends StatelessWidget {
  const _PayloadExpansion({required this.title, required this.values});

  final String title;
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('$title (${values.length})'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (values.isEmpty)
          const Text('无')
        else
          SelectableText(_safeSummary(values)),
      ],
    );
  }
}

class _StringExpansion extends StatelessWidget {
  const _StringExpansion({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('$title (${values.length})'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (values.isEmpty)
          const Text('无')
        else
          for (final value in values) Text('• $value'),
      ],
    );
  }
}

Widget _detailRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 112, child: Text(label)),
      Expanded(child: SelectableText(value.isEmpty ? '未提供' : value)),
    ],
  ),
);

String _formatLabel(SillyTavernParsedAsset asset) => switch (asset.kind) {
  SillyTavernAssetKind.characterCard =>
    'SillyTavern Character Card ${asset.sourceVersion}',
  SillyTavernAssetKind.lorebook => 'SillyTavern World Info',
  SillyTavernAssetKind.persona => 'SillyTavern Persona',
  SillyTavernAssetKind.promptPreset => 'SillyTavern Prompt / Preset',
};

String _kindDescription(SillyTavernAssetKind kind) => switch (kind) {
  SillyTavernAssetKind.characterCard => '这是故事中由 AI 扮演的角色。',
  SillyTavernAssetKind.lorebook => '这是一份故事世界设定。',
  SillyTavernAssetKind.persona => '这是你在故事中扮演的角色。',
  SillyTavernAssetKind.promptPreset => '这些内容可以映射到世界提示词。',
};

String _kindName(SillyTavernAssetKind kind) => switch (kind) {
  SillyTavernAssetKind.characterCard => '角色卡',
  SillyTavernAssetKind.lorebook => '世界书',
  SillyTavernAssetKind.persona => '我的角色',
  SillyTavernAssetKind.promptPreset => 'Prompt / Preset',
};

String _importButtonLabel(SillyTavernAssetKind kind) => switch (kind) {
  SillyTavernAssetKind.characterCard => '导入角色',
  SillyTavernAssetKind.lorebook => '导入世界书',
  SillyTavernAssetKind.persona => '导入我的角色',
  SillyTavernAssetKind.promptPreset => '保存兼容信息',
};

String _promptSummary(SillyTavernParsedAsset asset) {
  final card = asset.characterCard;
  if (card != null) {
    return [
      if (card.systemPrompt.isNotEmpty) 'Character System Prompt → 角色专属提示层',
      if (card.postHistoryInstructions.isNotEmpty)
        'Post-History Instructions → 角色后置指令',
      if (card.exampleMessages.isNotEmpty) 'Example Messages → 角色说话样例',
      if (card.systemPrompt.isEmpty &&
          card.postHistoryInstructions.isEmpty &&
          card.exampleMessages.isEmpty)
        '没有需要映射的 Prompt 字段。',
    ].join('\n');
  }
  if (asset.promptPreset != null) {
    return 'Main/System Prompt → World System Prompt candidate\n'
        "Author's Note / Post-History → 当前故事补充指令 candidate\n"
        '默认不覆盖任何现有提示词。';
  }
  return '此资产没有 Prompt 映射。';
}

String _safeSummary(Map<String, Object?> values) {
  final lines = <String>[];
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) {
      lines.add(
        '${entry.key}: ${value.length > 240 ? '${value.substring(0, 240)}…' : value}',
      );
    } else if (value is List) {
      lines.add('${entry.key}: List × ${value.length}');
    } else if (value is Map) {
      lines.add('${entry.key}: Object × ${value.length}');
    } else {
      lines.add('${entry.key}: $value');
    }
  }
  return lines.join('\n');
}

String _friendlyError(Object error) {
  if (error is SillyTavernParseException) return error.message;
  return error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
}

String? _validSelection(String? value, Iterable<String> values) {
  if (value == null) return null;
  return values.contains(value) ? value : null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
