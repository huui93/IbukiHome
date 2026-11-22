import '../../domain/reader/reader_preferences.dart';

abstract class ReaderRepository {
  Future<ReaderPreferences> loadPreferences(String projectId);

  Future<void> savePreferences(ReaderPreferences preferences);

  Future<ReaderProgress> loadProgress(String projectId);

  Future<void> saveProgress(ReaderProgress progress);
}
