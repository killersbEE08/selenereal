import 'dart:typed_data';

import 'palm_store_io.dart' if (dart.library.js_interop) 'palm_store_web.dart' as impl;

/// Local copy of a compressed palm photo, used for the line overlay (the server copy is deleted
/// by default). Mobile keeps it on disk; web keeps it in memory for the browser session.
class PalmStore {
  static Future<void> save(String readingId, Uint8List bytes) => impl.save(readingId, bytes);
  static Future<Uint8List?> load(String readingId) => impl.load(readingId);
  static Future<void> delete(String readingId) => impl.delete(readingId);
}
