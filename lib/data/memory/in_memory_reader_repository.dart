import '../../domain/reader/reader_preferences.dart';
import '../repositories/reader_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryReaderRepository implements ReaderRepository {
  InMemoryReaderRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<ReaderPreferences> loadPreferences(String projectId) async =>
      store.readerPreferences(projectId) ??
      ReaderPreferences.defaults(projectId);

  @override
  Future<void> savePreferences(ReaderPreferences preferences) async {
    store.putReaderPreferences(preferences);
  }

  @override
  Future<ReaderProgress> loadProgress(String projectId) async =>
      store.readerProgress(projectId) ?? ReaderProgress.empty(projectId);

  @override
  Future<void> saveProgress(ReaderProgress progress) async {
    store.putReaderProgress(progress);
  }
}
