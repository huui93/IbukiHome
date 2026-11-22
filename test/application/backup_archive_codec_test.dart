import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/backup/backup_security.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';

void main() {
  group('BackupArchiveCodec', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ibuki-backup-codec-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('writes chunked logical data and verifies checksums', () async {
      final codec = BackupArchiveCodec(
        applicationSupportDirectory: root,
        limits: const BackupArchiveLimits(rowsPerChunk: 2),
      );
      final file = File('${root.path}/sample.ibukibackup');
      final preview = await codec.write(
        snapshot: const BackupSnapshot(
          collections: {
            'projects': [
              {'id': 'p1', 'title': 'A'},
              {'id': 'p2', 'title': 'B'},
              {'id': 'p3', 'title': 'C'},
            ],
          },
        ),
        destination: file,
        appVersion: 'test',
        schemaVersion: 12,
      );

      expect(preview.manifest.collections.single.files, hasLength(2));
      final decoded = await codec.read(
        source: file,
        staging: Directory('${root.path}/read'),
      );
      expect(decoded.snapshot.collections['projects'], hasLength(3));
      expect(decoded.preview.checksum, hasLength(64));
    });

    test(
      'large logical collections remain split into bounded chunks',
      () async {
        const rowCount = 100001;
        const rowsPerChunk = 5000;
        final codec = BackupArchiveCodec(
          applicationSupportDirectory: root,
          limits: const BackupArchiveLimits(rowsPerChunk: rowsPerChunk),
        );
        final file = File('${root.path}/large.ibukibackup');
        final preview = await codec.write(
          snapshot: BackupSnapshot(
            collections: {
              'chat_messages': List.generate(
                rowCount,
                (index) => {'id': 'message-$index', 'content': 'line $index'},
              ),
            },
          ),
          destination: file,
          appVersion: 'test',
          schemaVersion: 12,
        );

        final collection = preview.manifest.collections.single;
        expect(collection.rowCount, rowCount);
        expect(collection.files, hasLength(21));
        expect(
          collection.files.every((path) => path.endsWith('.jsonl')),
          isTrue,
        );
        final decoded = await codec.read(
          source: file,
          staging: Directory('${root.path}/large-read'),
        );
        expect(
          decoded.snapshot.collections['chat_messages'],
          hasLength(rowCount),
        );
      },
    );

    test('cancellation removes partial archive output', () async {
      final codec = BackupArchiveCodec(applicationSupportDirectory: root);
      final file = File('${root.path}/cancelled.ibukibackup');
      final cancellation = BackupCancellationToken()..cancel();
      await expectLater(
        codec.write(
          snapshot: const BackupSnapshot(
            collections: {
              'projects': [
                {'id': 'p1'},
              ],
            },
          ),
          destination: file,
          appVersion: 'test',
          schemaVersion: 12,
          cancellation: cancellation,
        ),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      expect(await file.exists(), isFalse);
    });

    test('rejects traversal, future versions, and checksum mismatch', () async {
      final codec = BackupArchiveCodec(applicationSupportDirectory: root);
      final traversal = File('${root.path}/traversal.ibukibackup');
      _writeArchive(traversal, {
        '../escape': 'no',
        'manifest.json': _manifest(),
        'checksums.json': '{}',
      });
      await expectLater(
        codec.read(source: traversal, staging: Directory('${root.path}/t1')),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'unsafe_path'),
        ),
      );

      final future = File('${root.path}/future.ibukibackup');
      _writeArchive(future, {
        'manifest.json': _manifest(version: 99),
        'checksums.json': '{}',
      });
      await expectLater(
        codec.read(source: future, staging: Directory('${root.path}/t2')),
        throwsA(
          isA<BackupException>().having(
            (e) => e.code,
            'code',
            'future_version',
          ),
        ),
      );

      final bad = File('${root.path}/bad.ibukibackup');
      _writeArchive(bad, {
        'manifest.json': _manifest(),
        'data/projects/00000.jsonl': '{"id":"p1"}\n',
        'checksums.json': jsonEncode({'data/projects/00000.jsonl': '0' * 64}),
      });
      await expectLater(
        codec.read(source: bad, staging: Directory('${root.path}/t3')),
        throwsA(
          isA<BackupException>().having(
            (e) => e.code,
            'code',
            'checksum_mismatch',
          ),
        ),
      );
    });
  });

  test('secret sanitizer removes credentials but preserves inert scripts', () {
    const sanitizer = BackupSecuritySanitizer();
    final value =
        sanitizer.sanitize({
              'api_key': 'sk-not-archived-123456789',
              'nested': {
                'Authorization': 'Bearer abcdefghijklmnop',
                'script':
                    'function rubyPanel() { return "safe inert source"; }',
              },
            })
            as Map<String, Object?>;

    expect(value, isNot(contains('api_key')));
    final nested = value['nested']! as Map<String, Object?>;
    expect(nested, isNot(contains('Authorization')));
    expect(nested['script'], contains('rubyPanel'));
  });
}

String _manifest({int version = 1}) => jsonEncode({
  'archiveFormat': ibukiBackupFormat,
  'archiveVersion': version,
  'createdAt': '2026-01-01T00:00:00Z',
  'appVersion': 'test',
  'schemaVersion': 12,
  'collections': const [],
  'assets': const [],
  'security': const {},
});

void _writeArchive(File file, Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  file.writeAsBytesSync(ZipEncoder().encode(archive));
}
