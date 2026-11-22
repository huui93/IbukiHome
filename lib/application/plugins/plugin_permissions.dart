import '../../core/errors/plugin_exceptions.dart';
import '../../domain/plugins/ibuki_plugin_manifest.dart';

abstract final class PluginPermissions {
  static const chatRead = 'chat.read';
  static const characterRead = 'character.read';
  static const storagePrivate = 'storage.private';
  static const uiExtend = 'ui.extend';
  static const aiGenerate = 'ai.generate';
  static const aiPromptModify = 'ai.prompt.modify';
  static const network = 'network';
}

class PluginPermissionGuard {
  const PluginPermissionGuard(this.manifest);

  final IbukiPluginManifest manifest;

  bool allows(String permission) => manifest.permissions.contains(permission);

  void require(String permission) {
    if (allows(permission)) return;
    throw PluginException(
      PluginErrorCategory.permissionDenied,
      '插件没有权限执行此操作。',
      detail: 'missingPermission=$permission',
    );
  }
}
