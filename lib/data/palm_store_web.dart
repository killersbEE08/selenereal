import 'dart:typed_data';

// Browsers have no app documents folder; keep photos for this tab's session only. After a reload
// the reading still works, it just shows the illustrated palm instead of the user's photo.
final _mem = <String, Uint8List>{};

Future<void> save(String readingId, Uint8List bytes) async => _mem[readingId] = bytes;
Future<Uint8List?> load(String readingId) async => _mem[readingId];
Future<void> delete(String readingId) async => _mem.remove(readingId);
