import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<File> _file(String readingId) async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/palms');
  await dir.create(recursive: true);
  return File('${dir.path}/$readingId.jpg');
}

Future<void> save(String readingId, Uint8List bytes) async => (await _file(readingId)).writeAsBytes(bytes, flush: true);

Future<Uint8List?> load(String readingId) async {
  final f = await _file(readingId);
  return await f.exists() ? f.readAsBytes() : null;
}

Future<void> delete(String readingId) async {
  final f = await _file(readingId);
  if (await f.exists()) await f.delete();
}
