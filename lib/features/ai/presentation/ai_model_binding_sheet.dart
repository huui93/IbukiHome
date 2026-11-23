import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/ai/ai_settings_controller.dart';
import '../../../application/chat/chat_vision_preferences.dart';
import '../../../domain/ai/ai_default_selection.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../application/world_roleplay/world_roleplay_providers.dart';
import '../../../core/network/ai_provider_exceptions.dart';
import '../../../domain/ai/ai_provider_config.dart';
import '../../../domain/ai/ai_provider_type.dart';
import 'ai_ui_helpers.dart';
import '../../../app/localization/app_localizations.dart';

enum AiModelBindingScope { project, chatSession, worldSession, chatVision }

Future<void> showAiModelBindingSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AiModelBindingScope scope,
  required String entityId,
}) async {
  final settings = await ref.read(aiSettingsControllerProvider.future);
  String? providerId;
  String? model;
  switch (scope) {
    case AiModelBindingScope.chatVision:
      try {
        final vision = await ref.read(chatVisionPreferencesProvider.future);
        providerId = vision?.providerId;
        model = vision?.modelId;
      } catch (_) {
        providerId = null;
        model = null;
      }
      break;
    case AiModelBindingScope.project:
      final project = await ref.read(projectByIdProvider(entityId).future);
      providerId = project.aiProviderConfigId;
      model = project.aiModel;
      break;
    case AiModelBindingScope.chatSession:
      final session = await ref.read(chatSessionByIdProvider(entityId).future);
      providerId = session.aiProviderConfigId;
      model = session.aiModel;
      break;
    case AiModelBindingScope.worldSession:
      final session = await ref.read(worldSessionByIdProvider(entityId).future);
      providerId = session.aiProviderConfigId;
      model = session.aiModel;
      break;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AiModelBindingSheet(
      scope: scope,
      entityId: entityId,
      initialSettings: settings,
      initialProviderId: providerId,
      initialModel: model,
    ),
  );
}

class _AiModelBindingSheet extends ConsumerStatefulWidget {
  const _AiModelBindingSheet({
    required this.scope,
    required this.entityId,
    required this.initialSettings,
    required this.initialProviderId,
    required this.initialModel,
  });

  final AiModelBindingScope scope;
  final String entityId;
  final AiSettingsState initialSettings;
  final String? initialProviderId;
  final String? initialModel;

  @override
  ConsumerState<_AiModelBindingSheet> createState() =>
      _AiModelBindingSheetState();
}

class _AiModelBindingSheetState extends ConsumerState<_AiModelBindingSheet> {
  late AiSettingsState _settings;
  late bool _followsDefault;
  String? _providerId;
  late final TextEditingController _modelController;
  var _loadingModels = false;
  var _saving = false;
  String? _modelError;
  String? _saveError;

  List<AiProviderConfig> get _providers => _settings.configs
      .where((config) => config.enabled && config.baseUrl.trim().isNotEmpty)
      .toList(growable: false);

  AiProviderConfig? get _provider => _settings.configById(_providerId ?? '');

