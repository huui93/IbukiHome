enum RemoteConnectionStatus {
  disconnected,
  testing,
  connected,
  unauthorized,
  incompatible,
  unreachable,
  error,
}

class RemoteConnectionState {
  const RemoteConnectionState({
    required this.status,
    this.baseUri,
    this.displayName,
    this.lastVerifiedAtUtc,
    this.apiVersion,
    this.message,
  });

  const RemoteConnectionState.disconnected()
    : status = RemoteConnectionStatus.disconnected,
      baseUri = null,
      displayName = null,
      lastVerifiedAtUtc = null,
      apiVersion = null,
      message = null;

  final RemoteConnectionStatus status;
  final Uri? baseUri;
  final String? displayName;
  final DateTime? lastVerifiedAtUtc;
  final int? apiVersion;
  final String? message;

  bool get isConnected => status == RemoteConnectionStatus.connected;

  RemoteConnectionState copyWith({
    RemoteConnectionStatus? status,
    Uri? baseUri,
    String? displayName,
    DateTime? lastVerifiedAtUtc,
    int? apiVersion,
    String? message,
    bool clearProfile = false,
  }) {
    return RemoteConnectionState(
      status: status ?? this.status,
      baseUri: clearProfile ? null : baseUri ?? this.baseUri,
      displayName: clearProfile ? null : displayName ?? this.displayName,
      lastVerifiedAtUtc: clearProfile
          ? null
          : lastVerifiedAtUtc ?? this.lastVerifiedAtUtc,
      apiVersion: clearProfile ? null : apiVersion ?? this.apiVersion,
      message: message,
    );
  }
}
