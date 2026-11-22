import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_workspace_mode.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/remote/remote_browser_controller.dart';
import '../../../application/remote/remote_connection_controller.dart';
import '../../../application/remote/remote_connection_state.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';

class RemoteConnectPage extends ConsumerStatefulWidget {
  const RemoteConnectPage({
    this.sourceWorkspace = AppWorkspaceMode.home,
    super.key,
  });

  final AppWorkspaceMode sourceWorkspace;

  @override
  ConsumerState<RemoteConnectPage> createState() => _RemoteConnectPageState();
}

class _RemoteConnectPageState extends ConsumerState<RemoteConnectPage> {
  late final TextEditingController _addressController;
  late final TextEditingController _tokenController;
  var _showToken = false;
  var _loadedSavedProfile = false;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController()..addListener(_listen);
    _tokenController = TextEditingController()..addListener(_listen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedProfile());
  }

  @override
  void dispose() {
    _addressController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remoteConnectionControllerProvider);
    final isTesting = state.status == RemoteConnectionStatus.testing;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: ListView(
        key: const Key('remote-connect-page'),
        padding: const EdgeInsets.all(AppTokens.spacingM),
        children: [
          Text(
            '连接电脑',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.spacingS),
          const _ReadOnlyNotice(),
          const SizedBox(height: AppTokens.spacingM),
          TextField(
            key: const Key('remote-address-field'),
            controller: _addressController,
            enabled: !isTesting,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '电脑地址',
              hintText: 'http://192.168.1.10:8765',
              prefixIcon: Icon(Icons.computer_outlined),
            ),
          ),
          const SizedBox(height: AppTokens.spacingM),
          TextField(
            key: const Key('remote-token-field'),
            controller: _tokenController,
            enabled: !isTesting,
            obscureText: !_showToken,
            decoration: InputDecoration(
              labelText: '连接 Token',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                key: const Key('remote-token-visibility-button'),
                tooltip: _showToken ? '隐藏 Token' : '显示 Token',
                onPressed: () {
                  setState(() {
                    _showToken = !_showToken;
                  });
                },
                icon: Icon(
                  _showToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spacingM),
          _ConnectionStatusView(state: state),
          const SizedBox(height: AppTokens.spacingM),
          Wrap(
            spacing: AppTokens.spacingS,
            runSpacing: AppTokens.spacingS,
            children: [
              FilledButton.tonalIcon(
                key: const Key('remote-test-button'),
                onPressed: isTesting ? null : _testConnection,
                icon: isTesting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_outlined),
                label: Text(isTesting ? '测试中' : '测试连接'),
              ),
              FilledButton.icon(
                key: const Key('remote-save-button'),
                onPressed: isTesting ? null : _saveConnection,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('保存并连接'),
              ),
              OutlinedButton.icon(
                key: const Key('remote-disconnect-button'),
                onPressed: isTesting ? null : _disconnect,
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('断开连接'),
              ),
            ],
          ),
          if (state.isConnected) ...[
            const SizedBox(height: AppTokens.spacingM),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('remote-open-projects-button'),
                onPressed: () => context.push(
                  AppRoutes.remoteProjectsFor(widget.sourceWorkspace),
                ),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('浏览电脑项目'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadSavedProfile() async {
    if (_loadedSavedProfile || !mounted) {
      return;
    }
    _loadedSavedProfile = true;
    await ref
        .read(remoteConnectionControllerProvider.notifier)
        .loadSavedProfile();
    if (!mounted) {
      return;
    }
    final state = ref.read(remoteConnectionControllerProvider);
    final baseUri = state.baseUri;
    if (baseUri != null && _addressController.text.trim().isEmpty) {
      _addressController.text = baseUri.toString();
    }
  }

  void _listen() {
    if (!mounted) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
  }

  Future<void> _testConnection() async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    final ok = await ref
        .read(remoteConnectionControllerProvider.notifier)
        .testConnection(
          address: _addressController.text,
          token: _tokenController.text,
        );
    if (!mounted) {
      return;
    }
    ref
        .read(mascotControllerProvider.notifier)
        .perform(ok ? MascotAction.celebrate : MascotAction.settle);
  }

  Future<void> _saveConnection() async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    final ok = await ref
        .read(remoteConnectionControllerProvider.notifier)
        .saveConnection(
          address: _addressController.text,
          token: _tokenController.text,
        );
    if (!mounted) {
      return;
    }
    ref
        .read(mascotControllerProvider.notifier)
        .perform(ok ? MascotAction.celebrate : MascotAction.settle);
    if (ok) {
      _tokenController.clear();
      setState(() {
        _showToken = false;
      });
    }
  }

  Future<void> _disconnect() async {
    await ref.read(remoteConnectionControllerProvider.notifier).disconnect();
    ref.read(remoteBrowserControllerProvider.notifier).clear();
    _tokenController.clear();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已断开电脑连接。')));
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('remote-readonly-notice'),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
      ),
      child: const Padding(
        padding: EdgeInsets.all(AppTokens.spacingS),
        child: Text('当前阶段只读取电脑项目，不会修改电脑文件，也不会导入到手机本地数据库。'),
      ),
    );
  }
}

class _ConnectionStatusView extends StatelessWidget {
  const _ConnectionStatusView({required this.state});

  final RemoteConnectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = state.status == RemoteConnectionStatus.connected
        ? AppTokens.success
        : state.status == RemoteConnectionStatus.disconnected
        ? scheme.onSurfaceVariant
        : scheme.error;
    return DecoratedBox(
      key: const Key('remote-connection-status'),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      child: ListTile(
        leading: Icon(Icons.circle, size: 12, color: color),
        title: Text(_statusText(state.status)),
        subtitle: Text(_subtitle),
      ),
    );
  }

  String get _subtitle {
    final baseUri = state.baseUri;
    final message = state.message ?? '';
    if (baseUri == null) {
      return message.isEmpty ? '尚未连接电脑。' : message;
    }
    return '$baseUri\n$message';
  }

  String _statusText(RemoteConnectionStatus status) {
    switch (status) {
      case RemoteConnectionStatus.disconnected:
        return '未连接';
      case RemoteConnectionStatus.testing:
        return '正在测试';
      case RemoteConnectionStatus.connected:
        return '已连接';
      case RemoteConnectionStatus.unauthorized:
        return 'Token 错误';
      case RemoteConnectionStatus.incompatible:
        return '服务不兼容';
      case RemoteConnectionStatus.unreachable:
        return '无法连接';
      case RemoteConnectionStatus.error:
        return '连接错误';
    }
  }
}
