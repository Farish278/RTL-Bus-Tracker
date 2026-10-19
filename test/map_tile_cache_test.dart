import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtl_bus_tracker/features/map/data/db/map_tile_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disk tiles survive provider restart and equivalent subdomains reuse bytes',
    () async {
      final workspace = Directory.current.absolute.path;
      final directory = Directory(
        '$workspace/.cache/tile-cache-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      await directory.create(recursive: true);
      BuiltInMapCachingProvider create() =>
          BuiltInMapCachingProvider.getOrCreateInstance(
            cacheDirectory: directory.path,
            tileKeyGenerator: MapTileCache.tileKey,
            maxCacheSize: MapTileCache.maxBytes,
          );
      var provider = create();
      try {
        const first = 'https://a.basemaps.cartocdn.com/dark_all/1/2/3.png';
        const equivalent = 'https://d.basemaps.cartocdn.com/dark_all/1/2/3.png';
        await provider.getTile(first);
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        await provider.putTile(
          url: first,
          metadata: CachedMapTileMetadata(
            staleAt: DateTime.now().add(const Duration(days: 1)),
            lastModified: null,
            etag: 'test',
          ),
          bytes: bytes,
        );
        CachedMapTile? cached;
        for (var i = 0; i < 100 && cached == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          cached = await provider.getTile(equivalent);
        }
        expect(cached, isNotNull);
        expect(cached!.bytes, bytes);
        await provider.destroy();
        provider = create();
        final restored = await MapTileCache.instance.getTile(equivalent);
        expect(restored, isNotNull);
        expect(restored!.bytes, bytes);
        expect(restored.metadata.isStale, isFalse);
        await provider.putTile(
          url: first,
          metadata: CachedMapTileMetadata(
            staleAt: DateTime.now().add(const Duration(days: 1)),
            lastModified: null,
            etag: 'updated',
          ),
          bytes: bytes,
        );
        for (var i = 0; i < 100; i++) {
          if ((await provider.getTile(first))?.metadata.etag == 'updated') {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect((await provider.getTile(first))?.metadata.etag, 'updated');
        await MapTileCache.instance.clear();
        expect(await Directory('${directory.path}/fm_cache').exists(), isFalse);
      } finally {
        await provider.destroy();
        // Only remove the test-owned directory under this workspace.
        final resolved = await directory.resolveSymbolicLinks();
        final cacheRoot = await Directory(
          '$workspace/.cache',
        ).resolveSymbolicLinks();
        expect(path.isWithin(cacheRoot, resolved), isTrue);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}
