import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtl_bus_tracker/core/network/dio_client.dart';
import 'package:rtl_bus_tracker/core/network/request_scheduler.dart';
import 'package:rtl_bus_tracker/features/map/data/api/rtl_bus_api.dart';
import 'package:rtl_bus_tracker/features/map/data/db/map_tile_cache.dart';
import 'package:rtl_bus_tracker/features/map/data/repositories/map_repository_impl.dart';
import 'package:rtl_bus_tracker/features/map/domain/entities/resource_update.dart';
import 'support/fakes.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.reply);
  final Future<Map<String, dynamic>> Function(RequestOptions) reply;
  final paths = <String>[];
  int active = 0, peak = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    active++;
    if (active > peak) peak = active;
    try {
      return ResponseBody.fromString(
        jsonEncode(await reply(options)),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => RequestScheduler.shared.limit = 4);
  test(
    'coordinates-only monitoring makes one request; complete metadata skips enrichment',
    () async {
      final adapter = Adapter(
        (_) async => {
          'busList': [
            {
              'busCode': 'B1',
              'plateNumber': 'P1',
              'latitude': 4.1,
              'longitude': 73.5,
              'heading': 90,
              'direction': 'inbound',
              'destination': 'Male',
              'nextStop': 'S1',
              'tripDirection': 'inbound',
            },
          ],
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final api = RtlBusApi(DioClient(transport: dio));
      expect(await api.fetchLiveCoordinates('R1'), hasLength(1));
      expect(adapter.paths, hasLength(1));
      await api.fetchLive('R1');
      expect(adapter.paths, hasLength(2));
      expect(adapter.paths.every((p) => p.contains('livecoordinates')), isTrue);
    },
  );
  test('incomplete metadata uses v3 and matches buses by identity', () async {
    final adapter = Adapter(
      (options) async => options.path.contains('livecoordinates')
          ? {
              'busList': [
                {
                  'busCode': 'B1',
                  'plateNumber': 'P1',
                  'latitude': 4.1,
                  'longitude': 73.5,
                },
              ],
            }
          : {
              'busList': [
                {
                  'busCode': 'B1',
                  'nextStopName': 'Next',
                  'destination': 'Male',
                  'bearing': 45,
                },
              ],
            },
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final api = RtlBusApi(DioClient(transport: dio));
    final buses = await api.fetchLive('R1');
    expect(adapter.paths, hasLength(2));
    expect(buses.single.nextStop, 'Next');
    expect(buses.single.point.latitude, 4.1);
  });
  test('RTL request queue limits concurrency to four', () async {
    final gate = Completer<void>();
    final adapter = Adapter((_) async {
      await gate.future;
      return {'busList': []};
    });
    final api = RtlBusApi(
      DioClient(transport: Dio()..httpClientAdapter = adapter),
    );
    final jobs = List.generate(12, (i) => api.fetchLiveCoordinates('R$i'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(adapter.active, 4);
    expect(adapter.peak, 4);
    gate.complete();
    await Future.wait(jobs);
    expect(adapter.paths, hasLength(12));
    expect(adapter.peak, 4);
  });
  test(
    'queued cancellation removes obsolete requests and live work takes priority',
    () async {
      final scheduler = RequestScheduler(limit: 1);
      final gate = Completer<void>();
      final order = <String>[];
      final first = scheduler.run(() => gate.future);
      final obsolete = CancelToken();
      final cancelled = scheduler.run(() async {
        order.add('obsolete');
      }, cancelToken: obsolete);
      final assertion = expectLater(cancelled, throwsA(isA<DioException>()));
      final low = scheduler.run(() async {
        order.add('static');
      }, priority: 2);
      final high = scheduler.run(() async {
        order.add('live');
      }, priority: 0);
      obsolete.cancel();
      gate.complete();
      await Future.wait([first, low, high, assertion]);
      expect(order, ['live', 'static']);
    },
  );
  test(
    'equivalent CARTO subdomains share cache keys without conflating styles',
    () {
      expect(
        MapTileCache.tileKey(
          'https://a.basemaps.cartocdn.com/dark_all/1/2/3.png',
        ),
        MapTileCache.tileKey(
          'https://d.basemaps.cartocdn.com/dark_all/1/2/3.png',
        ),
      );
      expect(
        MapTileCache.tileKey(
          'https://a.basemaps.cartocdn.com/dark_all/1/2/3.png',
        ),
        isNot(
          MapTileCache.tileKey(
            'https://a.basemaps.cartocdn.com/light_all/1/2/3.png',
          ),
        ),
      );
    },
  );
  test(
    '256 Kbps and 800 ms latency publish coordinates before slow details',
    () async {
      final details = Completer<void>();
      final adapter = Adapter((options) async {
        final payload = <String, dynamic>{
          'busList': [
            {
              'busCode': 'B1',
              'plateNumber': 'P1',
              'latitude': 4.1,
              'longitude': 73.5,
            },
          ],
          'padding': List.filled(16000, 'x').join(),
        };
        final transferMs =
            (utf8.encode(jsonEncode(payload)).length / 32000 * 1000).ceil();
        await Future<void>.delayed(Duration(milliseconds: 800 + transferMs));
        if (options.path.contains('livedata')) await details.future;
        return payload;
      });
      final api = RtlBusApi(
        DioClient(transport: Dio()..httpClientAdapter = adapter),
      );
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final first = Completer<LiveSnapshot>();
      final sub = repo.watchLiveSnapshots(['R1']).listen((snapshot) {
        if (!first.isCompleted && !snapshot.historical) {
          first.complete(snapshot);
        }
      });
      final result = await first.future.timeout(const Duration(seconds: 5));
      expect(result.buses, hasLength(1));
      expect(details.isCompleted, isFalse);
      expect(
        adapter.paths.where((p) => p.contains('livecoordinates')),
        hasLength(1),
      );
      details.complete();
      await sub.cancel();
      await repo.dispose();
    },
  );
  test(
    'starting service drains UI requests to its two-slot allocation',
    () async {
      final scheduler = RequestScheduler();
      final gates = List.generate(4, (_) => Completer<void>());
      final jobs = gates
          .map((gate) => scheduler.run(() => gate.future))
          .toList();
      await Future<void>.delayed(Duration.zero);
      var ready = false;
      final reservation = scheduler.reserveForService().then((_) {
        ready = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);
      gates[0].complete();
      gates[1].complete();
      await reservation;
      expect(ready, isTrue);
      expect(scheduler.limit, 2);
      gates[2].complete();
      gates[3].complete();
      await Future.wait(jobs);
    },
  );
}
