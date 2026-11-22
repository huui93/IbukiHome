import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/backup/backup_models.dart';
import '../common/entity_id_generator.dart';
import 'backup_security.dart';

class BackupArchiveLimits {
  const BackupArchiveLimits({
    this.maxArchiveBytes = 2 * 1024 * 1024 * 1024,
    this.maxEntries = 20000,
    this.maxSingleEntryBytes = 256 * 1024 * 1024,
    this.maxExtractedBytes = 4 * 1024 * 1024 * 1024,
    this.maxManifestBytes = 4 * 1024 * 1024,
    this.rowsPerChunk = 5000,
  });

  final int maxArchiveBytes;
  final int maxEntries;
  final int maxSingleEntryBytes;
  final int maxExtractedBytes;
  final int maxManifestBytes;
  final int rowsPerChunk;
}

class DecodedBackupArchive {
  const DecodedBackupArchive({
    required this.preview,
    required this.snapshot,
    required this.assetDirectory,
  });

  final BackupPreview preview;
  final BackupSnapshot snapshot;
  final Directory assetDirectory;
}

class BackupArchiveCodec {
  BackupArchiveCodec({
    required this.applicationSupportDirectory,
    this.limits = const BackupArchiveLimits(),
    this.sanitizer = const BackupSecuritySanitizer(),
  });

  final Directory applicationSupportDirectory;
  final BackupArchiveLimits limits;
  final BackupSecuritySanitizer sanitizer;

  static const _assetColumns = {
    'avatar_reference',
    'image_reference',
    'background_reference',
  };

  Future<BackupPreview> preview(
    BackupSnapshot snapshot, {
    required String appVersion,
    required int schemaVersion,
  }) async {
    final assets = <String, BackupAssetManifest>{};
    for (final rows in snapshot.collections.values) {
      for (final row in rows) {
        for (final column in _assetColumns) {
          final value = row[column];
          if (value is! String || value.isEmpty || assets.containsKey(value)) {
            continue;
          }
          final file = File(value);
          if (!await file.exists() || !_isPrivatePath(value)) continue;
          final digest = await _shaFile(file);
          assets[value] = BackupAssetManifest(
            id: digest,
            archivePath: 'assets/$digest/${_safeFileName(p.basename(value))}',
            fileName: _safeFileName(p.basename(value)),
            bytes: await file.length(),
            sha256: digest,
          );
        }
      }
    }
    final manifest = IbukiBackupManifest(
      createdAt: DateTime.now().toUtc(),
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      collections: snapshot.collections.entries
          .map(
            (entry) => BackupCollectionManifest(
              name: entry.key,
              rowCount: entry.value.length,
              files: const [],
            ),
          )
          .toList(growable: false),
      assets: assets.values.toList(growable: false),
      security: const {
        'credentialsIncluded': false,
        'providerBindingsRestored': false,
        'scriptsExecutable': false,
        'networkAllowed': false,
      },
    );
    return BackupPreview(manifest: manifest, checksum: '');
  }

