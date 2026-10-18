import 'dart:typed_data';

import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:collection/collection.dart';
import 'package:test/fake.dart';

class FakeMediaFetchService extends Fake implements MediaFetchService {
  Set<AvesEntry> entries = {};

  // URIs of entries for which thumbnails are not available
  Set<String> thumbnailFailures = {};

  @override
  Future<Uint8List?> getEncodedThumbnailBytes(AvesEntry entry, {required int sizePx}) async {
    if (thumbnailFailures.contains(entry.uri)) return null;
    // fake image content, identifying the entry
    return Uint8List.fromList([entry.id % 256]);
  }

  @override
  Future<AvesEntry?> getEntry(String uri, String? mimeType, {bool allowUnsized = false}) async {
    return entries.firstWhereOrNull((v) => v.uri == uri);
  }
}
