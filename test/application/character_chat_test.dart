import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';

void main() {
  group('character-bound chat domain', () {
    test('ChatSession JSON round-trips characterId', () {
      final session = _session('session-1', characterId: 'character-1');

      expect(ChatSession.fromJson(session.toJson()), session);
    });

    test('legacy ChatSession JSON remains unbound', () {
      final json = _session('legacy').toJson()..remove('character_id');

      expect(ChatSession.fromJson(json).characterId, isNull);
    });

    test('copyWith preserves an unspecified characterId', () {
      final session = _session('session-1', characterId: 'character-1');

      expect(session.copyWith(title: 'Renamed').characterId, 'character-1');
    });

    test('copyWith can explicitly clear characterId', () {
      final session = _session('session-1', characterId: 'character-1');

      expect(session.copyWith(characterId: null).characterId, isNull);
    });
  });
}

final _t0 = DateTime.utc(2026, 8, 10, 8);

ChatSession _session(
  String id, {
  String? projectId,
  String? characterId,
  String? title,
  DateTime? updatedAt,
}) {
  return ChatSession(
    metadata: _metadata(id, updatedAt: updatedAt),
    projectId: projectId,
    characterId: characterId,
    title: title ?? id,
  );
}

EntityMetadata _metadata(String id, {DateTime? updatedAt}) {
  return EntityMetadata(
    id: id,
    createdAt: _t0,
    updatedAt: updatedAt ?? _t0,
    revision: 1,
  );
}
