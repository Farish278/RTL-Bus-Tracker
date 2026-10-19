import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rtl_bus_tracker/features/map/presentation/widgets/basemap_layer.dart';

class TestTiles extends fm.TileProvider {
  TestTiles(this.image);
  final ImageProvider image;
  final urls = <String>[];
  @override
  ImageProvider getImage(fm.TileCoordinates coordinates, fm.TileLayer options) {
    urls.add(getTileUrl(coordinates, options));
    return image;
  }
}

void main() {
  testWidgets(
    'dark map uses cached OSM tiles and keeps overlay colors intact',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 256, 256),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(256, 256);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      final provider = TestTiles(MemoryImage(bytes!));
      final boundaryKey = GlobalKey();
      Widget map(bool dark) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: RepaintBoundary(
              key: boundaryKey,
              child: fm.FlutterMap(
                options: const fm.MapOptions(
                  initialCenter: LatLng(0, 0),
                  initialZoom: 1,
                ),
                children: [
                  BasemapLayer(isDark: dark, tileProvider: provider),
                  const fm.MarkerLayer(
                    markers: [
                      fm.Marker(
                        point: LatLng(0, 0),
                        width: 20,
                        height: 20,
                        child: ColoredBox(
                          key: ValueKey('bus'),
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixel(int x, int y) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List().sublist(
            (y * 200 + x) * 4,
            (y * 200 + x) * 4 + 4,
          );
        }))!;
      }

      await tester.pumpWidget(map(false));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect((await pixel(5, 5)).first, greaterThan(240));
      final lightOverlay = await pixel(100, 100);
      final layer = tester.element(find.byType(fm.TileLayer));
      final requests = provider.urls.length;
      await tester.pumpWidget(map(true));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(fm.TileLayer)), same(layer));
      expect(provider.urls.length, requests);
      expect(
        provider.urls.every(
          (url) => Uri.parse(url).host == 'tile.openstreetmap.org',
        ),
        isTrue,
      );
      expect(find.byType(fm.TileLayer), findsOneWidget);
      expect((await pixel(5, 5)).first, lessThan(45));
      final overlay = await pixel(100, 100);
      expect(overlay, lightOverlay);
      expect(overlay[0], greaterThan(200));
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('bus')),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
