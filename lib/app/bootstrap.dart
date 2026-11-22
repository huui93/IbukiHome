import '../data/sqlite/sqlite_novel_plugin_state_store.dart';
import '../data/sqlite/sqlite_novel_plugin_repository.dart';
import '../application/plugins/novel_plugin_providers.dart';
import '../application/projects/novel_output_limits_providers.dart';
import '../data/sqlite/sqlite_novel_output_limits_repository.dart';
import '../application/chat/chat_avatar_store.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../application/ai/ai_settings_controller.dart';
import '../application/backup/backup_archive_codec.dart';
import '../application/backup/backup_providers.dart';
import '../application/backup/file_backup_asset_store.dart';
import '../application/import/sillytavern_asset_store.dart';
import '../application/import/sillytavern_import_providers.dart';
import '../application/plugins/plugin_manager.dart';
import '../application/plugins/plugin_package_picker.dart';
import '../application/plugins/plugin_providers.dart';
import '../application/plugins/ibuki_hook_bus.dart';
import '../application/plugins/plugin_contributions.dart';
import '../application/plugins/plugin_runtime.dart';
import '../application/providers/repository_providers.dart';
import '../application/projects/txt_novel_providers.dart';
import '../application/projects/novel_prompt_presets.dart';
import '../application/chat/chat_controls_providers.dart';
import '../data/sqlite/sqlite_chat_controls_repository.dart';
import '../data/sqlite/sqlite_novel_prompt_preset_repository.dart';
import '../data/sqlite/sqlite_novel_import_repository.dart';
import '../application/world_roleplay/world_roleplay_providers.dart';
import '../application/tavern/tavern_execution_providers.dart';
import '../data/cache/cached_repositories.dart';
import '../data/cache/cached_outline_repository.dart';
import '../data/cache/cached_long_context_repositories.dart';
import '../data/sqlite/ibuki_database.dart';
import '../data/sqlite/sqlite_backup_snapshot_store.dart';
import '../data/sqlite/sqlite_compatibility_import_repository.dart';
import '../data/sqlite/sqlite_character_repository.dart';
import '../data/sqlite/sqlite_chat_repository.dart';
import '../data/sqlite/sqlite_chat_persona_repository.dart';
import '../data/sqlite/sqlite_project_repository.dart';
import '../data/sqlite/sqlite_plugin_registry.dart';
import '../data/sqlite/sqlite_plugin_storage_repository.dart';
import '../data/sqlite/sqlite_outline_repository.dart';
import '../data/sqlite/sqlite_novel_memory_repository.dart';
import '../data/sqlite/sqlite_reader_repository.dart';
import '../data/sqlite/sqlite_chat_memory_repository.dart';
import '../data/sqlite/sqlite_segment_repository.dart';
import '../data/sqlite/sqlite_world_repository.dart';
import '../data/sqlite/sqlite_world_roleplay_repository.dart';
import '../data/sqlite/sqlite_tavern_repository.dart';
import '../data/secure/flutter_secure_value_store.dart';
import 'app.dart';
import 'performance/app_performance_policy.dart';
import 'startup_error_app.dart';

