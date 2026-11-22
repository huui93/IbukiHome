import 'package:ibukihome/data/sqlite/sqlite_novel_plugin_state_store.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/novel_plugin_bundle.dart';
import 'package:ibukihome/application/plugins/novel_plugin_scope_store.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/data/sqlite/sqlite_novel_plugin_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_plugin_registry.dart';
import 'package:ibukihome/data/sqlite/sqlite_plugin_storage_repository.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:ibukihome/domain/plugins/novel_plugin_models.dart';
import 'package:ibukihome/domain/plugins/novel_history_fingerprint.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import '../data/sqlite/sqlite_test_helpers.dart';

void main() {
  group(
    'Local NVWA host integration',
    () {
      setUpAll(ensureSqliteFfi);
      final now = DateTime.utc(2026, 11, 22);
      Future<
        ({
          SqliteFixture f,
          SQLiteNovelPluginRepository repo,
          NovelPluginScopeStore scopes,
          InstalledPlugin plugin,
          NovelPluginBundle bundle,
        })
      >
      fixture() async {
        final f = await SqliteFixture.create();
        for (final id in ['story', 'other']) {
          await f.projects.upsertProject(
            Project(metadata: metadata(id), title: id, description: ''),
          );
        }
        await f.segments.upsertSegment(
          segment('s', 'story', 0, content: '已经发生的事实'),
        );
        final plugin = InstalledPlugin(
          manifest: IbukiPluginManifest.parse(
            File('plugins/nvwa-novel/manifest.json').readAsStringSync(),
          ),
          installedPath: Directory('plugins/nvwa-novel').absolute.path,
          dataPath: 'unused',
          enabled: true,
          installedAt: now,
          updatedAt: now,
        );
        await SQLitePluginRegistry(f.database).upsertPlugin(plugin);
        final repo = SQLiteNovelPluginRepository(f.database);
        final scopes = NovelPluginScopeStore(
          repository: repo,
          storage: NovelRoutingPluginStorage(
            SQLitePluginStorageRepository(f.database),
            SQLiteNovelPluginStateStore(f.database),
          ),
        );
        addTearDown(scopes.dispose);
        return (
          f: f,
          repo: repo,
          scopes: scopes,
          plugin: plugin,
          bundle: await const NovelPluginBundleLoader().load(plugin),
        );
      }

      test(
        'story binding stays independent, branches inherit live values until explicitly overridden',
        () async {
          final x = await fixture();
          final p = x.plugin;
          final scopes = x.scopes;
          final preset = x.bundle.preset;
          expect((await scopes.resolve(p, 'story')).enabled, isFalse);
          await scopes.enable(p, 'story', true);
          await scopes.applyScheme(p, 'story', preset, preset.schemes['自然']!);
          await x.repo.fork(
            projectId: 'story',
            newProjectId: 'fork',
            label: '分支',
            now: now,
          );
          expect((await scopes.resolve(p, 'fork')).inherited, isTrue);
          await scopes.applyScheme(p, 'story', preset, preset.schemes['悬疑']!);
          expect(
            ((await scopes.resolve(p, 'fork')).settings['groups']
                as Map)['tone'],
            'nvwa_style_tone_xuanyi',
          );
          await scopes.applyScheme(p, 'fork', preset, preset.schemes['自然']!);
          expect((await scopes.resolve(p, 'fork')).inherited, isFalse);
          expect(
            ((await scopes.resolve(p, 'fork')).settings['groups']
                as Map)['tone'],
            'nvwa_style_tone_ziran',
          );
          expect((await scopes.resolve(p, 'other')).enabled, isFalse);
          await scopes.inherit(p, 'fork', true);
          expect(
            ((await scopes.resolve(p, 'fork')).settings['groups']
                as Map)['tone'],
            'nvwa_style_tone_xuanyi',
          );
          expect(
            (await scopes.resolve(p.copyWith(enabled: false), 'story')).enabled,
            isFalse,
          );
        },
      );
      test(
        'concurrent changes merge, schemes retain all settings, and session ending cannot be plugin-granted',
        () async {
          final x = await fixture();
          final scopes = x.scopes;
          final p = x.plugin;
          final preset = x.bundle.preset;
          await scopes.enable(p, 'story', true);
          await Future.wait([
            scopes.setSetting(
              p,
              'story',
              preset,
              'entries',
              'nvwa_model_notes',
              true,
            ),
            scopes.setSetting(p, 'story', preset, 'request', 'temperature', .4),
          ]);
          final state = await scopes.resolve(p, 'story');
          expect(
            (state.settings['entries'] as Map)['nvwa_model_notes'],
            isTrue,
          );
          expect((state.settings['request'] as Map)['temperature'], .4);
          expect(state.allowEnd, isFalse);
          await expectLater(
            scopes.authorizeEnd(p, 'story', true, userGesture: false),
            throwsException,
          );
          await expectLater(
            scopes.setSetting(p, 'story', preset, 'allowEnd', 'value', true),
            throwsException,
          );
          await scopes.authorizeEnd(p, 'story', true, userGesture: true);
          expect((await scopes.resolve(p, 'story')).allowEnd, isTrue);
          await scopes.saveScheme(p, '自己的方案', state.settings);
          await scopes.applyScheme(
            p,
            'other',
            preset,
            (await scopes.savedSchemes(p.id))['自己的方案']!,
            complete: true,
          );
          expect((await scopes.resolve(p, 'other')).settings, state.settings);
          expect((await scopes.resolve(p, 'other')).allowEnd, isFalse);
        },
      );
      test(
        'forked private memory retains valid frozen sources while parent edits invalidate only parent memory',
        () async {
          final x = await fixture();
          final source = await x.repo.history('story');
          final refs = novelSourceRefs(source);
          final block = NovelMemoryBlock(
            id: 'summary',
            content: '原始事实摘要',
            coveredMessageIds: ['s'],
            sourceRefs: refs,
            sourceFingerprint: novelRefsFingerprint(refs),
          );
          await x.scopes.privateSet(x.plugin, 'story', 'memory', {
            'blocks': [block.toJson()],
          });
          expect(
            await x.scopes.privateGet(x.plugin, 'other', 'memory'),
            isNull,
          );
          await x.repo.fork(
            projectId: 'story',
            newProjectId: 'fork',
            label: '分支',
            now: now,
          );
          final copied =
              await x.scopes.privateGet(x.plugin, 'fork', 'memory') as Map;
          final inherited = NovelMemoryBlock.fromJson(
            Map<String, Object?>.from((copied['blocks'] as List).single as Map),
          );
          expect(
            novelMemorySourcesCurrent(inherited, await x.repo.history('fork')),
            isTrue,
          );
          await SaveSegment(x.f.segments)(
            currentSegment: await x.f.segments.getSegment('s'),
            newContent: '后来修改的事实',
            now: now,
            revisionId: 'rev',
            mode: 'edit',
          );
          expect(
            novelMemorySourcesCurrent(block, await x.repo.history('story')),
            isFalse,
          );
          expect(
            novelMemorySourcesCurrent(inherited, await x.repo.history('fork')),
            isTrue,
          );
        },
      );
      test(
        'archive merge remaps novel scopes and memory sources without granting session-ending authority',
        () async {
          final x = await fixture();
          await SaveSegment(x.f.segments)(
            currentSegment: await x.f.segments.getSegment('s'),
            newContent: '修订后的事实',
            now: now,
            revisionId: 'before-backup',
            mode: 'edit',
          );
          final source = await x.repo.history('story');
          final refs = novelSourceRefs(source);
          final block = NovelMemoryBlock(
            id: 'summary',
            content: '事实摘要',
            coveredMessageIds: ['s'],
            sourceRefs: refs,
            sourceFingerprint: novelRefsFingerprint(refs),
          );
          await x.scopes.enable(x.plugin, 'story', true);
          await x.scopes.authorizeEnd(
            x.plugin,
            'story',
            true,
            userGesture: true,
          );
          await x.scopes.privateSet(x.plugin, 'story', 'memory', {
            'blocks': [block.toJson()],
          });
          await x.scopes.saveScheme(x.plugin, '同名方案', {
            'groups': {'tone': 'nvwa_style_tone_ziran'},
          });
          final store = SQLiteBackupSnapshotStore(x.f.database);
          final snapshot = await store.buildSnapshot();
          await store.restore(
            snapshot,
            mode: BackupRestoreMode.merge,
            restoredAssets: {},
          );
          final copy = (await x.f.projects.listProjects()).singleWhere(
            (p) => p.title == 'story' && p.id != 'story',
          );
          final state = await x.scopes.resolve(x.plugin, copy.id);
          expect(state.enabled, isTrue);
          expect(state.allowEnd, isFalse);
          expect((await x.scopes.resolve(x.plugin, 'story')).allowEnd, isTrue);
          final memory =
              await x.scopes.privateGet(x.plugin, copy.id, 'memory') as Map;
          final restored = NovelMemoryBlock.fromJson(
            Map<String, Object?>.from((memory['blocks'] as List).single as Map),
          );
          final copiedHistory = await x.repo.history(copy.id);
          expect(restored.coveredMessageIds.single, isNot('s'));
          expect(novelMemorySourcesCurrent(restored, copiedHistory), isTrue);
          expect(
            copiedHistory.single.candidates.length,
            source.single.candidates.length,
          );
          expect(
            (await x.repo.history(copy.id)).single.candidates.length,
            source.single.candidates.length,
          );
          expect(await x.scopes.savedSchemes(x.plugin.id), hasLength(2));
        },
      );
    },
    skip: !File('plugins/nvwa-novel/preset.json').existsSync()
        ? 'Requires a local NVWA preset'
        : false,
  );
}
