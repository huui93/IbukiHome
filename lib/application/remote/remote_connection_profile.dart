class RemoteConnectionProfile {
  const RemoteConnectionProfile({
    required this.baseUri,
    required this.token,
    required this.lastVerifiedAtUtc,
    required this.apiVersion,
    this.displayName,
  });

  final Uri baseUri;
  final String token;
  final DateTime lastVerifiedAtUtc;
  final int apiVersion;
  final String? displayName;

  RemoteConnectionProfile copyWith({
    Uri? baseUri,
    String? token,
    DateTime? lastVerifiedAtUtc,
    int? apiVersion,
    String? displayName,
  }) {
    return RemoteConnectionProfile(
      baseUri: baseUri ?? this.baseUri,
      token: token ?? this.token,
      lastVerifiedAtUtc: lastVerifiedAtUtc ?? this.lastVerifiedAtUtc,
      apiVersion: apiVersion ?? this.apiVersion,
      displayName: displayName ?? this.displayName,
    );
  }
}
