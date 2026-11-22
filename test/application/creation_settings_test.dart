import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/outline/create_outline_node.dart';
import 'package:ibukihome/application/outline/reorder_outline_nodes.dart';
import 'package:ibukihome/application/outline/save_outline_node.dart';
import 'package:ibukihome/application/outline/set_outline_node_status.dart';
import 'package:ibukihome/application/outline/soft_delete_outline_node.dart';
import 'package:ibukihome/application/projects/save_project_system_prompt.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_outline_repository.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  group('project system prompt', () {
    test('saves trimmed prompt and advances project revision', () async {
      final fixture = await _Fixture.create();
      final updated = await fixture.savePrompt(
        projectId: 'project-1',
        systemPrompt: '  Keep a restrained third-person voice.  ',
        nowUtc: _later,
      );
      expect(updated.systemPrompt, 'Keep a restrained third-person voice.');
      expect(updated.revision, 2);
      expect(
        (await fixture.projects.getProject('project-1')).systemPrompt,
        updated.systemPrompt,
      );
    });

    test('unchanged prompt is a no-op', () async {
      final fixture = await _Fixture.create(
        firstPrompt: 'Keep a restrained voice.',
      );
      final updated = await fixture.savePrompt(
        projectId: 'project-1',
        systemPrompt: ' Keep a restrained voice. ',
        nowUtc: _later,
      );
      expect(updated.revision, 1);
    });

    test('prompts remain isolated between projects', () async {
      final fixture = await _Fixture.create();
      await fixture.savePrompt(
        projectId: 'project-1',
        systemPrompt: 'Project one rules.',
        nowUtc: _later,
      );
      expect(
        (await fixture.projects.getProject('project-2')).systemPrompt,
        isEmpty,
      );
    });
  });

  group('outline use cases', () {
    test('creates planned nodes in stable order', () async {
      final fixture = await _Fixture.create();
      final first = await fixture.createOutline(
        projectId: 'project-1',
        title: ' Opening ',
        summary: ' Begin quietly. ',
        id: 'outline-1',
        nowUtc: _now,
      );
      final second = await fixture.createOutline(
        projectId: 'project-1',
        title: 'Discovery',
        summary: '',
        id: 'outline-2',
        nowUtc: _later,
      );
      expect(first.title, 'Opening');
      expect(first.summary, 'Begin quietly.');
      expect(first.status, OutlineNodeStatus.planned);
      expect([first.orderIndex, second.orderIndex], [0, 1]);
    });

    test('empty title fails', () async {
      final fixture = await _Fixture.create();
      expect(
        fixture.createOutline(
          projectId: 'project-1',
          title: ' ',
          summary: '',
          id: 'outline-1',
          nowUtc: _now,
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('edits title and summary without changing status', () async {
      final fixture = await _Fixture.withNodes();
      final updated = await fixture.saveOutline(
        projectId: 'project-1',
        outlineNodeId: 'outline-1',
        title: 'Updated',
        summary: 'Updated summary',
        nowUtc: _later,
      );
      expect(updated.title, 'Updated');
      expect(updated.summary, 'Updated summary');
      expect(updated.status, OutlineNodeStatus.planned);
      expect(updated.revision, 2);
    });

    test('soft delete hides node from active list', () async {
      final fixture = await _Fixture.withNodes();
      await fixture.deleteOutline(
        projectId: 'project-1',
        outlineNodeId: 'outline-1',
        nowUtc: _later,
      );
      expect(
        await fixture.outlines.listOutlineNodes('project-1'),
        hasLength(1),
      );
      expect(
        await fixture.outlines.listOutlineNodes(
          'project-1',
          includeDeleted: true,
        ),
        hasLength(2),
      );
    });

    test('reorders every active node', () async {
      final fixture = await _Fixture.withNodes();
      final ordered = await fixture.reorder(
        projectId: 'project-1',
        orderedIds: const ['outline-2', 'outline-1'],
        nowUtc: _later,
      );
      expect(ordered.map((item) => item.id), ['outline-2', 'outline-1']);
    });

    test('rejects incomplete reorder input', () async {
      final fixture = await _Fixture.withNodes();
      expect(
        fixture.reorder(
          projectId: 'project-1',
          orderedIds: const ['outline-1'],
          nowUtc: _later,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('switching current demotes the previous current to planned', () async {
      final fixture = await _Fixture.withNodes();
      await fixture.setStatus(
        projectId: 'project-1',
        outlineNodeId: 'outline-1',
        status: OutlineNodeStatus.current,
        nowUtc: _later,
      );
      final nodes = await fixture.setStatus(
        projectId: 'project-1',
        outlineNodeId: 'outline-2',
        status: OutlineNodeStatus.current,
        nowUtc: _later.add(const Duration(minutes: 1)),
      );
      expect(
        nodes
            .where((item) => item.status == OutlineNodeStatus.current)
            .single
            .id,
        'outline-2',
      );
      expect(
        nodes.singleWhere((item) => item.id == 'outline-1').status,
        OutlineNodeStatus.planned,
      );
    });

    test('supports completed and planned status transitions', () async {
      final fixture = await _Fixture.withNodes();
      await fixture.setStatus(
        projectId: 'project-1',
        outlineNodeId: 'outline-1',
        status: OutlineNodeStatus.completed,
        nowUtc: _later,
      );
      final nodes = await fixture.setStatus(
        projectId: 'project-1',
        outlineNodeId: 'outline-1',
        status: OutlineNodeStatus.planned,
        nowUtc: _later.add(const Duration(minutes: 1)),
      );
      expect(nodes.first.status, OutlineNodeStatus.planned);
    });

    test('nodes remain isolated between projects', () async {
      final fixture = await _Fixture.withNodes();
      await fixture.createOutline(
        projectId: 'project-2',
        title: 'Other project',
        summary: '',
        id: 'outline-other',
        nowUtc: _now,
      );
      expect(
        await fixture.outlines.listOutlineNodes('project-1'),
        hasLength(2),
      );
      expect(
        await fixture.outlines.listOutlineNodes('project-2'),
        hasLength(1),
      );
    });
  });
}

class _Fixture {
  _Fixture(this.projects, this.outlines)
    : savePrompt = SaveProjectSystemPrompt(projects),
      createOutline = CreateOutlineNode(projects, outlines),
      saveOutline = SaveOutlineNode(outlines),
      deleteOutline = SoftDeleteOutlineNode(outlines),
      reorder = ReorderOutlineNodes(outlines),
      setStatus = SetOutlineNodeStatus(outlines);

  final InMemoryProjectRepository projects;
  final InMemoryOutlineRepository outlines;
  final SaveProjectSystemPrompt savePrompt;
  final CreateOutlineNode createOutline;
  final SaveOutlineNode saveOutline;
  final SoftDeleteOutlineNode deleteOutline;
  final ReorderOutlineNodes reorder;
  final SetOutlineNodeStatus setStatus;

  static Future<_Fixture> create({String firstPrompt = ''}) async {
    final store = InMemoryIbukiStore();
    final projects = InMemoryProjectRepository(store);
    final outlines = InMemoryOutlineRepository(store);
    await projects.upsertProject(_project('project-1', firstPrompt));
    await projects.upsertProject(_project('project-2', ''));
    return _Fixture(projects, outlines);
  }

  static Future<_Fixture> withNodes() async {
    final fixture = await create();
    await fixture.createOutline(
      projectId: 'project-1',
      title: 'First',
      summary: '',
      id: 'outline-1',
      nowUtc: _now,
    );
    await fixture.createOutline(
      projectId: 'project-1',
      title: 'Second',
      summary: '',
      id: 'outline-2',
      nowUtc: _later,
    );
    return fixture;
  }
}

Project _project(String id, String systemPrompt) {
  return Project(
    metadata: EntityMetadata(
      id: id,
      createdAt: _now,
      updatedAt: _now,
      revision: 1,
    ),
    title: id,
    description: '',
    systemPrompt: systemPrompt,
  );
}

final _now = DateTime.utc(2026, 8, 12, 8);
final _later = DateTime.utc(2026, 8, 12, 9);
