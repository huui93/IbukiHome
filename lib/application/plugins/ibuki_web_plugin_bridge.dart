import 'dart:convert';

import '../../core/errors/plugin_exceptions.dart';
import 'ibuki_plugin_context.dart';
import 'plugin_permissions.dart';
import 'plugin_creative_state.dart';

class IbukiWebPluginBridge {
  IbukiWebPluginBridge({
    required this.context,
    this.logger = const NoopPluginBridgeLogger(),
  }) : _permissions = PluginPermissionGuard(context.plugin.manifest);

  final IbukiPluginContext context;
  final PluginBridgeLogger logger;
  final PluginPermissionGuard _permissions;

  static const Set<String> allowedMethods = {
    'context.get',
    'plugin.getMetadata',
    'chat.getCurrentSession',
    'chat.getMessages',
    'chat.getRecentMessages',
    'storage.get',
    'storage.set',
    'storage.remove',
    'storage.clear',
    'ai.generate',
  };

  Future<String> handle(String source) async {
    String requestId = '';
    String methodName = 'unknown';
    String? errorCode;
    var success = false;
    final stopwatch = Stopwatch()..start();
    try {
      if (source.length > 64 * 1024) {
        throw const _BridgeProtocolException(
          'request_too_large',
          'Bridge 请求过大。',
        );
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const _BridgeProtocolException(
          'invalid_request',
          'Bridge 请求必须是 JSON 对象。',
        );
      }
      requestId = _requiredRequestId(decoded['requestId']);
      final method = decoded['method'];
      if (method is String) methodName = method;
      if (method is! String || !allowedMethods.contains(method)) {
        throw const _BridgeProtocolException('unknown_method', '插件请求了不支持的方法。');
      }
      final rawParams = decoded['params'];
      if (rawParams != null && rawParams is! Map<String, dynamic>) {
        throw const _BridgeProtocolException(
          'invalid_arguments',
          'Bridge params 必须是 JSON 对象。',
        );
      }
      final params = rawParams as Map<String, dynamic>? ?? const {};
      if (params.containsKey('pluginId')) {
        throw const _BridgeProtocolException(
          'identity_mismatch',
          'Bridge 身份由 Host 绑定，不能由插件参数指定。',
        );
      }
      final result = await _invoke(method, params);
      success = true;
      return jsonEncode({'requestId': requestId, 'result': result});
    } on _BridgeProtocolException catch (error) {
      errorCode = error.code;
      return _errorResponse(requestId, error.code, error.message);
    } on PluginException catch (error) {
      errorCode = error.category == PluginErrorCategory.permissionDenied
          ? 'permission_denied'
          : error.category == PluginErrorCategory.storageFailure
          ? 'storage_error'
          : error.category == PluginErrorCategory.aiRequestBusy
          ? 'ai_request_busy'
          : error.category == PluginErrorCategory.aiRequestTimeout
          ? 'ai_request_timeout'
          : error.category == PluginErrorCategory.pluginRuntimeFailure
          ? 'plugin_ai_error'
          : 'invalid_request';
      return _errorResponse(requestId, errorCode, error.message);
    } on FormatException {
      errorCode = 'invalid_json';
      return _errorResponse(requestId, errorCode, 'Bridge 请求不是有效 JSON。');
    } on ArgumentError catch (error) {
      errorCode = 'invalid_arguments';
      return _errorResponse(
        requestId,
        errorCode,
        error.message?.toString() ?? '参数无效。',
      );
    } catch (_) {
      errorCode = 'host_error';
      return _errorResponse(requestId, errorCode, '插件请求没有完成。');
    } finally {
      stopwatch.stop();
      try {
        logger.record(
          PluginBridgeLogEntry(
            pluginId: context.plugin.id,
            method: methodName,
            success: success,
            duration: stopwatch.elapsed,
            errorCode: errorCode,
          ),
        );
      } catch (_) {
        // Diagnostics must never affect a plugin call.
      }
    }
  }

