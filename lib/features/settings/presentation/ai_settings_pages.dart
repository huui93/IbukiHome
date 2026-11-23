import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/ibuki_buttons.dart';
import '../../../app/widgets/ibuki_text_field.dart';
import '../../../application/ai/ai_settings_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../core/network/ai_provider_exceptions.dart';
import '../../../data/ai/ai_provider_client.dart';
import '../../../domain/ai/ai_provider_config.dart';
import '../../../domain/ai/ai_provider_type.dart';
import '../../../app/localization/app_localizations.dart';

class AiSettingsPage extends ConsumerWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(aiSettingsControllerProvider);
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _AiSettingsError(
        onRetry: () => ref.invalidate(aiSettingsControllerProvider),
      ),
      data: (state) {
        final selected = state.defaultSelection;
        final config = selected == null
            ? null
            : state.configById(selected.providerId);
        final subtitle = config == null || selected == null
            ? '尚未配置 AI'
            : '${config.displayName} · ${selected.modelId}';
        return ListView(
          key: const Key('ai-settings-page'),
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingS),
          children: [
            _SectionLabel(context.tr("默认 AI")),
            ListTile(
              key: const Key('default-ai-row'),
              leading: const _ProviderMark(label: 'AI'),
              title: Text(context.tr("默认 Provider 与模型")),
              subtitle: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _chooseDefault(context, ref, state),
            ),
            const Divider(indent: 70, endIndent: 16),
            _SectionLabel(context.tr("配置")),
            ListTile(
              key: const Key('api-provider-list-entry'),
              leading: const _ProviderMark(
                label: 'API',
                icon: Icons.key_rounded,
              ),
              title: Text(context.tr("API 配置")),
              subtitle: Text(context.tr("管理 Provider、模型与连接状态")),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.aiProviders),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spacingM,
                AppTokens.spacingL,
                AppTokens.spacingM,
                0,
              ),
              child: Text(
                context.tr("各模式共用模型与 API 配置，人格、记忆和内容分别管理。"),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.ibukiColors.textMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _chooseDefault(
    BuildContext context,
    WidgetRef ref,
    AiSettingsState state,
  ) async {
    final candidates = state.configs
        .where(
          (config) =>
              config.connectionStatus == AiProviderConnectionStatus.connected &&
              state.isConfigured(config),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr("请先配置并测试一个 Provider。"))),
      );
      await context.push(AppRoutes.aiProviders);
      return;
    }
    final selection =
        await showModalBottomSheet<({String providerId, String modelId})>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              key: const Key('default-ai-picker'),
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(context.tr("选择默认 AI")),
                  subtitle: Text(context.tr("只显示已经连接测试成功的配置")),
                ),
                for (final config in candidates)
                  ListTile(
                    leading: _ProviderMark(label: config.type.shortLabel),
                    title: Text(config.displayName),
                    subtitle: Text(
                      config.selectedModel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, (
                      providerId: config.id,
                      modelId: config.selectedModel,
                    )),
                  ),
              ],
            ),
          ),
        );
    if (selection == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(aiSettingsControllerProvider.notifier)
          .setDefault(selection.providerId, selection.modelId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr("默认 AI 已保存。"))));
      }
    } on AiProviderException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class AiProviderListPage extends ConsumerWidget {
  const AiProviderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(aiSettingsControllerProvider);
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _AiSettingsError(
        onRetry: () => ref.invalidate(aiSettingsControllerProvider),
      ),
      data: (state) {
        final builtIns = state.configs
            .where((config) => !config.isCustom)
            .toList(growable: false);
        final customs = state.configs
            .where((config) => config.isCustom)
            .toList(growable: false);
        return ListView(
          key: const Key('ai-provider-list-page'),
          padding: const EdgeInsets.only(bottom: AppTokens.spacingL),
          children: [
            _SectionLabel(context.tr("官方 Provider")),
            for (final config in builtIns)
              _ProviderRow(config: config, state: state),
            const Divider(indent: 70, endIndent: 16),
            _SectionLabel(
              context.tr("自定义 · {count} 个", {"count": customs.length}),
            ),
            for (final config in customs)
              _ProviderRow(config: config, state: state),
            ListTile(
              key: const Key('add-custom-provider'),
              leading: const _ProviderMark(label: '+', icon: Icons.add_rounded),
              title: Text(context.tr("添加自定义 API")),
              subtitle: Text(context.tr("OpenAI Compatible，可不填写 API Key")),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.newCustomAiProvider),
            ),
          ],
        );
      },
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.config, required this.state});

  final AiProviderConfig config;
  final AiSettingsState state;

  @override
  Widget build(BuildContext context) {
    final status = _providerStatus(config, state);
    return ListTile(
      key: Key('provider-row-${config.id}'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spacingM,
        vertical: 3,
      ),
      leading: _ProviderMark(label: config.type.shortLabel),
      title: Text(
        config.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          _StatusDot(status: status.status),
          const SizedBox(width: AppTokens.spacingXs),
          Expanded(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(AppRoutes.aiProvider(config.id)),
    );
  }
}

class AiProviderConfigPage extends ConsumerStatefulWidget {
  const AiProviderConfigPage({this.providerId, super.key});

  final String? providerId;

  @override
  ConsumerState<AiProviderConfigPage> createState() =>
      _AiProviderConfigPageState();
}

class _AiProviderConfigPageState extends ConsumerState<AiProviderConfigPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  AiProviderConfig? _draft;
  String? _loadedId;
  bool _ready = false;
  bool _obscureKey = true;
  bool _advancedOpen = false;
  bool _testing = false;
  bool _saving = false;
  String? _statusMessage;
  bool? _statusSuccess;
  AiRequestCancellation? _cancellation;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _apiKeyController = TextEditingController();
    _baseUrlController = TextEditingController();
    _modelController = TextEditingController();
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _apiKeyController.clear();
    _nameController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(aiSettingsControllerProvider);
    return asyncState.when(
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(leading: const BackButton()),
        body: _AiSettingsError(
          onRetry: () => ref.invalidate(aiSettingsControllerProvider),
        ),
      ),
      data: (state) {
        final config = _resolveConfig(state);
        if (config == null) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(leading: const BackButton()),
            body: Center(child: Text(context.tr("没有找到这个 Provider。"))),
          );
        }
        _ensureLoaded(config);
        return Scaffold(
          key: const Key('ai-provider-config-page'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            leading: BackButton(onPressed: () => _goBack(context)),
            title: Text(
              _providerPageTitle(config),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              TextButton(
                key: const Key('save-ai-provider'),
                onPressed: _ready && !_saving && !_testing ? _save : null,
                child: Text(_saving ? context.tr("保存中") : context.tr("保存")),
              ),
            ],
          ),
          body: _ready
              ? _buildForm(config)
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  AiProviderConfig? _resolveConfig(AiSettingsState state) {
    if (widget.providerId != null) {
      return state.configById(widget.providerId!);
    }
    return _draft ??= ref
        .read(aiSettingsControllerProvider.notifier)
        .newCustomConfig(
          id: ref.read(entityIdGeneratorProvider).nextId('ai_custom'),
        );
  }

  void _ensureLoaded(AiProviderConfig config) {
    if (_loadedId == config.id) {
      return;
    }
    _loadedId = config.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      _draft = config;
      _nameController.text = config.displayName;
      _baseUrlController.text = config.baseUrl;
      _modelController.text = config.selectedModel;
      final key = await ref
          .read(aiSettingsControllerProvider.notifier)
          .loadApiKey(config.id);
      if (!mounted) {
        return;
      }
      _apiKeyController.text = key ?? '';
      setState(() => _ready = true);
    });
  }

  Widget _buildForm(AiProviderConfig config) {
    final isCustom = config.isCustom;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spacingM,
          AppTokens.spacingM,
          AppTokens.spacingM,
          AppTokens.spacingL,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Row(
            children: [
              _ProviderMark(label: config.type.shortLabel, large: true),
              const SizedBox(width: AppTokens.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _providerPageTitle(config),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      config.type == AiProviderType.kimi
                          ? context.tr("由 Moonshot AI 提供")
                          : isCustom
                          ? 'OpenAI Compatible'
                          : context.tr("API Key 仅保存在本机安全存储"),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.ibukiColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spacingL),
          if (isCustom) ...[
            IbukiTextField(
              key: const Key('provider-name-field'),
              controller: _nameController,
              label: context.tr("名称"),
              hint: context.tr("例如：我的中转站"),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: AppTokens.spacingM),
          ],
          IbukiTextField(
            key: const Key('provider-api-key-field'),
            controller: _apiKeyController,
            label: isCustom ? context.tr("API Key（可留空）") : 'API Key',
            hint: context.tr("输入后将安全保存在本机"),
            obscureText: _obscureKey,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _markChanged(),
            suffixIcon: IbukiIconButton(
              key: const Key('toggle-api-key-visibility'),
              tooltip: _obscureKey
                  ? context.tr("显示 API Key")
                  : context.tr("隐藏 API Key"),
              icon: _obscureKey
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
          const SizedBox(height: AppTokens.spacingM),
          IbukiTextField(
            key: const Key('provider-model-field'),
            controller: _modelController,
            label: context.tr("模型"),
            hint: context.tr("选择或手动输入模型 ID"),
            textInputAction: TextInputAction.done,
            onChanged: (_) => _markChanged(),
            suffixIcon: IbukiIconButton(
              key: const Key('open-model-picker'),
              tooltip: context.tr("选择模型"),
              icon: Icons.expand_more_rounded,
              onPressed: _openModelPicker,
            ),
          ),
          const SizedBox(height: AppTokens.spacingS),
          Align(
            alignment: Alignment.centerLeft,
            child: IbukiTextAction(
              key: const Key('refresh-provider-models'),
              label: '刷新模型列表',
              icon: Icons.refresh_rounded,
              onPressed: _testing
                  ? null
                  : () => _testConnection(modelsOnly: true),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(context.tr("刷新列表只查询模型；测试连接会发送一条简短请求，可能消耗少量额度。")),
          ),
          const SizedBox(height: AppTokens.spacingS),
          if (isCustom)
            IbukiTextField(
              key: const Key('provider-base-url-field'),
              controller: _baseUrlController,
              label: 'Base URL',
              hint: 'https://example.com/v1',
              keyboardType: TextInputType.url,
              onChanged: (_) => _markChanged(),
            )
          else ...[
            ListTile(
              key: const Key('provider-advanced-settings'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr("高级设置")),
              subtitle: Text(context.tr("官方 Base URL")),
              trailing: Icon(
                _advancedOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            ),
            if (_advancedOpen)
              IbukiTextField(
                key: const Key('provider-base-url-field'),
                controller: _baseUrlController,
                label: 'Base URL',
                keyboardType: TextInputType.url,
                onChanged: (_) => _markChanged(),
              ),
          ],
          const SizedBox(height: AppTokens.spacingM),
          if (_statusMessage != null)
            _ConnectionMessage(
              message: _statusMessage!,
              success: _statusSuccess,
            ),
          const SizedBox(height: AppTokens.spacingM),
          Row(
            children: [
              Expanded(
                child: IbukiSecondaryButton(
                  key: const Key('test-ai-provider'),
                  label: _testing ? context.tr("测试中…") : context.tr("测试连接"),
                  icon: Icons.wifi_tethering_rounded,
                  onPressed: _testing ? null : _testConnection,
                ),
              ),
              if (_testing) ...[
                const SizedBox(width: AppTokens.spacingS),
                IbukiTextAction(
                  key: const Key('cancel-ai-provider-test'),
                  label: '取消',
                  onPressed: _cancelTest,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTokens.spacingL),
          if (isCustom)
            IbukiTextAction(
              key: const Key('delete-custom-provider'),
              label: '删除自定义 Provider',
              icon: Icons.delete_outline_rounded,
              onPressed: widget.providerId == null ? null : _deleteCustom,
            )
          else
            IbukiTextAction(
              key: const Key('clear-official-provider'),
              label: '清除配置',
              icon: Icons.restart_alt_rounded,
              onPressed: _clearOfficial,
            ),
        ],
      ),
    );
  }

  String _providerPageTitle(AiProviderConfig config) {
    if (config.type == AiProviderType.kimi) {
      return 'Kimi';
    }
    final name = config.displayName.trim();
    return name.isEmpty && config.isCustom ? '添加自定义 API' : name;
  }

  void _markChanged() {
    final draft = _draft;
    if (draft == null ||
        draft.connectionStatus == AiProviderConnectionStatus.untested) {
      return;
    }
    setState(() {
      _draft = draft.copyWith(
        connectionStatus: AiProviderConnectionStatus.untested,
        lastVerifiedAtUtc: null,
        verifiedModels: const [],
        incompatibleModels: const [],
      );
      _statusMessage = '配置已修改，请重新测试连接。';
      _statusSuccess = null;
    });
  }

  AiProviderConfig _formDraft() {
    final current = _draft!;
    return current.copyWith(
      displayName: current.isCustom
          ? _nameController.text
          : current.displayName,
      baseUrl: _baseUrlController.text,
      selectedModel: _modelController.text,
    );
  }

  Future<void> _testConnection({bool modelsOnly = false}) async {
    if (_testing) {
      return;
    }
    final cancellation = AiRequestCancellation();
    setState(() {
      _testing = true;
      _cancellation = cancellation;
      _statusMessage = modelsOnly ? '正在读取可用模型…' : '正在验证模型回复…';
      _statusSuccess = null;
    });
    try {
      final controller = ref.read(aiSettingsControllerProvider.notifier);
      final result = modelsOnly
          ? AiProviderTestResult(
              models: await controller.listDraftModels(
                _formDraft(),
                apiKey: _apiKeyController.text,
                cancellation: cancellation,
              ),
              verifiedAtUtc: DateTime.now().toUtc(),
            )
          : await controller.testConnection(
              _formDraft(),
              apiKey: _apiKeyController.text,
              cancellation: cancellation,
            );
      if (!mounted || cancellation.isCancelled) {
        return;
      }
      if (_modelController.text.trim().isEmpty &&
          result.verifiedModel != null) {
        _modelController.text = result.verifiedModel!;
      }
      final currentModel = _modelController.text.trim();
      final verifiedModels = modelsOnly
          ? _draft!.verifiedModels
          : result.verifiedModels;
      final verified =
          verifiedModels.contains(currentModel) &&
          (!modelsOnly ||
              _draft!.connectionStatus == AiProviderConnectionStatus.connected);
      final selectedIncompatible = result.incompatibleModels.contains(
        currentModel,
      );
      setState(() {
        _draft = _formDraft().copyWith(
          connectionStatus: verified
              ? AiProviderConnectionStatus.connected
              : AiProviderConnectionStatus.untested,
          availableModels: result.models,
          verifiedModels: verifiedModels,
          incompatibleModels: result.incompatibleModels,
          lastVerifiedAtUtc: verified
              ? (modelsOnly ? _draft!.lastVerifiedAtUtc : result.verifiedAtUtc)
              : null,
        );
        _statusMessage = selectedIncompatible
            ? '该模型不支持当前生成接口，请重新选择。'
            : verified
            ? modelsOnly
                  ? '已刷新 ${result.models.length} 个模型；保留当前模型的生成验证。'
                  : '连接成功，已用 ${result.verifiedModel} 完成最小生成；读取到 ${result.models.length} 个模型。'
            : '已读取 ${result.models.length} 个模型；请选择或填写模型 ID，再测试回复。';
        _statusSuccess = verified ? true : null;
      });
    } on AiProviderConnectionTestException catch (error) {
      if (!mounted || cancellation.isCancelled) {
        return;
      }
      setState(() {
        _draft = _formDraft().copyWith(
          connectionStatus: AiProviderConnectionStatus.failed,
          availableModels: error.availableModels,
          incompatibleModels: error.incompatibleModels,
        );
        _statusMessage =
            '${error.message} 已读取到 ${error.availableModels.length} 个可生成模型。';
        _statusSuccess = false;
      });
    } on AiProviderException catch (error) {
      if (!mounted || cancellation.isCancelled) {
        return;
      }
      setState(() {
        _draft = _formDraft().copyWith(
          connectionStatus: AiProviderConnectionStatus.failed,
        );
        _statusMessage = error.message;
        _statusSuccess = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
          _cancellation = null;
        });
      }
    }
  }

  void _cancelTest() {
    _cancellation?.cancel();
    if (mounted) {
      setState(() {
        _testing = false;
        _cancellation = null;
        _statusMessage = '连接测试已取消。';
        _statusSuccess = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(aiSettingsControllerProvider.notifier)
          .saveConfig(_formDraft(), apiKey: _apiKeyController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '配置已保存。';
        _statusSuccess = true;
        _obscureKey = true;
      });
      if (widget.providerId == null) {
        context.go(AppRoutes.aiProviders);
      }
    } on AiProviderException catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = error.message;
          _statusSuccess = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openModelPicker() async {
    final models = _draft?.availableModels ?? const <String>[];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AiModelPickerSheet(
        models: models,
        currentModel: _modelController.text,
        incompatibleModels: _draft?.incompatibleModels ?? const [],
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    _modelController.text = selected;
    _markChanged();
  }

  Future<void> _clearOfficial() async {
    if (!await _confirm(
      title: context.tr("清除配置？"),
      message: context.tr("将清除 API Key、模型和测试状态，并恢复官方 Base URL。"),
    )) {
      return;
    }
    await ref
        .read(aiSettingsControllerProvider.notifier)
        .clearOfficialConfig(_draft!.id);
    if (mounted) {
      _loadedId = null;
      _ready = false;
      _apiKeyController.clear();
      setState(() {});
    }
  }

  Future<void> _deleteCustom() async {
    if (!await _confirm(
      title: context.tr("删除自定义 Provider？"),
      message: context.tr("对应的 API Key 也会从安全存储中删除。"),
    )) {
      return;
    }
    await ref
        .read(aiSettingsControllerProvider.notifier)
        .deleteCustomConfig(_draft!.id);
    if (mounted) {
      _apiKeyController.clear();
      context.go(AppRoutes.aiProviders);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr("取消")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr("确认")),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _goBack(BuildContext context) async {
    _apiKeyController.clear();
    if (await Navigator.of(context).maybePop() || !context.mounted) {
      return;
    }
    context.go(AppRoutes.aiProviders);
  }
}

class AiModelPickerSheet extends StatefulWidget {
  const AiModelPickerSheet({
    required this.models,
    required this.currentModel,
    this.incompatibleModels = const [],
    super.key,
  });

  final List<String> models;
  final String currentModel;
  final List<String> incompatibleModels;

  @override
  State<AiModelPickerSheet> createState() => _AiModelPickerSheetState();
}

class _AiModelPickerSheetState extends State<AiModelPickerSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _manualController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _manualController = TextEditingController(text: widget.currentModel);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = widget.models
        .where((model) => model.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spacingM,
          right: AppTokens.spacingM,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppTokens.spacingM,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            key: const Key('model-picker-sheet'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr("选择模型"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTokens.spacingM),
              IbukiTextField(
                key: const Key('model-search-field'),
                controller: _searchController,
                hint: context.tr("搜索模型…"),
                prefixIcon: const Icon(Icons.search_rounded),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppTokens.spacingS),
              Row(
                children: [
                  Expanded(
                    child: IbukiTextField(
                      key: const Key('manual-model-field'),
                      controller: _manualController,
                      hint: context.tr("手动输入模型 ID"),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spacingS),
                  IbukiSecondaryButton(
                    key: const Key('confirm-manual-model'),
                    label: context.tr("使用"),
                    icon: Icons.check_rounded,
                    onPressed: () {
                      final value = _manualController.text.trim();
                      if (value.isNotEmpty) {
                        Navigator.pop(context, value);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spacingS),
              Expanded(
                child: models.isEmpty
                    ? Center(
                        child: Text(
                          widget.models.isEmpty
                              ? context.tr("测试连接后会在这里显示模型，也可以手动输入。")
                              : context.tr("没有匹配的模型。"),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final incompatible = widget.incompatibleModels
                              .contains(model);
                          return ListTile(
                            title: Text(
                              model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: incompatible
                                ? Text(context.tr("不支持当前 Gemini Native 生成接口"))
                                : null,
                            enabled: !incompatible,
                            trailing: model == widget.currentModel
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: incompatible
                                ? null
                                : () => Navigator.pop(context, model),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({required this.label, this.icon, this.large = false});

  final String label;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 52.0 : 40.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.ibukiColors.primarySoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: icon == null
              ? Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spacingM,
        AppTokens.spacingM,
        AppTokens.spacingM,
        AppTokens.spacingXs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.ibukiColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConnectionMessage extends StatelessWidget {
  const _ConnectionMessage({required this.message, required this.success});

  final String message;
  final bool? success;

  @override
  Widget build(BuildContext context) {
    final color = success == true
        ? context.ibukiColors.success
        : success == false
        ? Theme.of(context).colorScheme.error
        : context.ibukiColors.textMuted;
    return Row(
      key: const Key('provider-connection-message'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 8, color: color),
        ),
        const SizedBox(width: AppTokens.spacingS),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AiProviderConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AiProviderConnectionStatus.connected => context.ibukiColors.success,
      AiProviderConnectionStatus.failed => Theme.of(context).colorScheme.error,
      AiProviderConnectionStatus.untested => context.ibukiColors.disabled,
    };
    return Icon(Icons.circle, size: 8, color: color);
  }
}

({String label, AiProviderConnectionStatus status}) _providerStatus(
  AiProviderConfig config,
  AiSettingsState state,
) {
  if (!state.isConfigured(config)) {
    return (
      label: config.selectedModel.isEmpty && !state.hasKey(config)
          ? '未配置'
          : '已配置，尚未测试',
      status: AiProviderConnectionStatus.untested,
    );
  }
  if (config.type == AiProviderType.gemini &&
      config.incompatibleModels.contains(config.selectedModel)) {
    return (
      label: '已连接 · 当前模型不兼容',
      status: AiProviderConnectionStatus.untested,
    );
  }
  return switch (config.connectionStatus) {
    AiProviderConnectionStatus.connected => (
      label: '连接正常 · ${config.selectedModel}',
      status: config.connectionStatus,
    ),
    AiProviderConnectionStatus.failed => (
      label: '连接失败',
      status: config.connectionStatus,
    ),
    AiProviderConnectionStatus.untested => (
      label: '已配置，尚未测试',
      status: config.connectionStatus,
    ),
  };
}

class _AiSettingsError extends StatelessWidget {
  const _AiSettingsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: AppTokens.spacingM),
            Text(context.tr("AI 配置暂时无法读取。")),
            const SizedBox(height: AppTokens.spacingM),
            IbukiSecondaryButton(
              label: context.tr("重试"),
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
