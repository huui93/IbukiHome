import 'ibuki_plugin_manifest.dart';

enum InstalledPluginStatus { installed, broken }

class InstalledPlugin {
  const InstalledPlugin({
    required this.manifest,
    required this.installedPath,
    required this.dataPath,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
    this.status = InstalledPluginStatus.installed,
    this.errorCategory,
    this.packageSize = 0,
    this.extractedSize = 0,
  });

  final IbukiPluginManifest manifest;
  final String installedPath;
  final String dataPath;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;
  final InstalledPluginStatus status;
  final String? errorCategory;
  final int packageSize;
  final int extractedSize;

  String get id => manifest.id;
  bool get isBroken => status == InstalledPluginStatus.broken;

  InstalledPlugin copyWith({
    IbukiPluginManifest? manifest,
    String? installedPath,
    String? dataPath,
    bool? enabled,
    DateTime? installedAt,
    DateTime? updatedAt,
    InstalledPluginStatus? status,
    String? errorCategory,
    bool clearErrorCategory = false,
    int? packageSize,
    int? extractedSize,
  }) {
    return InstalledPlugin(
      manifest: manifest ?? this.manifest,
      installedPath: installedPath ?? this.installedPath,
      dataPath: dataPath ?? this.dataPath,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      errorCategory: clearErrorCategory
          ? null
          : errorCategory ?? this.errorCategory,
      packageSize: packageSize ?? this.packageSize,
      extractedSize: extractedSize ?? this.extractedSize,
    );
  }
}
