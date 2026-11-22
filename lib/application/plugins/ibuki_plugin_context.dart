import '../../domain/plugins/installed_plugin.dart';
import 'ibuki_chat_api.dart';
import 'ibuki_hook_bus.dart';
import 'ibuki_plugin_ai.dart';
import 'ibuki_plugin_creative_api.dart';
import 'plugin_storage.dart';

class IbukiPluginContext {
  const IbukiPluginContext({
    required this.plugin,
    required this.currentRoute,
    required this.currentSessionId,
    required this.currentProjectId,
    required this.storage,
    required this.hooks,
    required this.chat,
    this.ai,
    this.prompt,
    this.scope,
    this.settings,
  });

  final InstalledPlugin plugin;
  final String currentRoute;
  final String? currentSessionId;
  final String? currentProjectId;
  final PluginStorage storage;
  final IbukiHookBus hooks;
  final IbukiChatApi chat;
  final IbukiPluginAi? ai;
  final IbukiPluginPromptApi? prompt;
  final IbukiPluginScopeApi? scope;
  final IbukiPluginSettingsApi? settings;

  Map<String, Object?> safeMetadata() => {
    'plugin': {
      'id': plugin.id,
      'name': plugin.manifest.name,
      'version': plugin.manifest.version,
    },
    'route': currentRoute,
    'sessionId': currentSessionId,
    'projectId': currentProjectId,
  };
}
