import 'package:sqflite/sqflite.dart';

Future<void> createChatImagesV20Schema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(chat_messages)');
  if (!columns.any((row) => row['name'] == 'image_json')) {
    await db.execute(
      'ALTER TABLE chat_messages ADD COLUMN image_json TEXT NULL',
    );
  }
}