  Future<Object?> _invoke(String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'context.get':
        final result = Map<String, Object?>.from(context.safeMetadata());
        if (_permissions.allows(PluginPermissions.characterRead)) {
          result['character'] = (await context.chat.getSafeCharacterContext())
              ?.toJson();
        }
        return result;
      case 'plugin.getMetadata':
        return context.plugin.manifest.toJson();
      case 'chat.getCurrentSession':
        _permissions.require(PluginPermissions.chatRead);
        return (await context.chat.getCurrentSession())?.toJson();
      case 'chat.getMessages':
        _permissions.require(PluginPermissions.chatRead);
        return (await context.chat.getMessages())
            .map((item) => item.toJson())
            .toList();
      case 'chat.getRecentMessages':
        _permissions.require(PluginPermissions.chatRead);
        final limit = params['limit'] ?? 30;
        if (limit is! int) throw ArgumentError('limit 必须是整数。');
        return (await context.chat.getRecentMessages(
          limit: limit,
        )).map((item) => item.toJson()).toList();
      case 'storage.get':
        _permissions.require(PluginPermissions.storagePrivate);
        return context.storage.get(_requiredKey(params));
      case 'storage.set':
        _permissions.require(PluginPermissions.storagePrivate);
        if (!params.containsKey('value')) {
          throw ArgumentError('缺少 value。');
        }
        await context.storage.set(_requiredKey(params), params['value']);
        return const {'saved': true};
      case 'storage.remove':
        _permissions.require(PluginPermissions.storagePrivate);
        await context.storage.remove(_requiredKey(params));
        return const {'removed': true};
      case 'storage.clear':
        _permissions.require(PluginPermissions.storagePrivate);
        await context.storage.clear();
        return const {'cleared': true};
      case 'ai.generate':
        _permissions.require(PluginPermissions.aiGenerate);
        final ai = context.ai;
        if (ai == null) {
          throw const PluginException(
            PluginErrorCategory.pluginRuntimeFailure,
            '当前页面没有可用的插件 AI Host。',
          );
        }
        final prompt = params['prompt'];
        if (prompt is! String || prompt.trim().isEmpty) {
          throw ArgumentError('prompt 不能为空。');
        }
        final systemPrompt = params['systemPrompt'];
        if (systemPrompt != null && systemPrompt is! String) {
          throw ArgumentError('systemPrompt 必须是字符串。');
        }
        final maxTokens = params['maxOutputTokens'] ?? 1024;
        if (maxTokens is! int) {
          throw ArgumentError('maxOutputTokens 必须是整数。');
        }
        final scope = context.currentSessionId != null
            ? PluginScopeRef.chatSession(context.currentSessionId!)
            : context.currentProjectId != null
            ? PluginScopeRef.project(context.currentProjectId!)
            : const PluginScopeRef.global();
        final result = await ai.generate(
          plugin: context.plugin,
          scope: scope,
          prompt: prompt,
          systemPrompt:
              systemPrompt as String? ?? '你正在响应一个经过用户授权的伊吹之家插件请求。只返回请求所需的结果。',
          maxOutputTokens: maxTokens,
        );
        return result.toSafeJson();
    }
    throw StateError('Unreachable bridge method.');
  }

  static String _requiredRequestId(Object? value) {
    if (value is! String || value.isEmpty || value.length > 100) {
      throw const _BridgeProtocolException(
        'invalid_request_id',
        'Bridge requestId 无效。',
      );
    }
    return value;
  }

  static String _requiredKey(Map<String, dynamic> params) {
    final key = params['key'];
    if (key is! String || key.isEmpty) throw ArgumentError('缺少 storage key。');
    return key;
  }

  static String _errorResponse(String requestId, String code, String message) {
    return jsonEncode({
      'requestId': requestId,
      'error': {'code': code, 'message': message},
    });
  }
}

class PluginBridgeLogEntry {
  const PluginBridgeLogEntry({
    required this.pluginId,
    required this.method,
    required this.success,
    required this.duration,
    this.errorCode,
  });

  final String pluginId;
  final String method;
  final bool success;
  final Duration duration;
  final String? errorCode;
}

abstract class PluginBridgeLogger {
  void record(PluginBridgeLogEntry entry);
}

class NoopPluginBridgeLogger implements PluginBridgeLogger {
  const NoopPluginBridgeLogger();

  @override
  void record(PluginBridgeLogEntry entry) {}
}

class RollingPluginBridgeLogger implements PluginBridgeLogger {
  RollingPluginBridgeLogger({this.maxEntries = 200});

  final int maxEntries;
  final List<PluginBridgeLogEntry> _entries = [];

  List<PluginBridgeLogEntry> get entries => List.unmodifiable(_entries);

  @override
  void record(PluginBridgeLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }
}

class _BridgeProtocolException implements Exception {
  const _BridgeProtocolException(this.code, this.message);

  final String code;
  final String message;
}
