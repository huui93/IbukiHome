import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';

import '../helpers/plugin_test_helpers.dart';

void main() {
  test('parse valid manifest v1 and retain open extension fields', () {
    final manifest = IbukiPluginManifest.parse(
      jsonEncode(
        pluginManifest(
          permissions: const ['project.read', 'future.permission'],
          capabilities: const ['demo', 'future.unknown-capability'],
          metadata: const {'futureField': true},
        ),
      ),
    );

    expect(manifest.id, 'dev.ibuki.test');
    expect(manifest.manifestVersion, 1);
    expect(manifest.permissions, contains('future.permission'));
    expect(manifest.capabilities, contains('future.unknown-capability'));
    expect(manifest.metadata['futureField'], true);
  });

  test('malformed manifest is rejected', () {
    expect(
      () => IbukiPluginManifest.parse('{broken'),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.malformedManifest,
        ),
      ),
    );
  });

  test('missing id is rejected', () {
    final json = pluginManifest()..remove('id');
    expect(
      () => IbukiPluginManifest.fromJson(json.cast<String, dynamic>()),
      throwsA(isA<PluginException>()),
    );
  });

  for (final invalidId in [
    '../escape',
    r'C:\plugin',
    'with/slash',
    'line\nbreak',
    '.',
    '..',
  ]) {
    test('invalid plugin id "$invalidId" is rejected', () {
      final json = pluginManifest(id: invalidId);
      expect(
        () => IbukiPluginManifest.fromJson(json.cast<String, dynamic>()),
        throwsA(isA<PluginException>()),
      );
    });
  }

  test('unsupported manifest version is rejected', () {
    final json = pluginManifest(manifestVersion: 2);
    expect(
      () => IbukiPluginManifest.fromJson(json.cast<String, dynamic>()),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.unsupportedManifestVersion,
        ),
      ),
    );
  });

  test('unsafe manifest entry path is rejected', () {
    final json = pluginManifest()..['entry'] = '../scripts/main.js';
    expect(
      () => IbukiPluginManifest.fromJson(json.cast<String, dynamic>()),
      throwsA(isA<PluginException>()),
    );
  });
}