  List<String> get _models => _modelsFor(_provider);

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _followsDefault = widget.initialProviderId == null;
    _providerId = widget.initialProviderId;
    if (_providerId == null) {
      final defaultProviderId = _settings.defaultSelection?.providerId;
      _providerId = _settings.configById(defaultProviderId ?? '') != null
          ? defaultProviderId
          : _providers.firstOrNull?.id;
    }
    final initial = widget.initialModel?.trim() ?? '';
    _modelController = TextEditingController(
      text: initial.isNotEmpty ? initial : _preferredModel(_provider),
    )..addListener(_onModelChanged);
  }

  @override
  void dispose() {
    _modelController
      ..removeListener(_onModelChanged)
      ..dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() => _saveError = null);
  }

  @override
  Widget build(BuildContext context) {
    final defaultSelection = _settings.defaultSelection;
    final selectedModel = _modelController.text.trim();
    final dropdownValue = _models.contains(selectedModel)
        ? selectedModel
        : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(switch (widget.scope) {
                AiModelBindingScope.chatVision => '聊天识图模型',
                AiModelBindingScope.project => '本作品使用的 AI',
                AiModelBindingScope.chatSession => '本聊天使用的 AI',
                AiModelBindingScope.worldSession => '本世界存档使用的 AI',
              }, style: Theme.of(context).textTheme.titleLarge),
              RadioGroup<bool>(
                groupValue: _followsDefault,
                onChanged: (value) {
                  if (_saving || value == null) return;
                  setState(() {
                    _followsDefault = value;
                    _saveError = null;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      key: const Key('ai-binding-follow-default'),
                      value: true,
                      title: Text(
                        widget.scope == AiModelBindingScope.chatVision
                            ? context.tr("跟随当前聊天模型")
                            : '跟随默认',
                      ),
                      subtitle: Text(
                        widget.scope == AiModelBindingScope.chatVision
                            ? '每次发送图片时，使用该会话当前选择的模型'
                            : defaultSelection == null
                            ? '尚未配置默认 AI'
                            : '${_settings.configById(defaultSelection.providerId)?.displayName ?? defaultSelection.providerId} · ${defaultSelection.modelId}',
                      ),
                    ),
                    RadioListTile<bool>(
                      key: const Key('ai-binding-override'),
                      value: false,
                      enabled: _providers.isNotEmpty && !_saving,
                      title: const Text('单独选择'),
                    ),
                  ],
                ),
              ),
              if (!_followsDefault) ...[
                DropdownButtonFormField<String>(
                  key: const Key('ai-binding-provider'),
                  initialValue: _providers.any((item) => item.id == _providerId)
                      ? _providerId
                      : null,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: [
                    for (final item in _providers)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.displayName),
                      ),
                  ],
                  onChanged: _saving ? null : _selectProvider,
                ),
                const SizedBox(height: 12),
                if (_loadingModels)
                  Padding(
                    key: const Key('ai-binding-model-loading'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '正在加载 ${_provider?.displayName ?? 'Provider'} 模型…',
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_models.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'ai-binding-model-${_providerId ?? 'none'}',
                      ),
                      initialValue: dropdownValue,
                      decoration: const InputDecoration(labelText: '模型列表'),
                      items: [
                        for (final item in _models)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                _modelController.text = value;
                              }
                            },
                    ),
                  if (_models.isNotEmpty) const SizedBox(height: 10),
                  TextField(
                    key: const Key('ai-binding-manual-model'),
                    controller: _modelController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Model ID',
                      hintText: '也可以手动输入',
                    ),
                  ),
                  if (_modelError != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _modelError!,
                            key: const Key('ai-binding-model-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('retry-ai-binding-models'),
                          onPressed: _refreshModels,
                          child: Text(context.tr("重试")),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _saveError!,
                  key: const Key('ai-binding-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('save-ai-binding'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr("保存")),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectProvider(String? providerId) async {
    if (providerId == null || providerId == _providerId) return;
    setState(() {
      _providerId = providerId;
      _modelController.clear();
      _modelError = null;
      _saveError = null;
    });
    await _refreshModels();
  }

  Future<void> _refreshModels() async {
    final provider = _provider;
    if (provider == null) return;
    if (!_credentialReady(provider)) {
      setState(() {
        _modelError = '${provider.displayName} API Key 未配置，请先到设置中完成配置。';
      });
      return;
    }
    setState(() {
      _loadingModels = true;
      _modelError = null;
    });
    try {
      await ref
          .read(aiSettingsControllerProvider.notifier)
          .refreshModels(provider.id);
      final refreshed = await ref.read(aiSettingsControllerProvider.future);
      if (!mounted || _providerId != provider.id) return;
      setState(() {
        _settings = refreshed;
        final models = _models;
        final preferred = _preferredModel(_provider);
        if (!models.contains(_modelController.text.trim())) {
          _modelController.text = preferred;
        }
      });
    } catch (error) {
      if (!mounted || _providerId != provider.id) return;
      setState(() {
        _modelError = '模型列表获取失败：${friendlyAiError(error)}';
      });
    } finally {
      if (mounted && _providerId == provider.id) {
        setState(() => _loadingModels = false);
      }
    }
  }

  Future<void> _save() async {
    final providerId = _providerId;
    final model = _modelController.text.trim();
    if (!_followsDefault) {
      final provider = _settings.configById(providerId ?? '');
      if (provider == null) {
        setState(() => _saveError = '请选择 Provider。');
        return;
      }
      if (!_credentialReady(provider)) {
        setState(() => _saveError = '${provider.displayName} API Key 未配置。');
        return;
      }
      if (model.isEmpty) {
        setState(() => _saveError = '请选择或输入 Model ID。');
        return;
      }
      if (provider.incompatibleModels.contains(model)) {
        setState(() => _saveError = '该模型不支持当前 Gemini Native 生成接口。');
        return;
      }
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final savedProvider = _followsDefault ? null : providerId;
      final savedModel = _followsDefault ? null : model;
      if (widget.scope == AiModelBindingScope.chatVision) {
        await ref
            .read(chatVisionPreferencesProvider.notifier)
            .setSelection(
              _followsDefault
                  ? null
                  : AiDefaultSelection(
                      providerId: providerId!,
                      modelId: model,
                      updatedAtUtc: ref.read(utcClockProvider).now(),
                    ),
            );
      } else if (widget.scope == AiModelBindingScope.project) {
        await ref.read(saveProjectAiBindingProvider)(
          projectId: widget.entityId,
          providerConfigId: savedProvider,
          model: savedModel,
          nowUtc: ref.read(utcClockProvider).now(),
        );
        final project = await ref
            .read(projectRepositoryProvider)
            .getProject(widget.entityId);
        _verifyPersisted(
          project.aiProviderConfigId,
          project.aiModel,
          savedProvider,
          savedModel,
        );
        if (!_followsDefault) {
          final resolved = await ref
              .read(aiModelResolverProvider)
              .resolveForProject(widget.entityId);
          _verifyResolved(resolved.providerConfigId, resolved.model, model);
        }
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.projects],
        );
      } else if (widget.scope == AiModelBindingScope.chatSession) {
        await ref.read(saveChatSessionAiBindingProvider)(
          sessionId: widget.entityId,
          providerConfigId: savedProvider,
          model: savedModel,
          nowUtc: ref.read(utcClockProvider).now(),
        );
        final session = await ref
            .read(chatRepositoryProvider)
            .getSession(widget.entityId);
        _verifyPersisted(
          session.aiProviderConfigId,
          session.aiModel,
          savedProvider,
          savedModel,
        );
        if (!_followsDefault) {
          final resolved = await ref
              .read(aiModelResolverProvider)
              .resolveForChatSession(widget.entityId);
          _verifyResolved(resolved.providerConfigId, resolved.model, model);
        }
        notifyRepositoryChanged(
          ref,
          areas: const [RepositoryDataArea.chatSessions],
        );
      } else {
        await ref.read(saveWorldSessionAiBindingProvider)(
          sessionId: widget.entityId,
          providerConfigId: savedProvider,
          model: savedModel,
          nowUtc: ref.read(utcClockProvider).now(),
        );
        final session = await ref
            .read(worldRoleplayRepositoryProvider)
            .getSession(widget.entityId);
        _verifyPersisted(
          session.aiProviderConfigId,
          session.aiModel,
          savedProvider,
          savedModel,
        );
        if (!_followsDefault) {
          final resolved = await ref
              .read(aiModelResolverProvider)
              .resolveForWorldSession(widget.entityId);
          _verifyResolved(resolved.providerConfigId, resolved.model, model);
        }
        notifyWorldRoleplayChanged(ref);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saveError = '模型设置保存失败：${friendlyAiError(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _verifyPersisted(
    String? actualProvider,
    String? actualModel,
    String? expectedProvider,
    String? expectedModel,
  ) {
    if (actualProvider != expectedProvider || actualModel != expectedModel) {
      throw const AiProviderValidationException('模型绑定写入后回读不一致。');
    }
  }

  void _verifyResolved(String providerId, String model, String expectedModel) {
    if (providerId != _providerId || model != expectedModel) {
      throw const AiProviderValidationException('模型绑定已保存，但实际解析结果不一致。');
    }
  }

  bool _credentialReady(AiProviderConfig config) =>
      !config.type.requiresApiKey || _settings.hasKey(config);
}

List<String> _modelsFor(AiProviderConfig? config) {
  if (config == null) return const [];
  final available = config.availableModels
      .where((model) => !config.incompatibleModels.contains(model))
      .toSet();
  if (available.isNotEmpty) return available.toList(growable: false);
  return <String>{
        ...config.verifiedModels,
        if (config.selectedModel.trim().isNotEmpty) config.selectedModel.trim(),
      }
      .where((model) => !config.incompatibleModels.contains(model))
      .toList(growable: false);
}

String _preferredModel(AiProviderConfig? config) {
  if (config == null) return '';
  final models = _modelsFor(config);
  final selected = config.selectedModel.trim();
  if (selected.isNotEmpty && models.contains(selected)) return selected;
  return config.verifiedModels.where(models.contains).firstOrNull ??
      models.firstOrNull ??
      '';
}
