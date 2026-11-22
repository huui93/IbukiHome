import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/plugins/novel_plugin_bundle.dart';
import 'package:ibukihome/application/plugins/novel_plugin_host.dart';
import 'package:ibukihome/application/plugins/novel_plugin_providers.dart';
import 'package:ibukihome/application/plugins/novel_plugin_scope_store.dart';
import 'package:ibukihome/application/plugins/novel_reply_markup.dart';
import 'package:ibukihome/application/plugins/plugin_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_providers.dart';
import 'package:ibukihome/data/repositories/novel_plugin_repository.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:ibukihome/domain/plugins/novel_history_fingerprint.dart';
import 'package:ibukihome/domain/plugins/novel_plugin_models.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import '../data/ai/provider_expansion_test.dart' as ai;
import '../data/sqlite/sqlite_test_helpers.dart';

void main() {
  group(
    'Local NVWA host integration',
    () {
      test(
        'novel entry points send the selected branch preset to the real wire adapter',
        () async {
          final f = await _Fixture.create();
          await f.source('s1', 'story', 'The lantern went out.');
          await f.generate('story', 'natural', 'Continue naturally.');
          final natural = jsonEncode(f.requests.single['messages']);
          expect(natural, contains('nvwa_style_tone_ziran'));
          expect(natural, isNot(contains('nvwa_style_tone_xuanyi')));
          expect(natural.split('The lantern went out.').length, 2);
          await f.repository.fork(
            projectId: 'story',
            newProjectId: 'fork',
            label: 'Suspense',
            atMessageId: 's1',
            now: f.now,
          );
          final preset = (await const NovelPluginBundleLoader().load(
            f.plugin,
          )).preset;
          await f.scopes.applyScheme(
            f.plugin,
            'fork',
            preset,
            preset.schemes['悬疑']!,
          );
          await f.scopes.setSetting(
            f.plugin,
            'fork',
            preset,
            'request',
            'top_p',
            .6,
          );
          await f.scopes.setSetting(
            f.plugin,
            'fork',
            preset,
            'request',
            'frequency_penalty',
            .5,
          );
          final origin = (await f.repository.history('fork')).single;
          final rewrite = f.container.read(rewriteSegmentProvider);
          final draft = (await rewrite(
            projectId: 'fork',
            segmentId: origin.segmentId,
            instruction: '暗示门后有人。',
            selectedCharacterIds: {},
            selectedWorldCardIds: {},
            requestId: 'rewrite-fork',
          ).toList()).last;
          final suspense = jsonEncode(f.requests.last['messages']);
          expect(suspense, contains('nvwa_style_tone_xuanyi'));
          expect(suspense, isNot(contains('nvwa_style_tone_ziran')));
          expect(suspense.split('The lantern went out.').length, 2);
          expect(f.requests.last['top_p'], .6);
          expect(f.requests.last.containsKey('frequency_penalty'), isFalse);
          expect(f.host.lastRun('fork')!.compiled.wireParameters['top_p'], .6);
          expect(
            f.host.lastRun('fork')!.compiled.notes.join(),
            contains('frequency_penalty'),
          );
          await rewrite.apply(
            segmentId: origin.segmentId,
            originalContent: origin.content,
            draft: draft.draft,
            instruction: '暗示门后有人。',
            nowUtc: f.now,
            revisionId: 'revision',
            requestId: 'rewrite-fork',
          );
          expect(
            (await f.repository.history('fork')).single.candidates.length,
            2,
          );
          expect(
            (await f.repository.history('story')).first.content,
            'The lantern went out.',
          );
          await f.generate('other', 'isolated', 'New work');
          expect(jsonEncode(f.requests.last), isNot(contains('nvwa_style')));
        },
      );

      test(
        'four finalized segments schedule automatic memory and stale sources are not injected',
        () async {
          final f = await _Fixture.create(automatic: true);
          final finished = f.host.events
              .where(
                (e) =>
                    e.projectId == 'story' &&
                    e.type == 'memory-task' &&
                    !f.container
                        .read(novelPluginMemoryProvider)
                        .isRunning('story'),
              )
              .first;
          for (var i = 0; i < 4; i++) {
            await f.source('a$i', 'story', '事件$i', notify: true);
          }
          await finished.timeout(const Duration(seconds: 5));
          final blocks = await f.host.memories(
            f.plugin,
            'story',
            await f.repository.history('story'),
          );
          expect(blocks.single.coveredMessageIds, ['a0', 'a1', 'a2', 'a3']);
          await f.scopes.configureMemory(
            f.plugin,
            'story',
            automatic: false,
            batchSize: 4,
          );
          await f.generate('story', 'with-memory', 'Continue');
          expect(jsonEncode(f.requests.last), contains('已发生事件'));
          expect(f.host.lastRun('story')!.compiled.worldInfoMemoryIds, isEmpty);
          final original = await f.container
              .read(segmentRepositoryProvider)
              .getSegment('a0');
          await f.container.read(saveSegmentProvider)(
            currentSegment: original,
            newContent: '改写了第一段',
            now: f.now,
            revisionId: 'edit-memory',
          );
          await f.generate('story', 'after-edit', 'Continue');
          expect(
            f.host
                .lastRun('story')!
                .compiled
                .blocks
                .where((b) => b.source == 'memory'),
            isEmpty,
          );
          expect(jsonEncode(f.requests.last), contains('改写了第一段'));
        },
      );

      test(
        'world book scan reads only opted-in memory and places activated entries in the request',
        () async {
          final f = await _Fixture.create();
          final world = f.container.read(worldRoleplayRepositoryProvider);
          await world.upsertWorldBook(
            WorldBook(entity: metadata('book'), name: '世界书'),
          );
          await world.upsertLoreEntry(
            LoreEntry(
              entity: metadata('lore'),
              worldBookId: 'book',
              title: '隐秘机关',
              content: 'The north gate turns purple.',
              keywords: ['purple-keyword'],
            ),
          );
          final preset = (await const NovelPluginBundleLoader().load(
            f.plugin,
          )).preset;
          await f.scopes.saveSettings(f.plugin, 'story', preset, {
            'worldBookIds': ['book'],
          });
          const memory = NovelMemoryBlock(
            id: 'reference',
            content: 'purple-keyword',
          );
          await f.scopes.privateSet(f.plugin, 'story', 'memory', {
            'blocks': [memory.toJson()],
          });
          await f.generate('story', 'before-scan', 'Continue.');
          expect(
            jsonEncode(f.requests.last),
            isNot(contains('The north gate turns purple.')),
          );
          await f.container
              .read(novelPluginMemoryProvider)
              .setScan(f.plugin, 'story', memory.id, true);
          await f.generate('story', 'after-scan', 'Continue.');
          expect(
            jsonEncode(f.requests.last),
            contains('The north gate turns purple.'),
          );
          expect(f.host.lastRun('story')!.activeWorldInfo, ['book:lore']);
          expect(f.host.lastRun('story')!.compiled.worldInfoMemoryIds, [
            memory.id,
          ]);
        },
      );

      test(
        'old and quoted markers cannot end a branch and native reasoning stays separate',
        () async {
          final f = await _Fixture.create();
          await f.scopes.authorizeEnd(
            f.plugin,
            'story',
            true,
            userGesture: true,
          );
          await f.source('old', 'story', '旧正文\n<div data-nvwa-end>旧标记</div>');
          f.reply = '正文。\n> <div data-nvwa-end>引用</div>';
          await f.generate('story', 'quote', '');
          expect((await f.repository.branch('story')).ended, isFalse);
          f.reply = '<think>格式模板</think>\n新的正文。\n<div data-nvwa-end>故事收束</div>';
          final update = await f.generate('story', 'end', '');
          expect(update, isNotNull);
          expect((await f.repository.branch('story')).endedReason, '故事收束');
          final view = await f.repository.replyView(
            update!.id,
            novelContentHash(update.content),
          );
          expect((view!['slots'] as Map)['templateReasoning'], '格式模板');
          expect(view['nativeReasoning'], '本机测试推理');
          expect(update.content, isNot(contains('格式模板')));
          expect(jsonEncode(f.requests.last), isNot(contains('本机测试推理')));
          await expectLater(
            f.generate('story', 'already-ended', ''),
            throwsException,
          );
          final fork = await f.repository.fork(
            projectId: 'story',
            newProjectId: 'survivor',
            label: '另开故事线',
            now: f.now,
          );
          expect(fork.ended, isFalse);
          expect(
            (await f.scopes.resolve(f.plugin, fork.projectId)).allowEnd,
            isFalse,
          );
        },
      );

      test(
        'markup extracts native cards and only accepts a top-level final end marker',
        () {
          final view = NovelReplyMarkup.parse(
            '————12:30•星期五•九月十三日————\n'
            '<span data-char="小林">你好</span>\n<second_space>区外</second_space>\n'
            '<div data-nvwa-ui="场景"><div>候车</div><button data-nvwa-draft="我到了">到达</button></div>'
            '<nvwa_notes>幕后</nvwa_notes>',
          );
          expect(
            view.slots.keys,
            containsAll(['timeBar', 'secondSpace', 'interaction', 'backstage']),
          );
          expect(view.drafts.single.text, '我到了');
          expect(view.body, contains('<span data-char="小林">'));
          for (final text in [
            '正文\n```html\n<div data-nvwa-end>代码</div>',
            '正文\n<blockquote>\n<div data-nvwa-end>引用</div>',
            '正文\n<div data-nvwa-end>非末尾</div>\n后续正文',
          ]) {
            expect(NovelReplyMarkup.endingReason(text), isNull);
          }
        },
      );
    },
    skip: !File('plugins/nvwa-novel/preset.json').existsSync()
        ? 'Requires a local NVWA preset'
        : false,
  );
}

