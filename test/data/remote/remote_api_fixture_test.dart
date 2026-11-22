import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/network/api_client_exceptions.dart';
import 'package:ibukihome/data/remote/dto/project_detail_dto.dart';

import 'remote_test_helpers.dart';

void main() {
  group('remote API fixtures', () {
    test('health fixture parses', () {
      final dto = healthFixture();
      expect(dto.apiVersion, 1);
      expect(dto.status, 'ok');
    });

    test('capabilities fixture parses', () {
      final dto = capabilitiesFixture();
      expect(dto.readOnly, isTrue);
      expect(dto.supportsWrite, isFalse);
    });

    test('project list fixture parses', () {
      final items = projectListFixture();
      expect(items, hasLength(1));
      expect(items.single.id, 'project-alpha');
    });

    test('project detail fixture parses', () {
      final dto = projectDetailFixture();
      expect(dto.title, '雨夜试写');
      expect(dto.segmentCount, 2);
    });

    test('segment list fixture parses', () {
      final items = segmentListFixture();
      expect(items.map((item) => item.orderIndex), [0, 1]);
    });

    test('API error fixture parses', () {
      final dto = apiErrorFixture();
      expect(dto.code, 'not_found');
      expect(dto.requestId, 'req-fixture-error');
    });

    test('UTC dates are restored as UTC', () {
      final dto = projectDetailFixture();
      expect(dto.createdAt.isUtc, isTrue);
      expect(dto.updatedAt.isUtc, isTrue);
    });

    test('unknown fields are ignored', () {
      final dto = ProjectDetailDto.fromJson({
        ...projectDetailFixtureJson(),
        'extra_future_field': 'ignored',
      });
      expect(dto.id, 'project-alpha');
    });

    test('missing key fails with protocol exception', () {
      final json = projectDetailFixtureJson()..remove('title');
      expect(
        () => ProjectDetailDto.fromJson(json),
        throwsA(isA<RemoteProtocolException>()),
      );
    });
  });
}

Map<String, dynamic> projectDetailFixtureJson() {
  return fixtureJson('project_detail_response.json');
}
