import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/remote/mappers/remote_segment_mapper.dart';

import 'remote_test_helpers.dart';

void main() {
  group('remote segment mapper', () {
    test('Segment DTO maps to local domain model', () {
      final segment = segmentFromRemote(segmentListFixture().first);
      expect(segment.id, 'segment-alpha-1');
      expect(segment.projectId, 'project-alpha');
      expect(segment.orderIndex, 0);
      expect(segment.createdAt.isUtc, isTrue);
    });

    test('Segment mapper preserves revision', () {
      final segment = segmentFromRemote(segmentListFixture().first);
      expect(segment.revision, 2);
    });
  });
}
