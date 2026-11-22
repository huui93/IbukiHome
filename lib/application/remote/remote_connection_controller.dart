import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client_exceptions.dart';
import '../../data/remote/remote_ibuki_api.dart';
import '../providers/remote_connection_providers.dart';
import 'remote_connection_profile.dart';
import 'remote_connection_state.dart';

class RemoteConnectionRequiredException implements Exception {
  const RemoteConnectionRequiredException();
}

class InvalidRemoteAddressException implements Exception {
  const InvalidRemoteAddressException(this.message);

  final String message;
}

final remoteConnectionControllerProvider =
    NotifierProvider<RemoteConnectionController, RemoteConnectionState>(
      RemoteConnectionController.new,
    );

class RemoteConnectionController extends Notifier<RemoteConnectionState> {
  RemoteConnectionProfile? _savedProfile;
  RemoteConnectionProfile? _verifiedProfile;

  @override
  RemoteConnectionState build() {
    return const RemoteConnectionState.disconnected();
  }

  Future<void> loadSavedProfile() async {
    final profile = await ref.read(remoteCredentialStoreProvider).load();
    _savedProfile = profile;
    _verifiedProfile = profile;
    if (profile == null) {
      state = const RemoteConnectionState.disconnected();
      return;
    }
    state = RemoteConnectionState(
      status: RemoteConnectionStatus.connected,
      baseUri: profile.baseUri,
      displayName: profile.displayName,
      lastVerifiedAtUtc: profile.lastVerifiedAtUtc,
      apiVersion: profile.apiVersion,
      message: '已保存连接。进入电脑项目时会按需读取，不会自动同步。',
    );
  }

  Future<bool> testConnection({
    required String address,
    required String token,
  }) {
    return _verify(address: address, token: token, saveOnSuccess: false);
  }

  Future<bool> saveConnection({
    required String address,
    required String token,
  }) {
    return _verify(address: address, token: token, saveOnSuccess: true);
  }

  Future<void> disconnect() async {
    await ref.read(remoteCredentialStoreProvider).delete();
    _savedProfile = null;
    _verifiedProfile = null;
    state = const RemoteConnectionState.disconnected();
  }

  Future<T> withVerifiedApi<T>(
    Future<T> Function(RemoteIbukiApi api) run,
  ) async {
    var profile = _verifiedProfile ?? _savedProfile;
    profile ??= await ref.read(remoteCredentialStoreProvider).load();
    if (profile == null) {
      throw const RemoteConnectionRequiredException();
    }
    _savedProfile = profile;
    _verifiedProfile = profile;
    final api = ref.read(remoteIbukiApiFactoryProvider)(profile);
    try {
      return await run(api);
    } finally {
      api.close();
    }
  }

  Future<bool> _verify({
    required String address,
    required String token,
    required bool saveOnSuccess,
  }) async {
    final trimmedToken = token.trim();
    Uri baseUri;
    try {
      baseUri = normalizeRemoteBaseUri(address);
      if (trimmedToken.isEmpty) {
        throw const InvalidRemoteAddressException('连接 Token 不能为空。');
      }
    } on InvalidRemoteAddressException catch (error) {
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.error,
        message: error.message,
      );
      return false;
    }

    state = RemoteConnectionState(
      status: RemoteConnectionStatus.testing,
      baseUri: baseUri,
      message: '正在测试连接...',
    );

    final now = ref.read(remoteUtcClockProvider).now().toUtc();
    final candidate = RemoteConnectionProfile(
      baseUri: baseUri,
      token: trimmedToken,
      lastVerifiedAtUtc: now,
      apiVersion: 1,
      displayName: baseUri.host,
    );
    final api = ref.read(remoteIbukiApiFactoryProvider)(candidate);

    try {
      final health = await api.getHealth();
      if (health.apiVersion != 1) {
        state = RemoteConnectionState(
          status: RemoteConnectionStatus.incompatible,
          baseUri: baseUri,
          message: '电脑端 API 版本不兼容。',
        );
        return false;
      }
      final capabilities = await api.getCapabilities();
      if (!capabilities.readOnly) {
        state = RemoteConnectionState(
          status: RemoteConnectionStatus.incompatible,
          baseUri: baseUri,
          message: '电脑服务不是只读模式，已拒绝连接。',
        );
        return false;
      }
      if (!capabilities.supportsProjects || !capabilities.supportsSegments) {
        state = RemoteConnectionState(
          status: RemoteConnectionStatus.incompatible,
          baseUri: baseUri,
          message: '电脑服务不支持项目或正文浏览。',
        );
        return false;
      }
      if (capabilities.supportsWrite) {
        state = RemoteConnectionState(
          status: RemoteConnectionStatus.incompatible,
          baseUri: baseUri,
          message: '电脑服务声明支持写入，本阶段仅允许只读连接。',
        );
        return false;
      }

      final profile = candidate.copyWith(
        apiVersion: capabilities.apiVersion,
        lastVerifiedAtUtc: now,
      );
      _verifiedProfile = profile;
      if (saveOnSuccess) {
        await ref.read(remoteCredentialStoreProvider).save(profile);
        _savedProfile = profile;
      }
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.connected,
        baseUri: profile.baseUri,
        displayName: profile.displayName,
        lastVerifiedAtUtc: profile.lastVerifiedAtUtc,
        apiVersion: profile.apiVersion,
        message: saveOnSuccess ? '已保存连接。' : '连接测试成功。',
      );
      return true;
    } on RemoteAuthException {
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.unauthorized,
        baseUri: baseUri,
        message: 'Token 错误，请检查电脑端生成的连接 Token。',
      );
      return false;
    } on RemoteNetworkException {
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.unreachable,
        baseUri: baseUri,
        message: '无法连接电脑，请确认地址、端口和同一局域网。',
      );
      return false;
    } on RemoteProtocolException {
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.error,
        baseUri: baseUri,
        message: '电脑端返回的协议格式无法识别。',
      );
      return false;
    } on RemoteServerException {
      state = RemoteConnectionState(
        status: RemoteConnectionStatus.error,
        baseUri: baseUri,
        message: '电脑端服务内部错误，请稍后重试。',
      );
      return false;
    } finally {
      api.close();
    }
  }
}

Uri normalizeRemoteBaseUri(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    throw const InvalidRemoteAddressException('请输入完整的电脑地址。');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const InvalidRemoteAddressException('只支持 http 或 https 地址。');
  }
  if (uri.host.isEmpty) {
    throw const InvalidRemoteAddressException('电脑地址必须包含 host。');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const InvalidRemoteAddressException('地址中不能包含用户名或密码。');
  }
  return uri.replace(
    path: _trimTrailingSlashes(uri.path),
    query: null,
    fragment: null,
  );
}

String _trimTrailingSlashes(String path) {
  if (path.isEmpty || path == '/') {
    return '';
  }
  return path.replaceFirst(RegExp(r'/+$'), '');
}
