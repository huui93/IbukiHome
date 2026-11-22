import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart' as domain;
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/segments/segment_revision.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  group('domain models', () {
    test('Project JSON round-trips', () {
      final project = Project(
        metadata: _metadata('project-1'),
        title: '伊吹之家',
        description: '长篇写作项目',
      );

      expect(Project.fromJson(_json(project.toJson())), project);
    });

    test('Segment JSON round-trips', () {
      final segment = Segment(
        metadata: _metadata('segment-1', revision: 2),
        projectId: 'project-1',
        orderIndex: 3,
        content: '她推开门，听见雨声。',
      );

      expect(Segment.fromJson(_json(segment.toJson())), segment);
    });

    test('SegmentRevision JSON round-trips', () {
      final revision = SegmentRevision(
        metadata: _metadata('revision-1'),
        projectId: 'project-1',
        segmentId: 'segment-1',
        revisionNumber: 2,
        content: '旧正文',
        note: '手动保存',
        userInstruction: '改得轻一点',
        mode: 'local_edit',
      );

      expect(SegmentRevision.fromJson(_json(revision.toJson())), revision);
    });

    test('CharacterCard JSON round-trips', () {
      final character = CharacterCard(
        metadata: _metadata('character-1'),
        projectId: 'project-1',
        name: '伊吹',
        content: '角色设定正文',
        sortOrder: 1,
      );

      expect(CharacterCard.fromJson(_json(character.toJson())), character);
    });

    test('WorldCard JSON round-trips', () {
      final card = WorldCard(
        metadata: _metadata('world-1'),
        projectId: 'project-1',
        title: '旧城',
        content: '世界观正文',
        sortOrder: 2,
      );

      expect(WorldCard.fromJson(_json(card.toJson())), card);
    });

    test('ChatSession JSON round-trips', () {
      final session = ChatSession(
        metadata: _metadata('session-1'),
        projectId: null,
        title: '随便聊聊',
      );

      expect(ChatSession.fromJson(_json(session.toJson())), session);
    });

    test('ChatMessage JSON round-trips', () {
      final message = domain.ChatMessage(
        metadata: _metadata('message-1'),
        sessionId: 'session-1',
        projectId: 'project-1',
        role: ChatMessageRole.assistant,
        content: '我先把这个念头接住。',
      );

      expect(domain.ChatMessage.fromJson(_json(message.toJson())), message);
    });

    test('unknown JSON fields are ignored', () {
      final json = _json(
        Project(
          metadata: _metadata('project-1'),
          title: '伊吹之家',
          description: '说明',
        ).toJson(),
      )..['future_field'] = 'safe to ignore';

      expect(Project.fromJson(json).title, '伊吹之家');
    });

    test('dates are restored as UTC', () {
      final project = Project.fromJson({
        'id': 'project-utc',
        'created_at': '2026-01-01T08:00:00+08:00',
        'updated_at': '2026-01-01T09:30:00+08:00',
        'revision': 1,
        'deleted_at': null,
        'title': 'UTC',
        'description': '',
      });

      expect(project.createdAt.isUtc, isTrue);
      expect(project.createdAt, DateTime.utc(2026, 1, 1));
      expect(project.updatedAt, DateTime.utc(2026, 1, 1, 1, 30));
    });

    test('missing required fields throw clear format errors', () {
      expect(
        () => Project.fromJson({
          'id': 'project-bad',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'revision': 1,
        }),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('copyWith keeps unspecified fields', () {
      final original = Segment(
        metadata: _metadata('segment-1'),
        projectId: 'project-1',
        orderIndex: 7,
        content: '旧正文',
      );

      final updated = original.copyWith(content: '新正文');

      expect(updated.projectId, original.projectId);
      expect(updated.orderIndex, original.orderIndex);
      expect(updated.metadata, original.metadata);
      expect(updated.content, '新正文');
    });

    test('equal values compare as equal', () {
      final left = Project(
        metadata: _metadata('project-1'),
        title: '伊吹之家',
        description: '说明',
      );
      final right = Project(
        metadata: _metadata('project-1'),
        title: '伊吹之家',
        description: '说明',
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });
  });
}

EntityMetadata _metadata(String id, {int revision = 1}) {
  return EntityMetadata(
    id: id,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    revision: revision,
  );
}

Map<String, dynamic> _json(Map<String, Object?> value) {
  return Map<String, dynamic>.from(value);
}