Future<void> bootstrap({IbukiDatabase? database, Widget? application}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppPerformancePolicy.configureImageCache();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    const forceDatabaseError = bool.fromEnvironment(
      'IBUKI_FORCE_DATABASE_ERROR',
    );
    if (forceDatabaseError) {
      throw const FormatException('Forced database startup failure.');
    }

    final ibukiDatabase = database ?? IbukiDatabase();
    await ibukiDatabase.open();
    final pluginRegistry = SQLitePluginRegistry(ibukiDatabase);
    final pluginStorage = NovelRoutingPluginStorage(
      SQLitePluginStorageRepository(ibukiDatabase),
      SQLiteNovelPluginStateStore(ibukiDatabase),
    );
    final pluginContributions = PluginContributionRegistry();
    final pluginHooks = IbukiHookBus();
    final pluginRuntime = DeclarativePluginRuntime(
      contributions: pluginContributions,
      hooks: pluginHooks,
    );
    final applicationSupportDirectory = await getApplicationSupportDirectory();
    final backupAssets = FileBackupAssetStore(applicationSupportDirectory);
    final backupCodec = BackupArchiveCodec(
      applicationSupportDirectory: applicationSupportDirectory,
    );
    final pluginManager = PluginManager(
      registry: pluginRegistry,
      applicationSupportDirectory: applicationSupportDirectory,
      picker: const SafPluginPackagePicker(),
      runtime: pluginRuntime,
      hookBus: pluginHooks,
      storageRepository: pluginStorage,
    );
    await pluginManager.loadEnabledPlugins();
    const secureStorage = FlutterSecureStorage();
    final projects = CachedProjectRepository(
      SQLiteProjectRepository(ibukiDatabase),
    );
    final segments = CachedSegmentRepository(
      SQLiteSegmentRepository(ibukiDatabase),
    );
    final outlines = CachedOutlineRepository(
      SQLiteOutlineRepository(ibukiDatabase),
    );
    final characters = CachedCharacterRepository(
      SQLiteCharacterRepository(ibukiDatabase),
    );
    final worlds = CachedWorldRepository(SQLiteWorldRepository(ibukiDatabase));
    final worldRoleplay = SQLiteWorldRoleplayRepository(ibukiDatabase);
    final compatibilityImports = SQLiteCompatibilityImportRepository(
      ibukiDatabase,
    );
    final importAssets = FileSillyTavernImportAssetStore(
      applicationSupportDirectory,
    );
    final chats = CachedChatRepository(SQLiteChatRepository(ibukiDatabase));
    final personas = CachedChatPersonaRepository(
      SQLiteChatPersonaRepository(ibukiDatabase),
    );
    final novelMemory = CachedNovelMemoryRepository(
      SQLiteNovelMemoryRepository(ibukiDatabase),
    );
    final reader = CachedReaderRepository(
      SQLiteReaderRepository(ibukiDatabase),
    );
    final chatMemory = CachedChatMemoryRepository(
      SQLiteChatMemoryRepository(ibukiDatabase),
    );
    runApp(
      ProviderScope(
        overrides: [
          aiSecureValueStoreProvider.overrideWithValue(
            const FlutterSecureValueStore(secureStorage),
          ),
          tavernRepositoryProvider.overrideWithValue(
            SQLiteTavernRepository(ibukiDatabase),
          ),
          backupSnapshotStoreProvider.overrideWithValue(
            SQLiteBackupSnapshotStore(ibukiDatabase),
          ),
          backupAssetStoreProvider.overrideWithValue(backupAssets),
          backupArchiveCodecProvider.overrideWithValue(backupCodec),
          backupWorkingDirectoryProvider.overrideWithValue(
            Directory(
              '${applicationSupportDirectory.path}${Platform.pathSeparator}backup${Platform.pathSeparator}exports',
            ),
          ),
          projectRepositoryProvider.overrideWithValue(projects),
          novelPluginRepositoryProvider.overrideWithValue(
            SQLiteNovelPluginRepository(ibukiDatabase),
          ),
          chatControlsRepositoryProvider.overrideWithValue(
            SQLiteChatControlsRepository(ibukiDatabase),
          ),
          novelImportRepositoryProvider.overrideWithValue(
            SQLiteNovelImportRepository(ibukiDatabase),
          ),
          novelOutputLimitsRepositoryProvider.overrideWithValue(
            SQLiteNovelOutputLimitsRepository(ibukiDatabase),
          ),
          novelPromptPresetRepositoryProvider.overrideWithValue(
            SQLiteNovelPromptPresetRepository(ibukiDatabase),
          ),
          segmentRepositoryProvider.overrideWithValue(segments),
          outlineRepositoryProvider.overrideWithValue(outlines),
          characterRepositoryProvider.overrideWithValue(characters),
          worldRepositoryProvider.overrideWithValue(worlds),
          worldRoleplayRepositoryProvider.overrideWithValue(worldRoleplay),
          compatibilityImportRepositoryProvider.overrideWithValue(
            compatibilityImports,
          ),
          sillyTavernImportAssetStoreProvider.overrideWithValue(importAssets),
          chatAvatarStoreProvider.overrideWithValue(
            FileChatAvatarStore(applicationSupportDirectory),
          ),
          chatRepositoryProvider.overrideWithValue(chats),
          chatPersonaRepositoryProvider.overrideWithValue(personas),
          novelMemoryRepositoryProvider.overrideWithValue(novelMemory),
          readerRepositoryProvider.overrideWithValue(reader),
          chatMemoryRepositoryProvider.overrideWithValue(chatMemory),
          pluginRegistryProvider.overrideWithValue(pluginRegistry),
          pluginStorageRepositoryProvider.overrideWithValue(pluginStorage),
          pluginContributionRegistryProvider.overrideWithValue(
            pluginContributions,
          ),
          ibukiHookBusProvider.overrideWithValue(pluginHooks),
          pluginRuntimeProvider.overrideWithValue(pluginRuntime),
          pluginManagerProvider.overrideWithValue(pluginManager),
        ],
        child: application ?? const IbukiHomeApp(),
      ),
    );
    unawaited(
      _preloadLocalSnapshots(
        projects: projects,
        segments: segments,
        outlines: outlines,
        characters: characters,
        worlds: worlds,
        worldRoleplay: worldRoleplay,
        chats: chats,
        personas: personas,
        novelMemory: novelMemory,
        chatMemory: chatMemory,
      ),
    );
  } catch (_) {
    runApp(
      StartupErrorApp(
        onRetry: () => bootstrap(database: database, application: application),
      ),
    );
  }
}

Future<void> _preloadLocalSnapshots({
  required CachedProjectRepository projects,
  required CachedSegmentRepository segments,
  required CachedOutlineRepository outlines,
  required CachedCharacterRepository characters,
  required CachedWorldRepository worlds,
  required SQLiteWorldRoleplayRepository worldRoleplay,
  required CachedChatRepository chats,
  required CachedChatPersonaRepository personas,
  required CachedNovelMemoryRepository novelMemory,
  required CachedChatMemoryRepository chatMemory,
}) async {
  try {
    final projectList = await projects.listProjects();
    final personaList = await personas.listPersonas();
    await Future.wait([
      chats.listSessions(),
      worldRoleplay.listWorlds(),
      if (personaList.isNotEmpty) chatMemory.listEntries(personaList.first.id),
      if (projectList.isNotEmpty) ...[
        segments.listSegments(projectList.first.id),
        outlines.listOutlineNodes(projectList.first.id),
        characters.listCharacters(projectList.first.id),
        worlds.listWorldCards(projectList.first.id),
        novelMemory.listChunks(projectList.first.id),
        novelMemory.getDigest(projectList.first.id),
      ],
    ]);
  } catch (_) {
    // Preloading is opportunistic. Normal repository reads retain error handling.
  }
}