class _Fixture {
  _Fixture(this.container, this.plugin);
  final ProviderContainer container;
  final InstalledPlugin plugin;
  final requests = <Map<String, Object?>>[];
  String reply = '新的一个段落。';
  final now = DateTime.utc(2026, 11, 22);
  NovelPluginRepository get repository =>
      container.read(novelPluginRepositoryProvider);
  NovelPluginHost get host => container.read(novelPluginHostProvider);
  NovelPluginScopeStore get scopes =>
      container.read(novelPluginScopeStoreProvider);

  static Future<_Fixture> create({bool automatic = false}) async {
    late _Fixture fixture;
    final container = ProviderContainer(
      overrides: [
        aiHttpClientFactoryProvider.overrideWithValue(
          () => MockClient((request) async {
            final body = Map<String, Object?>.from(
              jsonDecode(request.body) as Map,
            );
            fixture.requests.add(body);
            final memory = jsonEncode(body['messages']).contains('你整理小说的本地记忆');
            final packet = jsonEncode({
              'choices': [
                {
                  'delta': {
                    'content': memory ? '【事件】已发生事件。\n【人物关系】朋友' : fixture.reply,
                    if (!memory) 'reasoning_content': '本机测试推理',
                  },
                  'finish_reason': 'stop',
                },
              ],
            });
            return http.Response.bytes(
              utf8.encode('data: $packet\n\ndata: [DONE]\n\n'),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final config = ai
        .config(AiProviderType.deepseek)
        .copyWith(
          selectedModel: 'deepseek-flash',
          availableModels: ['deepseek-flash'],
        );
    await container.read(aiProviderConfigRepositoryProvider).saveConfig(config);
    await container
        .read(secureApiKeyStoreProvider)
        .write(config.apiKeyRef, 'local-test-credential');
    final now = DateTime.utc(2026, 11, 22);
    await container
        .read(aiProviderConfigRepositoryProvider)
        .saveDefault(
          AiDefaultSelection(
            providerId: config.id,
            modelId: config.selectedModel,
            updatedAtUtc: now,
          ),
        );
    for (final id in ['story', 'other']) {
      await container
          .read(projectRepositoryProvider)
          .upsertProject(
            Project(metadata: metadata(id), title: id, description: '一条街道。'),
          );
    }
    final plugin = InstalledPlugin(
      manifest: IbukiPluginManifest.parse(
        await File('plugins/nvwa-novel/manifest.json').readAsString(),
      ),
      installedPath: Directory('plugins/nvwa-novel').absolute.path,
      dataPath: '',
      enabled: true,
      installedAt: now,
      updatedAt: now,
    );
    await container.read(pluginRegistryProvider).upsertPlugin(plugin);
    fixture = _Fixture(container, plugin);
    await fixture.scopes.enable(plugin, 'story', true);
    await fixture.scopes.configureMemory(
      plugin,
      'story',
      automatic: automatic,
      batchSize: 4,
    );
    return fixture;
  }

  Future<void> source(
    String id,
    String projectId,
    String text, {
    bool notify = false,
  }) async {
    await container.read(createSegmentProvider)(
      projectId: projectId,
      content: text,
      id: id,
      nowUtc: now,
      notify: notify,
    );
  }

  Future<Segment?> generate(
    String id,
    String request,
    String input, {
    NovelGenerationMode mode = NovelGenerationMode.normal,
  }) async {
    final result = await container
        .read(generateNextSegmentProvider)(
          projectId: id,
          userInstruction: input,
          selectedCharacterIds: {},
          selectedWorldCardIds: {},
          requestId: request,
          segmentId: 'new-$request',
          nowUtc: now,
          mode: mode,
        )
        .toList();
    return result.last.savedSegment;
  }
}
