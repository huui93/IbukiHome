enum PluginErrorCategory {
  invalidExtension,
  invalidArchive,
  missingManifest,
  malformedManifest,
  invalidManifest,
  unsupportedManifestVersion,
  incompatibleExtensionApi,
  incompatibleAppVersion,
  unsafeArchivePath,
  packageTooLarge,
  duplicateInstall,
  installFailed,
  updateFailed,
  registryFailure,
  brokenPlugin,
  permissionDenied,
  invalidBridgeRequest,
  unsupportedRuntime,
  pluginRuntimeFailure,
  storageFailure,
  promptConflict,
  aiRequestBusy,
  aiRequestTimeout,
}

class PluginException implements Exception {
  const PluginException(this.category, this.message, {this.detail});

  final PluginErrorCategory category;
  final String message;
  final String? detail;

  @override
  String toString() => message;
}
