import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import 'novel_prompt_compiler.dart';

class NovelPluginBundle {
  const NovelPluginBundle({
    required this.preset,
    required this.resources,
    required this.options,
  });
  final NovelPluginPreset preset;
  final Map<String, String> resources;
  final Map<String, Object?> options;
}

class NovelPluginBundleLoader {
  const NovelPluginBundleLoader({this.maxTextBytes = 2 * 1024 * 1024});
  final int maxTextBytes;
  static bool supports(InstalledPlugin plugin) =>
      plugin.manifest.extensionApiVersion >= 2 &&
      plugin.manifest.capabilities.contains('novel-host-v2');
  Future<NovelPluginBundle> load(InstalledPlugin plugin) async {
    if (!supports(plugin)) {
      throw const NovelPluginRequestException('此插件没有小说宿主 v2 声明。');
    }
    final options = Map<String, Object?>.from(
      plugin.manifest.contributions['novel'] as Map? ?? const {},
    );
    final root = await Directory(plugin.installedPath).resolveSymbolicLinks();
    var total = 0;
    Future<String> read(String name) async {
      if (!RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(name) ||
          name.startsWith('/') ||
          name
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..')) {
        throw const NovelPluginRequestException('小说插件资源路径无效。');
      }
      final file = File(p.join(root, name));
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw const NovelPluginRequestException('小说插件资源不能位于安装目录之外。');
      }
      final length = await file.length();
      total += length;
      if (total > maxTextBytes) {
        throw const NovelPluginRequestException('小说插件的提示词文本资源过大。');
      }
      return file.readAsString(encoding: utf8);
    }

    final definition = NovelPluginPreset.fromJson(
      Map<String, Object?>.from(
        jsonDecode(await read(options['preset'] as String? ?? 'preset.json'))
            as Map,
      ),
    );
    final resources = <String, String>{};
    for (final name
        in definition.entries
            .map((e) => e.resource)
            .whereType<String>()
            .toSet()) {
      resources[name] = await read(name);
    }
    return NovelPluginBundle(
      preset: definition,
      resources: Map.unmodifiable(resources),
      options: Map.unmodifiable(options),
    );
  }
}
