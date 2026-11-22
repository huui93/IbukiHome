import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../application/plugins/ibuki_chat_api.dart';
import '../../../application/plugins/ibuki_plugin_context.dart';
import '../../../application/plugins/ibuki_plugin_creative_api.dart';
import '../../../application/plugins/ibuki_web_plugin_bridge.dart';
import '../../../application/plugins/plugin_contributions.dart';
import '../../../application/plugins/plugin_permissions.dart';
import '../../../application/plugins/plugin_providers.dart';
import '../../../application/plugins/plugin_storage.dart';
import '../../../application/plugins/plugin_creative_state.dart';
import '../../../application/plugins/plugin_web_bundle.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../core/errors/plugin_exceptions.dart';

class PluginWebPanelPage extends ConsumerStatefulWidget {
  const PluginWebPanelPage({
    required this.contribution,
    required this.sessionId,
    super.key,
  });

  final PluginUiContribution contribution;
  final String sessionId;

  @override
  ConsumerState<PluginWebPanelPage> createState() => _PluginWebPanelPageState();
}

class _PluginWebPanelPageState extends ConsumerState<PluginWebPanelPage> {
  WebViewController? _controller;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final manager = ref.read(pluginManagerProvider);
      final plugin = await manager.getPlugin(widget.contribution.pluginId);
      if (plugin == null || !plugin.enabled || plugin.isBroken) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '插件当前不可用。',
        );
      }
      PluginPermissionGuard(
        plugin.manifest,
      ).require(PluginPermissions.uiExtend);
      final session = await ref
          .read(chatRepositoryProvider)
          .getSession(widget.sessionId);
      final context = IbukiPluginContext(
        plugin: plugin,
        currentRoute: '/chat/${widget.sessionId}',
        currentSessionId: widget.sessionId,
        currentProjectId: session.projectId,
        storage: PluginStorage(
          pluginId: plugin.id,
          repository: ref.read(pluginStorageRepositoryProvider),
        ),
        hooks: ref.read(ibukiHookBusProvider),
        chat: CoreIbukiChatApi(
          sessionId: widget.sessionId,
          permissions: PluginPermissionGuard(plugin.manifest),
          chats: ref.read(chatRepositoryProvider),
          personas: ref.read(chatPersonaRepositoryProvider),
        ),
        ai: ref.read(ibukiPluginAiProvider),
        prompt: IbukiPluginPromptApi(plugin),
        scope: IbukiPluginScopeApi(
          plugin: plugin,
          currentScope: PluginScopeRef.chatSession(widget.sessionId),
          states: ref.read(pluginCreativeStateStoreProvider),
        ),
        settings: IbukiPluginSettingsApi(
          plugin: plugin,
          currentScope: PluginScopeRef.chatSession(widget.sessionId),
          states: ref.read(pluginCreativeStateStoreProvider),
        ),
      );
      final bridge = IbukiWebPluginBridge(
        context: context,
        logger: ref.read(pluginBridgeLoggerProvider),
      );
      final bundle = await const PluginWebBundleLoader().load(
        plugin,
        widget.contribution,
      );
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              return PluginWebSecurityPolicy.allowsNavigation(request.url)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame != true || !mounted) return;
              setState(() {
                _error = const PluginException(
                  PluginErrorCategory.pluginRuntimeFailure,
                  '插件界面加载失败。',
                );
                _loading = false;
              });
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
          ),
        )
        ..addJavaScriptChannel(
          'IbukiPluginBridge',
          onMessageReceived: (message) async {
            final response = await bridge.handle(message.message);
            try {
              await controller.runJavaScript(
                'window.ibuki && window.ibuki.__receive(${jsonEncode(jsonDecode(response))});',
              );
            } catch (_) {
              if (mounted) {
                setState(() {
                  _error = const PluginException(
                    PluginErrorCategory.pluginRuntimeFailure,
                    '插件脚本运行异常。',
                  );
                });
              }
            }
          },
        );
      await controller.loadHtmlString(bundle.html);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _disablePlugin() async {
    try {
      await ref
          .read(pluginManagerProvider)
          .disablePlugin(widget.contribution.pluginId);
      ref.invalidate(installedPluginsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('插件停用失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('plugin-panel-${widget.contribution.pluginId}'),
      appBar: AppBar(title: Text(widget.contribution.label)),
      body: Stack(
        children: [
          if (_controller != null && _error == null)
            WebViewWidget(controller: _controller!),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.extension_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      '${widget.contribution.label} 插件运行异常',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const Key('disable-failed-plugin'),
                      onPressed: _disablePlugin,
                      child: const Text('停用插件'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading && _error == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
