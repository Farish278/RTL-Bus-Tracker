import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

class MapTileCache implements MapCachingProvider {
  MapTileCache._();
  static final instance = MapTileCache._();
  static const maxBytes = 1000000000;
  int hits = 0, misses = 0, writes = 0;
  String? lastError;
  Future<void>? _clearing;
  final Set<Future<void>> _pending = {};
  BuiltInMapCachingProvider get _delegate =>
      BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: maxBytes,
        tileKeyGenerator: tileKey,
      );
  static String canonicalUrl(String url) {
    final uri = Uri.parse(url);
    if (const [
      'a.basemaps.cartocdn.com',
      'b.basemaps.cartocdn.com',
      'c.basemaps.cartocdn.com',
      'd.basemaps.cartocdn.com',
    ].contains(uri.host)) {
      return uri.replace(host: 'basemaps.cartocdn.com').toString();
    }
    return url;
  }

  static String tileKey(String url) =>
      BuiltInMapCachingProvider.uuidTileKeyGenerator(canonicalUrl(url));
  @override
  bool get isSupported => !kIsWeb && _delegate.isSupported;
  Future<T> _track<T>(Future<T> Function() action) async {
    await _clearing;
    final future = action();
    final done = future.then<void>(
      (_) {},
      onError: (Object error) {
        lastError = '$error';
      },
    );
    _pending.add(done);
    try {
      return await future;
    } finally {
      _pending.remove(done);
    }
  }

  @override
  Future<CachedMapTile?> getTile(String url) => _track(() async {
    final tile = await _delegate.getTile(url);
    if (tile == null || tile.metadata.isStale) {
      misses++;
    } else {
      hits++;
    }
    return tile;
  });
  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) => _track(() async {
    await _delegate.putTile(url: url, metadata: metadata, bytes: bytes);
    writes++;
  });
  Future<void> clear() {
    return _clearing ??= () async {
      try {
        await Future.wait(_pending.toList());
        await _delegate.destroy(deleteCache: true);
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        hits = 0;
        misses = 0;
        writes = 0;
        lastError = null;
      } finally {
        _clearing = null;
      }
    }();
  }

  Future<Map<String, Object?>> diagnostics() async {
    var bytes = 0, files = 0;
    if (!kIsWeb) {
      final directory = Directory(
        '${(await getApplicationCacheDirectory()).path}/fm_cache',
      );
      if (await directory.exists()) {
        await for (final file in directory.list()) {
          if (file is File) {
            bytes += await file.length();
            files++;
          }
        }
      }
    }
    return {
      'bytes': bytes,
      'files': files,
      'hits': hits,
      'misses': misses,
      'writes': writes,
      'lastError': lastError,
    };
  }
}
