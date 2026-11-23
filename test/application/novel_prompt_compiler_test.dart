import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/novel_prompt_compiler.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/plugins/novel_plugin_models.dart';

const core = AiGenerationRequest(
  requestId: 'novel-preset',
  systemPrompt: '本作设定：未来空间站',
  messages: [],
  maxTokens: 512,
);
const variables = {
  'char': '林晚',
  'user': '作者',
  'group': '林晚、陈叔',
  'scenario': '空间站',
  'personality': '谨慎',
  'date': '2026-11-22',
  'time': '16:00',
};
List<NovelHistoryMessage> history() => [
  for (var i = 0; i < 4; i++)
    NovelHistoryMessage(
      id: 'm$i',
      segmentId: 's$i',
      candidateId: 'c$i',
      content: '正文$i',
      revision: 1,
      createdAt: DateTime.utc(2026),
    ),
];
NovelCompiledPrompt compile(
  NovelPluginPreset preset, {
  Map<String, Object?> settings = const {},
  List<NovelMemoryBlock> memories = const [],
  Set<String> exclude = const {},
  String provider = 'openai',
}) => const NovelPromptCompiler().compile(
  core: core,
  preset: preset,
  settings: settings,
  resources: const {},
  variables: variables,
  placeholders: const {},
  history: history(),
  authorInput: '推开门',
  memories: memories,
  excludedMessageIds: exclude,
  providerType: provider,
  model: 'test-model',
);

