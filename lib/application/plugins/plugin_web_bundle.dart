import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/plugin_exceptions.dart';
import '../../domain/plugins/installed_plugin.dart';
import 'plugin_contributions.dart';

class PluginWebBundle {
  const PluginWebBundle({required this.html});

  final String html;
}

class PluginWebBundleLoader {
  const PluginWebBundleLoader({this.maxAssetBytes = 2 * 1024 * 1024});

  final int maxAssetBytes;

  Future<PluginWebBundle> load(
    InstalledPlugin plugin,
    PluginUiContribution contribution,
  ) async {
    final html = await _read(plugin, contribution.entry);
    final style = contribution.style == null
        ? ''
        : await _read(plugin, contribution.style!);
    final script = contribution.script == null
        ? ''
        : await _read(plugin, contribution.script!);
    final secured = _applySecurityPolicy(html);
    return PluginWebBundle(
      html: secured
          .replaceFirst('<!-- IBUKI_PLUGIN_STYLE -->', '<style>$style</style>')
          .replaceFirst(
            '<!-- IBUKI_PLUGIN_SCRIPT -->',
            '<script>${_bridgeBootstrap()}\n'
                'try { (() => { $script\n})(); } catch (_) {'
                'document.body.innerHTML = '
                '\'<main style="padding:24px;font-family:system-ui">'
                '<h2>插件运行异常</h2><p>请关闭此页面并停用插件。</p></main>\';'
                '}</script>',
          ),
    );
  }

  Future<String> _read(InstalledPlugin plugin, String relativePath) async {
    final root = p.normalize(p.absolute(plugin.installedPath));
    final resolved = p.normalize(p.absolute(p.join(root, relativePath)));
    if (resolved != root && !p.isWithin(root, resolved)) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件界面资源路径越界。',
      );
    }
    final file = File(resolved);
    if (!await file.exists()) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件界面资源缺失。',
      );
    }
    final length = await file.length();
    if (length > maxAssetBytes) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件界面资源过大。',
      );
    }
    return file.readAsString();
  }

  static String _applySecurityPolicy(String html) {
    const csp =
        '<meta http-equiv="Content-Security-Policy" '
        'content="default-src \'none\'; img-src data:; '
        'style-src \'unsafe-inline\'; script-src \'unsafe-inline\'; '
        'connect-src \'none\'; frame-src \'none\'; media-src \'none\'; '
        'object-src \'none\'; form-action \'none\'; base-uri \'none\'">';
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>$csp');
    }
    return '$csp$html';
  }

  static String _bridgeBootstrap() => r'''
(() => {
  const pending = new Map();
  let sequence = 0;
  function request(method, params = {}) {
    const requestId = `ibuki-${Date.now()}-${++sequence}`;
    return new Promise((resolve, reject) => {
      pending.set(requestId, { resolve, reject });
      IbukiPluginBridge.postMessage(JSON.stringify({ requestId, method, params }));
    });
  }
  window.ibuki = Object.freeze({
    context: Object.freeze({ get: () => request('context.get') }),
    plugin: Object.freeze({ getMetadata: () => request('plugin.getMetadata') }),
    chat: Object.freeze({
      getCurrentSession: () => request('chat.getCurrentSession'),
      getMessages: () => request('chat.getMessages'),
      getRecentMessages: (limit = 30) => request('chat.getRecentMessages', { limit }),
      getCurrentCharacter: async () => (await request('context.get')).character ?? null
    }),
    storage: Object.freeze({
      get: (key) => request('storage.get', { key }),
      set: (key, value) => request('storage.set', { key, value }),
      remove: (key) => request('storage.remove', { key }),
      clear: () => request('storage.clear')
    }),
    ai: Object.freeze({
      generate: (prompt, options = {}) => request('ai.generate', {
        prompt,
        systemPrompt: options.systemPrompt,
        maxOutputTokens: options.maxOutputTokens
      })
    }),
    __receive: (response) => {
      const slot = pending.get(response.requestId);
      if (!slot) return;
      pending.delete(response.requestId);
      if (response.error) slot.reject(new Error(response.error.message));
      else slot.resolve(response.result);
    }
  });
  window.open = () => null;
})();
''';
}

abstract final class PluginWebSecurityPolicy {
  static bool allowsNavigation(String url) {
    final uri = Uri.tryParse(url);
    return url == 'about:blank' || uri?.scheme == 'data';
  }
}
