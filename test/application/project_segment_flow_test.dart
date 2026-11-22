import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/projects/create_project.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/segments/create_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';

void main() {
  group('project and segment flow use cases', () {
    test('CreateProject creates a project', () async {
      final fixture = _Fixture();

      final project = await fixture.createProject(
        title: ' 测试故事 ',
        description: ' 一个说明 ',
        id: 'project-1',
        nowUtc: DateTime.utc(2026, 1, 1),
      );

      expect(project.id, 'project-1');
      expect(project.title, '测试故事');
      expect(project.description, '一个说明');
      expect(project.revision, 1);
    });

    test('CreateProject rejects an empty title', () async {
      final fixture = _Fixture();

      expect(
        fixture.createProject(
          title: '   ',
          id: 'project-1',
          nowUtc: DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('created projects can be read from the repository', () async {
      final fixture = _Fixture();

      await fixture.createProject(
        title: '测试故事',
        id: 'project-1',
        nowUtc: DateTime.utc(2026, 1, 1),
      );

      expect((await fixture.projects.getProject('project-1')).title, '测试故事');
    });

    test('CreateSegment appends orderIndex at the end', () async {
      final fixture = _Fixture();
      await fixture.addProject('project-1');

      final first = await fixture.createSegment(
        projectId: 'project-1',
        content: '第一段',
        id: 'segment-1',
        nowUtc: DateTime.utc(2026, 1, 1),
      );
      final second = await fixture.createSegment(
        projectId: 'project-1',
        content: '第二段',
        id: 'segment-2',
        nowUtc: DateTime.utc(2026, 1, 2),
      );

      expect(first.orderIndex, 0);
      expect(second.orderIndex, 1);
    });

    test(
      'CreateSegment calculates orderIndex independently per project',
      () async {
        final fixture = _Fixture();
        await fixture.addProject('project-a');
        await fixture.addProject('project-b');
        await fixture.createSegment(
          projectId: 'project-a',
          content: 'A1',
          id: 'segment-a1',
          nowUtc: DateTime.utc(2026, 1, 1),
        );

        final segment = await fixture.createSegment(
          projectId: 'project-b',
          content: 'B1',
          id: 'segment-b1',
          nowUtc: DateTime.utc(2026, 1, 1),
        );

        expect(segment.orderIndex, 0);
      },
    );

    test('CreateSegment fails when the project does not exist', () async {
      final fixture = _Fixture();

      expect(
        fixture.createSegment(
          projectId: 'missing',
          content: '正文',
          id: 'segment-1',
          nowUtc: DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('CurrentProjectController can switch and clear project', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        currentProjectControllerProvider.notifier,
      );
      controller.selectProject('project-1');

      expect(container.read(currentProjectControllerProvider), 'project-1');

      controller.clearProject();

      expect(container.read(currentProjectControllerProvider), isNull);
    });

    test('time and ID providers can be fixed in tests', () async {
      final container = ProviderContainer(
        overrides: [
          entityIdGeneratorProvider.overrideWithValue(
            _QueueIdGenerator(['project-fixed']),
          ),
          utcClockProvider.overrideWithValue(
            _FixedClock(DateTime.utc(2026, 2, 3, 4, 5)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final project = await container.read(createProjectProvider)(
        title: '固定项目',
        id: container.read(entityIdGeneratorProvider).nextId('project'),
        nowUtc: container.read(utcClockProvider).now(),
      );

      expect(project.id, 'project-fixed');
      expect(project.createdAt, DateTime.utc(2026, 2, 3, 4, 5));
    });

    test('soft-deleted projects cannot receive new segments', () async {
      final fixture = _Fixture();
      await fixture.addProject('project-1');
      await fixture.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 2),
      );

      expect(
        fixture.createSegment(
          projectId: 'project-1',
          content: '正文',
          id: 'segment-1',
          nowUtc: DateTime.utc(2026, 1, 3),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test(
      'project list sorts by updatedAt descending then title and id',
      () async {
        final fixture = _Fixture();
        await fixture.createProject(
          title: 'B',
          id: 'project-b',
          nowUtc: DateTime.utc(2026, 1, 1),
        );
        await fixture.createProject(
          title: 'A',
          id: 'project-a',
          nowUtc: DateTime.utc(2026, 1, 2),
        );

        final projects = await fixture.projects.listProjects();

        expect(projects.map((project) => project.id), [
          'project-a',
          'project-b',
        ]);
      },
    );
  });
}

class _Fixture {
  final InMemoryIbukiStore store = InMemoryIbukiStore();
  late final InMemoryProjectRepository projects = InMemoryProjectRepository(
    store,
  );
  late final InMemorySegmentRepository segments = InMemorySegmentRepository(
    store,
  );
  late final CreateProject createProject = CreateProject(projects);
  late final CreateSegment createSegment = CreateSegment(projects, segments);

  Future<void> addProject(String id) {
    return createProject(title: id, id: id, nowUtc: DateTime.utc(2026, 1, 1));
  }
}

class _QueueIdGenerator extends EntityIdGenerator {
  _QueueIdGenerator(Iterable<String> ids) : _ids = Queue.of(ids);

  final Queue<String> _ids;

  @override
  String nextId(String prefix) => _ids.removeFirst();
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