void main() {
  test(
    'actual NVWA keeps 99 independent entries and changing tone changes the transmitted resource',
    () {
      final directory = Directory('plugins/nvwa-novel');
      final preset = NovelPluginPreset.fromJson(
        Map<String, Object?>.from(
          jsonDecode(File('${directory.path}/preset.json').readAsStringSync())
              as Map,
        ),
      );
      final resources = {
        for (final entry in preset.entries)
          if (entry.resource != null)
            entry.resource!: File(
              '${directory.path}/${entry.resource}',
            ).readAsStringSync(),
      };
      expect(preset.entries.length, 99);
      expect(resources.length, 91);
      expect(resources.containsKey('prompts/main.txt'), isTrue);
      expect(resources.containsKey('prompts/nvwa_ban_expr.txt'), isTrue);
      NovelCompiledPrompt run(String tone) =>
          const NovelPromptCompiler().compile(
            core: core,
            preset: preset,
            settings: {
              'groups': {'tone': tone},
            },
            resources: resources,
            variables: variables,
            placeholders: const {},
            history: history(),
            authorInput: '让人物调查异响',
          );
      final natural = run('nvwa_style_tone_ziran');
      final suspense = run('nvwa_style_tone_xuanyi');
      expect(
        natural.blocks.any((b) => b.id == 'nvwa_style_tone_ziran'),
        isTrue,
      );
      expect(
        natural.blocks.any((b) => b.id == 'nvwa_style_tone_xuanyi'),
        isFalse,
      );
      expect(
        suspense.blocks.any((b) => b.id == 'nvwa_style_tone_xuanyi'),
        isTrue,
      );
      expect(
        suspense.blocks.any((b) => b.id == 'nvwa_style_tone_ziran'),
        isFalse,
      );
      expect(
        natural.request.systemPrompt,
        isNot(suspense.request.systemPrompt),
      );
      expect(
        suspense.request.messages.map((m) => m.content).join(),
        contains('正文0'),
      );
      expect(suspense.request.maxTokens, 8192);
    },
    skip: !File('plugins/nvwa-novel/preset.json').existsSync()
        ? 'Requires a local NVWA preset'
        : false,
  );
  test(
    'roles, history depth, generation modes and macros remain independent',
    () {
      final preset = NovelPluginPreset(
        id: 'test',
        entries: const [
          NovelPromptEntry(
            id: 'head',
            name: 'head',
            enabled: true,
            text: '{{char}} / {{user}} / {{date}}',
          ),
          NovelPromptEntry(
            id: 'history',
            name: 'history',
            enabled: true,
            placeholder: 'chatHistory',
            order: 10,
          ),
          NovelPromptEntry(
            id: 'depth',
            name: 'depth',
            enabled: true,
            text: '深度一',
            position: NovelPromptPosition.inHistory,
            depth: 1,
          ),
          NovelPromptEntry(
            id: 'regen',
            name: 'regen',
            enabled: true,
            text: '仅重生成',
            modes: ['regenerate'],
          ),
        ],
      );
      final result = compile(preset);
      expect(result.request.systemPrompt, contains('林晚 / 作者 / 2026-11-22'));
      final ids = result.blocks.map((b) => b.id).toList();
      expect(ids.indexOf('depth'), ids.indexOf('history:m3') - 1);
      expect(ids, isNot(contains('regen')));
      expect(
        result.request.messages.singleWhere((m) => m.content == '深度一').role,
        AiMessageRole.system,
      );
      final native = compile(preset, provider: 'gemini');
      expect(
        native.request.messages
            .singleWhere((m) => m.content.contains('深度一'))
            .role,
        AiMessageRole.user,
      );
      expect(native.notes.any((n) => n.contains('system')), isTrue);
    },
  );
  test(
    'history filtering preserves source messages and only opted-in memory enters world info scanning',
    () {
      final original = history();
      const preset = NovelPluginPreset(id: 'test', entries: []);
      final result = compile(
        preset,
        exclude: {'m0'},
        memories: const [
          NovelMemoryBlock(id: 'summary', content: '摘要'),
          NovelMemoryBlock(
            id: 'recall',
            content: '触发词',
            scanForWorldInfo: true,
          ),
        ],
      );
      expect(result.blocks.any((b) => b.historyId == 'm0'), isFalse);
      expect(original.first.content, '正文0');
      expect(result.worldInfoMemoryIds, ['recall']);
      expect(
        () => compile(preset, exclude: {'another-branch-message'}),
        throwsA(isA<NovelPluginRequestException>()),
      );
    },
  );
  test(
    'context/output limits, nonrecursive expansion and wire diagnostics are honest',
    () {
      final preset = NovelPluginPreset(
        id: 'test',
        entries: const [
          NovelPromptEntry(
            id: 'main',
            name: 'main',
            enabled: true,
            text: '{{char}}',
          ),
        ],
        request: const {'contextTokens': 900, 'outputTokens': 99999},
      );
      final result = const NovelPromptCompiler().compile(
        core: core,
        preset: preset,
        settings: const {},
        resources: const {},
        variables: const {'char': '{{user}}'},
        placeholders: const {},
        history: history(),
        authorInput: '短输入',
        modelContextLimit: 800,
        modelOutputLimit: 256,
        projectOutputTokenLimit: 300,
        projectTemperature: .4,
      );
      expect(result.request.temperature, .4);
      expect(result.requested['projectOutputTokenLimit'], 300);
      expect(result.request.systemPrompt, contains('{{user}}'));
      expect(result.effective['contextTokens'], 800);
      expect(result.request.maxTokens, 256);
      result.request.reportAppliedParameters({
        'max_completion_tokens': 128,
        'stream': true,
      });
      expect(result.wireParameters['max_completion_tokens'], 128);
      expect(result.requested['outputTokens'], 99999);
    },
  );
  test(
    'ambiguous groups, unsafe paths and oversized mandatory instructions are rejected',
    () {
      final preset = NovelPluginPreset(
        id: 'test',
        entries: const [
          NovelPromptEntry(id: 'a', name: 'a', enabled: true),
          NovelPromptEntry(id: 'b', name: 'b', enabled: true),
        ],
        groups: const {
          'tone': ['a', 'b'],
        },
      );
      expect(
        () => compile(preset),
        throwsA(isA<NovelPluginRequestException>()),
      );
      expect(
        () => NovelPromptEntry.fromJson({
          'id': 'bad',
          'resource': '../escape.txt',
        }),
        throwsFormatException,
      );
      expect(
        () => compile(
          NovelPluginPreset(
            id: 'large',
            entries: [
              NovelPromptEntry(
                id: 'main',
                name: 'main',
                enabled: true,
                text: '必需内容' * 10000,
              ),
            ],
            request: const {'contextTokens': 1024},
          ),
        ),
        throwsA(isA<NovelPluginRequestException>()),
      );
    },
  );
}
