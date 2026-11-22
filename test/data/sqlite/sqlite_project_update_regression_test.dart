import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/save_ai_model_binding.dart';
import 'package:ibukihome/application/projects/save_project_system_prompt.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test('project updates preserve child rows and scoped AI binding', () async {
    final fixture = await SqliteFixture.create();
    final initial = project(
      'project-1',
      title: '原作品名',
      description: '原简介',
    ).copyWith(aiProviderConfigId: 'deepseek', aiModel: 'deepseek-v4-flash');
    await fixture.projects.upsertProject(initial);
    await fixture.segments.upsertSegment(
      segment('segment-1', initial.id, 0, content: '原正文'),
    );
    await fixture.outlines.upsertOutlineNode(
      outlineNode('outline-1', initial.id, 0, title: '原大纲'),
    );

    final saved = await SaveProjectSystemPrompt(fixture.projects)(
      projectId: initial.id,
      systemPrompt: '使用克制的第三人称叙事。',
      nowUtc: DateTime.utc(2026, 8, 21, 10),
    );

    expect(saved.title, '原作品名');
    expect(saved.description, '原简介');
    expect(saved.aiProviderConfigId, 'deepseek');
    expect(saved.aiModel, 'deepseek-v4-flash');
    expect(saved.systemPrompt, '使用克制的第三人称叙事。');
    expect(await fixture.segments.getSegment('segment-1'), isNotNull);
    expect(await fixture.outlines.getOutlineNode('outline-1'), isNotNull);

    await SaveProjectAiBinding(fixture.projects)(
      projectId: initial.id,
      providerConfigId: 'gemini',
      model: 'gemini-3.1-flash-lite',
      nowUtc: DateTime.utc(2026, 8, 21, 11),
    );
    final rebound = await fixture.projects.getProject(initial.id);
    expect(rebound.systemPrompt, '使用克制的第三人称叙事。');
    expect(rebound.aiProviderConfigId, 'gemini');
    expect(rebound.aiModel, 'gemini-3.1-flash-lite');
    expect((await fixture.segments.listSegments(initial.id)), hasLength(1));
    expect((await fixture.outlines.listOutlineNodes(initial.id)), hasLength(1));

    await fixture.database.close();
    final reopened = await reopenFixture(fixture);
    final restored = await reopened.projects.getProject(initial.id);
    expect(restored.title, initial.title);
    expect(restored.description, initial.description);
    expect(restored.systemPrompt, saved.systemPrompt);
    expect(restored.aiProviderConfigId, 'gemini');
    expect(restored.aiModel, 'gemini-3.1-flash-lite');
    expect(await reopened.segments.getSegment('segment-1'), isNotNull);
    expect(await reopened.outlines.getOutlineNode('outline-1'), isNotNull);
  });

  test('chat session AI binding survives database reopen', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('project-1'));
    await fixture.chatRepository.upsertSession(chatSession('session-1', null));

    await SaveChatSessionAiBinding(fixture.chatRepository)(
      sessionId: 'session-1',
      providerConfigId: 'gemini',
      model: 'gemini-3.1-flash-lite',
      nowUtc: DateTime.utc(2026, 8, 21, 12),
    );

    await fixture.database.close();
    final reopened = await reopenFixture(fixture);
    final session = await reopened.chatRepository.getSession('session-1');
    expect(session.aiProviderConfigId, 'gemini');
    expect(session.aiModel, 'gemini-3.1-flash-lite');
    expect(session.projectId, isNull);
  });

  test('new project still inserts normally after update-safe upsert', () async {
    final fixture = await SqliteFixture.create();
    await fixture.projects.upsertProject(project('new-project'));
    expect(
      (await fixture.projects.getProject('new-project')).title,
      'new-project',
    );
  });
}
