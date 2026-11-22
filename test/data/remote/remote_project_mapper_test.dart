import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/remote/mappers/remote_project_mapper.dart';

import 'remote_test_helpers.dart';

void main() {
  group('remote project mappers', () {
    test('ProjectDetail maps to local domain model', () {
      final project = projectFromRemoteDetail(projectDetailFixture());
      expect(project.id, 'project-alpha');
      expect(project.title, '雨夜试写');
      expect(project.createdAt.isUtc, isTrue);
    });

    test(
      'ProjectSummary maps to local domain model with updatedAt as createdAt',
      () {
        final project = projectFromRemoteSummary(projectListFixture().single);
        expect(project.id, 'project-alpha');
        expect(project.createdAt, project.updatedAt);
        expect(project.revision, 3);
      },
    );
  });
}
