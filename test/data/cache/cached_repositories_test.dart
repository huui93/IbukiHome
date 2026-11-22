import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/cache/cached_outline_repository.dart';
import 'package:ibukihome/data/cache/cached_repositories.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_outline_repository.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';

void main() {
  group('performance-oriented repository snapshots', () {
    test('cache invalidation exposes out-of-band restored data', () async {
      final store = InMemoryIbukiStore();
      final delegate = InMemoryProjectRepository(store);
      final cached = CachedProjectRepository(delegate);

      expect(await cached.listProjects(), isEmpty);
      await delegate.upsertProject(_project());
      expect(await cached.listProjects(), isEmpty);

      cached.invalidateAll();
      expect((await cached.listProjects()).single.title, '性能测试作品');
    });

    test('1000 segments stay cached and writes update the snapshot', () async {
      final store = InMemoryIbukiStore();
      final projects = InMemoryProjectRepository(store);
      final delegate = InMemorySegmentRepository(store);
      await projects.upsertProject(_project());
      for (var index = 0; index < 1000; index += 1) {
        await delegate.upsertSegment(_segment(index));
      }
      final cached = CachedSegmentRepository(delegate);

      expect(await cached.listSegments('project-1'), hasLength(1000));
      for (var index = 0; index < 20; index += 1) {
        expect(await cached.listSegments('project-1'), hasLength(1000));
      }

      expect(cached.metrics.delegateReads, 1);
      expect(cached.metrics.cacheHits, 20);
      expect(cached.retainedEntryCount, 1000);

      await cached.upsertSegment(_segment(1000));
      expect(await cached.listSegments('project-1'), hasLength(1001));
      expect(cached.metrics.delegateReads, 1);
      expect(cached.retainedEntryCount, 1001);
    });

    test('5000 messages append without reloading chat history', () async {
      final store = InMemoryIbukiStore();
      final delegate = InMemoryChatRepository(store);
      await delegate.upsertSession(_session());
      final cached = CachedChatRepository(delegate);

      expect(await cached.listSessions(), hasLength(1));
      expect(await cached.listMessages('session-1'), isEmpty);
      for (var index = 0; index < 5000; index += 1) {
        final at = _now.add(Duration(seconds: index + 1));
        await cached.appendMessageAndTouchSession(_message(index, at), at);
      }

      final messages = await cached.listMessages('session-1');
      expect(messages, hasLength(5000));
      expect(messages.first.id, 'message-0000');
      expect(messages.last.id, 'message-4999');
      expect(cached.metrics.delegateReads, 2);
      expect(cached.retainedEntryCount, 5001);

      final stableEntries = cached.retainedEntryCount;
      for (var index = 0; index < 20; index += 1) {
        expect(await cached.listMessages('session-1'), hasLength(5000));
      }
      expect(cached.metrics.delegateReads, 2);
      expect(cached.retainedEntryCount, stableEntries);
    });

    test('100 personas remain resident without repeated queries', () async {
      final store = InMemoryIbukiStore();
      final delegate = InMemoryChatPersonaRepository(store);
      for (var index = 0; index < 100; index += 1) {
        await delegate.upsertPersona(_persona(index));
      }
      final cached = CachedChatPersonaRepository(delegate);

      expect(await cached.listPersonas(), hasLength(100));
      for (var index = 0; index < 50; index += 1) {
        expect(await cached.listPersonas(), hasLength(100));
      }

      expect(cached.metrics.delegateReads, 1);
      expect(cached.metrics.cacheHits, 50);
      expect(cached.retainedEntryCount, 100);
    });

    test(
      'outline context stays cached and status updates incrementally',
      () async {
        final store = InMemoryIbukiStore();
        final projects = InMemoryProjectRepository(store);
        final delegate = InMemoryOutlineRepository(store);
        await projects.upsertProject(_project());
        await delegate.upsertOutlineNode(_outline('outline-1', 0));
        await delegate.upsertOutlineNode(_outline('outline-2', 1));
        final cached = CachedOutlineRepository(delegate);

        expect(await cached.listOutlineNodes('project-1'), hasLength(2));
        for (var index = 0; index < 20; index += 1) {
          expect(await cached.listOutlineNodes('project-1'), hasLength(2));
        }
        await cached.setOutlineNodeStatus(
          id: 'outline-2',
          status: OutlineNodeStatus.current,
          updatedAt: _now.add(const Duration(minutes: 1)),
        );

        final nodes = await cached.listOutlineNodes('project-1');
        expect(
          nodes.singleWhere((item) => item.id == 'outline-2').status,
          OutlineNodeStatus.current,
        );
        expect(cached.metrics.delegateReads, 1);
        expect(cached.metrics.cacheHits, greaterThanOrEqualTo(21));
        expect(cached.retainedEntryCount, 2);
      },
    );
  });
}

final _now = DateTime.utc(2026, 8, 11, 8);

EntityMetadata _metadata(String id, [DateTime? at]) {
  return EntityMetadata(
    id: id,
    createdAt: at ?? _now,
    updatedAt: at ?? _now,
    revision: 1,
  );
}

Project _project() {
  return Project(
    metadata: _metadata('project-1'),
    title: '性能测试作品',
    description: '仅使用合成测试数据',
  );
}

Segment _segment(int index) {
  return Segment(
    metadata: _metadata('segment-${index.toString().padLeft(4, '0')}'),
    projectId: 'project-1',
    orderIndex: index,
    content: '第 $index 段性能测试正文。',
  );
}

ChatSession _session() {
  return ChatSession(
    metadata: _metadata('session-1'),
    projectId: null,
    title: '性能测试会话',
  );
}

ChatMessage _message(int index, DateTime at) {
  return ChatMessage(
    metadata: _metadata('message-${index.toString().padLeft(4, '0')}', at),
    sessionId: 'session-1',
    projectId: null,
    role: index.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
    content: '第 $index 条性能测试消息',
  );
}

ChatPersona _persona(int index) {
  return ChatPersona(
    metadata: _metadata('persona-${index.toString().padLeft(3, '0')}'),
    name: '测试角色 $index',
    descriptionMode: ChatPersonaDescriptionMode.simple,
    shortDescription: '仅用于缓存压力测试',
    speakingStyle: '简洁自然',
  );
}

OutlineNode _outline(String id, int orderIndex) {
  return OutlineNode(
    metadata: _metadata(id),
    projectId: 'project-1',
    title: '大纲 $orderIndex',
    summary: '用于创作上下文缓存测试。',
    orderIndex: orderIndex,
    status: OutlineNodeStatus.planned,
  );
}
