class RemoteApiConfig {
  const RemoteApiConfig({
    required this.baseUri,
    required this.bearerToken,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri baseUri;
  final String bearerToken;
  final Duration timeout;
}
