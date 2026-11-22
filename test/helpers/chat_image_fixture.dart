import 'package:ibukihome/domain/chat/chat_image.dart';

const imageFixtureBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAE0lEQVR4nGPUSLnDAANMcBZeDgBGoAFwFFW4VwAAAABJRU5ErkJggg==';
ChatImage imageFixture({String text = '', String? description}) => ChatImage(
  base64Data: imageFixtureBase64,
  mimeType: 'image/png',
  userText: text,
  description: description,
);