  Future<BackupPreview> write({
    required BackupSnapshot snapshot,
    required File destination,
    required String appVersion,
    required int schemaVersion,
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    final operationId = EntityIdGenerator().nextId('backup');
    final staging = Directory(
      p.join(applicationSupportDirectory.path, 'backup', 'temp', operationId),
    );
    await staging.create(recursive: true);
    try {
      final assets = <BackupAssetManifest>[];
      final assetByPath = <String, String>{};
      final collectionManifests = <BackupCollectionManifest>[];
      var processed = 0;
      final total = snapshot.collections.values.fold<int>(
        0,
        (a, b) => a + b.length,
      );
      for (final collection in snapshot.collections.entries) {
        cancellation?.throwIfCancelled();
        final files = <String>[];
        IOSink? sink;
        try {
          for (var index = 0; index < collection.value.length; index++) {
            cancellation?.throwIfCancelled();
            if (index % limits.rowsPerChunk == 0) {
              await sink?.close();
              final chunkIndex = index ~/ limits.rowsPerChunk;
              final relative =
                  'data/${collection.key}/${chunkIndex.toString().padLeft(5, '0')}.jsonl';
              final output = File(
                p.joinAll([staging.path, ...p.posix.split(relative)]),
              );
              await output.parent.create(recursive: true);
              sink = output.openWrite();
              files.add(relative);
            }

            final row = Map<String, Object?>.from(collection.value[index]);
            _sanitizeRow(collection.key, row);
            for (final column in _assetColumns) {
              final raw = row[column];
              if (raw is! String || raw.isEmpty) continue;
              final file = File(raw);
              if (!await file.exists() || !_isPrivatePath(file.path)) {
                row[column] = null;
                continue;
              }
              final canonical = p.normalize(p.absolute(file.path));
              var assetId = assetByPath[canonical];
              if (assetId == null) {
                final digest = await _shaFile(file);
                assetId = digest;
                assetByPath[canonical] = assetId;
                final safeName = _safeFileName(p.basename(file.path));
                final archivePath = 'assets/$assetId/$safeName';
                final target = File(
                  p.joinAll([staging.path, ...p.posix.split(archivePath)]),
                );
                await target.parent.create(recursive: true);
                await file.copy(target.path);
                assets.add(
                  BackupAssetManifest(
                    id: assetId,
                    archivePath: archivePath,
                    fileName: safeName,
                    bytes: await target.length(),
                    sha256: digest,
                  ),
                );
              }
              row[column] = 'ibuki-asset://$assetId';
            }
            sink!.writeln(jsonEncode(row));
            processed += 1;
            if (processed % 250 == 0) {
              onProgress?.call(BackupProgress('正在整理数据', processed, total));
            }
          }
        } finally {
          await sink?.close();
        }

        if (files.isEmpty) {
          final relative =
              'data/${collection.key}/${0.toString().padLeft(5, '0')}.jsonl';
          final output = File(
            p.joinAll([staging.path, ...p.posix.split(relative)]),
          );
          await output.parent.create(recursive: true);
          await output.writeAsString('');
          files.add(relative);
        }
        collectionManifests.add(
          BackupCollectionManifest(
            name: collection.key,
            rowCount: collection.value.length,
            files: files,
          ),
        );
      }

      final manifest = IbukiBackupManifest(
        createdAt: DateTime.now().toUtc(),
        appVersion: appVersion,
        schemaVersion: schemaVersion,
        collections: collectionManifests,
        assets: assets,
        security: const {
          'credentialsIncluded': false,
          'providerBindingsRestored': false,
          'scriptsExecutable': false,
          'networkAllowed': false,
        },
      );
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      await manifestFile.writeAsString(manifest.encode(), flush: true);

      final checksumMap = <String, String>{};
      final files = await staging
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (final file in files) {
        cancellation?.throwIfCancelled();
        final relative = p
            .relative(file.path, from: staging.path)
            .replaceAll('\\', '/');
        checksumMap[relative] = await _shaFile(file);
      }
      final checksumFile = File(p.join(staging.path, 'checksums.json'));
      await checksumFile.writeAsString(jsonEncode(checksumMap), flush: true);

      await destination.parent.create(recursive: true);
      if (await destination.exists()) await destination.delete();
      final encoder = ZipFileEncoder();
      encoder.create(destination.path);
      final archiveFiles = await staging
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      archiveFiles.sort((a, b) => a.path.compareTo(b.path));
      try {
        for (var index = 0; index < archiveFiles.length; index++) {
          cancellation?.throwIfCancelled();
          final file = archiveFiles[index];
          final relative = p
              .relative(file.path, from: staging.path)
              .replaceAll('\\', '/');
          await encoder.addFile(file, relative);
          onProgress?.call(
            BackupProgress('正在写入备份', index + 1, archiveFiles.length),
          );
        }
      } finally {
        await encoder.close();
      }
      final validationDirectory = Directory(
        p.join(
          applicationSupportDirectory.path,
          'backup',
          'validation',
          operationId,
        ),
      );
      try {
        await read(source: destination, staging: validationDirectory);
      } finally {
        if (await validationDirectory.exists()) {
          await validationDirectory.delete(recursive: true);
        }
      }
      final archiveDigest = await _shaFile(destination);
      return BackupPreview(manifest: manifest, checksum: archiveDigest);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<DecodedBackupArchive> read({
    required File source,
    required Directory staging,
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (!await source.exists() ||
        await source.length() > limits.maxArchiveBytes) {
      throw const BackupException('archive_too_large', '备份文件不存在或体积超过安全限制。');
    }
    await staging.create(recursive: true);
    InputFileStream? input;
    try {
      input = InputFileStream(source.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > limits.maxEntries) {
        throw const BackupException('too_many_files', '备份包含的文件数量超过安全限制。');
      }
      final paths = <String>{};
      var total = 0;
      for (var index = 0; index < archive.length; index++) {
        cancellation?.throwIfCancelled();
        final entry = archive[index];
        final relative = _safeArchivePath(entry.name);
        if (!paths.add(relative.toLowerCase())) {
          throw const BackupException('duplicate_path', '备份包含重复路径。');
        }
        if (entry.isSymbolicLink) {
          throw const BackupException('unsafe_path', '备份包含不安全的符号链接。');
        }
        if (entry.size > limits.maxSingleEntryBytes) {
          throw const BackupException('entry_too_large', '备份中的单个文件超过安全限制。');
        }
        if (entry.isFile) total += entry.size;
        if (total > limits.maxExtractedBytes) {
          throw const BackupException('expanded_too_large', '备份解压后的总体积超过安全限制。');
        }
        final target = File(
          p.joinAll([staging.path, ...p.posix.split(relative)]),
        );
        final root = p.normalize(p.absolute(staging.path));
        if (!p.isWithin(root, p.normalize(p.absolute(target.path)))) {
          throw const BackupException('unsafe_path', '备份包含不安全路径。');
        }
        if (entry.isDirectory) {
          await Directory(target.path).create(recursive: true);
        } else {
          await target.parent.create(recursive: true);
          final output = OutputFileStream(target.path);
          try {
            entry.writeContent(output);
          } finally {
            output.closeSync();
          }
        }
        onProgress?.call(BackupProgress('正在验证备份', index + 1, archive.length));
      }
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupException(
        'invalid_archive',
        '备份已损坏或不是有效归档。',
        detail: error.runtimeType.toString(),
      );
    } finally {
      input?.closeSync();
    }

    final manifestFile = File(p.join(staging.path, 'manifest.json'));
    final checksumsFile = File(p.join(staging.path, 'checksums.json'));
    if (!await manifestFile.exists() || !await checksumsFile.exists()) {
      throw const BackupException('missing_manifest', '备份缺少清单或校验信息。');
    }
    if (await manifestFile.length() > limits.maxManifestBytes) {
      throw const BackupException('manifest_too_large', '备份清单超过安全限制。');
    }
    final manifest = IbukiBackupManifest.parse(
      await manifestFile.readAsString(),
    );
    final checksumValue = jsonDecode(await checksumsFile.readAsString());
    if (checksumValue is! Map<String, Object?>) {
      throw const BackupException('invalid_checksums', '备份校验信息无效。');
    }
    for (final item in checksumValue.entries) {
      cancellation?.throwIfCancelled();
      final relative = _safeArchivePath(item.key);
      final expected = item.value;
      final file = File(p.joinAll([staging.path, ...p.posix.split(relative)]));
      if (expected is! String ||
          !await file.exists() ||
          await _shaFile(file) != expected) {
        throw BackupException('checksum_mismatch', '备份文件校验失败：$relative');
      }
    }
    final requiredChecksums = <String>{
      'manifest.json',
      for (final collection in manifest.collections) ...collection.files,
      for (final asset in manifest.assets) asset.archivePath,
    };
    if (!checksumValue.keys.toSet().containsAll(requiredChecksums)) {
      throw const BackupException('missing_checksum', '备份缺少关键文件的校验信息。');
    }

    final collections = <String, List<Map<String, Object?>>>{};
    for (final collection in manifest.collections) {
      cancellation?.throwIfCancelled();
      final rows = <Map<String, Object?>>[];
      for (final relative in collection.files) {
        cancellation?.throwIfCancelled();
        final safe = _safeArchivePath(relative);
        if (!safe.startsWith('data/${collection.name}/')) {
          throw const BackupException(
            'invalid_collection_path',
            '数据集合路径与清单不一致。',
          );
        }
        final file = File(p.joinAll([staging.path, ...p.posix.split(safe)]));
        if (!await file.exists()) {
          throw BackupException('missing_data', '备份缺少数据文件：$safe');
        }
        await for (final line
            in file
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          cancellation?.throwIfCancelled();
          if (line.trim().isEmpty) continue;
          final value = jsonDecode(line);
          if (value is! Map<String, Object?>) {
            throw BackupException(
              'invalid_row',
              '数据集合 ${collection.name} 包含无效记录。',
            );
          }
          rows.add(value);
        }
      }
      if (rows.length != collection.rowCount) {
        throw BackupException(
          'row_count_mismatch',
          '数据集合 ${collection.name} 的记录数量不一致。',
        );
      }
      collections[collection.name] = rows;
    }
    for (final asset in manifest.assets) {
      cancellation?.throwIfCancelled();
      final safe = _safeArchivePath(asset.archivePath);
      if (!safe.startsWith('assets/')) {
        throw const BackupException('invalid_asset_path', '资源路径无效。');
      }
      final file = File(p.joinAll([staging.path, ...p.posix.split(safe)]));
      if (!await file.exists() ||
          await file.length() != asset.bytes ||
          await _shaFile(file) != asset.sha256) {
        throw BackupException(
          'asset_checksum_mismatch',
          '资源校验失败：${asset.fileName}',
        );
      }
    }
    return DecodedBackupArchive(
      preview: BackupPreview(
        manifest: manifest,
        checksum: await _shaFile(source),
      ),
      snapshot: BackupSnapshot(collections: collections),
      assetDirectory: staging,
    );
  }

  void _sanitizeRow(String collection, Map<String, Object?> row) {
    final sanitized = sanitizer.sanitize(row);
    if (sanitized is Map<String, Object?>) {
      row
        ..clear()
        ..addAll(sanitized);
    }
    row.remove('ai_provider_config_id');
    row.remove('ai_model');
    if (collection == 'compatibilityPayloads') {
      for (final key in const [
        'normalized_payload_json',
        'unsupported_payload_json',
        'metadata_json',
      ]) {
        final value = row[key];
        if (value is String) row[key] = sanitizer.sanitizeJson(value);
      }
    }
  }

  bool _isPrivatePath(String filePath) {
    final root = p.normalize(p.absolute(applicationSupportDirectory.path));
    final candidate = p.normalize(p.absolute(filePath));
    return p.isWithin(root, candidate);
  }

  String _safeArchivePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.contains('\u0000') ||
        p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw const BackupException('unsafe_path', '备份包含不安全路径。');
    }
    final canonical = p.posix.normalize(normalized);
    if (canonical == '..' ||
        canonical.startsWith('../') ||
        canonical != normalized.replaceAll(RegExp('/+'), '/')) {
      throw const BackupException('unsafe_path', '备份包含路径穿越。');
    }
    return canonical;
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<String> _shaFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
