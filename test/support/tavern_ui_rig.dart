import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/tavern/provider/tavern_model_profile_store.dart';
import 'package:ibukihome/application/tavern/tavern_story_service.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_controller.dart';
import 'package:ibukihome/data/secure/secure_ai_provider_config_repository.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/world/world_card.dart';
import '../application/tavern_orchestrator_test.dart' as integration;

class TavernUiRig {
  late Directory directory;
  late IbukiDatabase db;
  late SQLiteTavernRepository repo;
  late TavernStoryService service;
  late integration.TavernTestEnvironment env;
  final controllers = <TavernSessionController>[];
  final traces = TavernTraceCache();
  Future<void> initialize() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('tavern-ui-');
    db = database('source.db');
    repo = SQLiteTavernRepository(db);
    final project = SQLiteProjectRepository(db),
        cards = SQLiteCharacterRepository(db),
        worlds = SQLiteWorldRoleplayRepository(db);
    final now = DateTime.utc(2026);
    await project.upsertProject(
      Project(
        metadata: EntityMetadata(
          id: 'project',
          createdAt: now,
          updatedAt: now,
          revision: 1,
        ),
        title: 'Synthetic',
        description: '',
      ),
    );
    await integration.seed(repo, cards, worlds);
    env = integration.TavernTestEnvironment(repo, cards, worlds);
    await env.initialize();
    service = TavernStoryService(
      repository: repo,
      characters: cards,
      worlds: worlds,
      worldCards: SQLiteWorldRepository(db),
      projects: project,
      configs: SecureAiProviderConfigRepository(env.secure),
      profiles: TavernModelProfileStore(env.secure),
      ids: EntityIdGenerator(),
    );
    await service.profiles.save(env.binding);
    await service.saveSettings('s', {
      'tavernBindingV1': await service.modelSettings(
        env.binding.config,
        env.binding.model,
      ),
      'tavernSceneV1': {
        'name': 'Dining Hall',
        'description': 'A bright shared table.',
        'timeText': 'Evening',
      },
    });
    await service.worldCards.upsertWorldCard(
      WorldCard(
        metadata: EntityMetadata(
          id: 'world-card',
          createdAt: now,
          updatedAt: now,
          revision: 1,
        ),
        projectId: 'project',
        title: 'Real World Card',
        content: 'World card content',
        sortOrder: 0,
      ),
    );
  }

  IbukiDatabase database(String file) => IbukiDatabase(
    pathResolver: () async => p.join(directory.path, file),
    databaseFactory: databaseFactoryFfi,
  );
  TavernSessionController controller([String id = 's']) {
    final c = TavernSessionController(
      sessionId: id,
      service: service,
      owner: env.owner,
      traces: traces,
    );
    controllers.add(c);
    return c;
  }

  Future<void> dispose() async {
    for (final c in controllers) {
      c.dispose();
    }
    await env.owner.dispose();
    await db.close();
    await directory.delete(recursive: true);
  }
}

class ControlledTavernTransport extends http.BaseClient {
  final stream = StreamController<List<int>>();
  final started = Completer<void>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    started.complete();
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void text(String value) => stream.add(
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': value},
          },
        ],
      })}\n\n',
    ),
  );
  @override
  void close() {
    closed = true;
    if (!stream.isClosed) unawaited(stream.close());
  }
}
