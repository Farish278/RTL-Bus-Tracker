import 'package:fake_async/fake_async.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtl_bus_tracker/features/map/data/repositories/map_repository_impl.dart';
import 'package:rtl_bus_tracker/features/map/domain/entities/models.dart';
import 'package:rtl_bus_tracker/features/map/domain/entities/resource_update.dart';
import 'support/fakes.dart';

void main() {
  test(
    'concurrent catalogue and schedule refreshes share one download',
    () async {
      final api = FakeApi();
      final gate = Completer<void>();
      api.routeWait = () => gate.future;
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final jobs = <Future<Object?>>[
        repo.getAreas(forceRefresh: true),
        repo.getRoutes('101', forceRefresh: true),
        repo.getRouteSchedule('R1', forceRefresh: true),
        repo.getRouteSchedule('R2', forceRefresh: true),
      ];
      await flush();
      expect(api.routeCalls, 1);
      gate.complete();
      await Future.wait(jobs);
      expect(
        (await repo.getRouteSchedule(
          'R1',
        ))!.stops.first.entries.first.timeLabel,
        '08:00',
      );
      await repo.dispose();
    },
  );
  test(
    'cache writes failing do not discard network results; memory avoids repeated decoding',
    () async {
      final api = FakeApi();
      final cache = MemoryCache()..failWrites = true;
      final repo = MapRepositoryImpl(api, cache: cache);
      expect(await repo.getRoutes('101'), hasLength(1));
      final reads = cache.reads;
      expect(await repo.getAreas(), hasLength(1));
      expect(cache.reads, reads);
      expect(repo.resourceStatuses['routes']!.fetchedAt, isNotNull);
      await repo.clearCache();
      api.routes = [];
      expect(await repo.getRoutes('101'), isEmpty);
      expect(api.routeCalls, 2);
      await repo.dispose();
    },
  );
  test(
    'stale catalogue is immediate and refresh is deduplicated and observable',
    () async {
      final cache = MemoryCache();
      final api = FakeApi();
      var repo = MapRepositoryImpl(api, cache: cache);
      await repo.getRoutes('101');
      await repo.dispose();
      cache.values['routes']!['updatedAt'] = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      final gate = Completer<void>();
      api.routeWait = () => gate.future;
      repo = MapRepositoryImpl(api, cache: cache);
      final events = <ResourceUpdate>[];
      final sub = repo.updates.listen(events.add);
      expect(await repo.getRoutes('101'), hasLength(1));
      expect(await repo.getAreas(), hasLength(1));
      expect(api.routeCalls, 2);
      expect(repo.resourceStatuses['routes']!.historical, isTrue);
      gate.complete();
      await flush();
      expect(events.where((e) => e.key == 'routes'), hasLength(1));
      expect(repo.resourceStatuses['routes']!.historical, isFalse);
      await sub.cancel();
      await repo.dispose();
    },
  );
  test('one slow geometry does not prevent other route publication', () async {
    final api = FakeApi();
    final gate = Completer<void>();
    api.geometryWait = (code) => code == 'slow' ? gate.future : Future.value();
    final repo = MapRepositoryImpl(api, cache: MemoryCache());
    final events = <ResourceUpdate>[];
    final sub = repo.updates.listen(events.add);
    final request = repo.getRouteGeometry(['slow', 'fast', 'fast']);
    await flush();
    expect(events.where((e) => e.key == 'geometry:fast'), hasLength(1));
    expect(api.geometryCalls, 2);
    gate.complete();
    expect(await request, hasLength(2));
    await sub.cancel();
    await repo.dispose();
  });
  test(
    'coordinates publish before delayed enrichment; cancellation reaches transport',
    () async {
      final api = FakeApi()..enrich = true;
      final gate = Completer<List<BusLocation>>();
      CancelToken? enrichmentToken;
      api.enrichment = (code, buses, token) {
        enrichmentToken = token;
        return gate.future;
      };
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final snapshots = <LiveSnapshot>[];
      final sub = repo.watchLiveSnapshots(['R1']).listen(snapshots.add);
      await flush();
      expect(api.coordinateCalls, 1);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.buses, hasLength(1));
      await sub.cancel();
      expect(enrichmentToken!.isCancelled, isTrue);
      gate.complete([bus('R1')]);
      await flush();
      expect(snapshots, hasLength(1));
      await repo.dispose();
    },
  );
  test(
    'successful polling waits eight seconds, failures retain buses, successful empty clears',
    () {
      fakeAsync((clock) {
        final api = FakeApi();
        var attempt = 0;
        api.coordinates = (code, token) async {
          attempt++;
          if (attempt == 2) throw StateError('offline');
          return attempt == 3 ? [] : [bus(code)];
        };
        final repo = MapRepositoryImpl(
          api,
          cache: MemoryCache(),
          jitter: false,
          now: clock.getClock(DateTime(2026)).now,
        );
        final snapshots = <LiveSnapshot>[];
        final sub = repo.watchLiveSnapshots(['R1']).listen(snapshots.add);
        clock.flushMicrotasks();
        expect(api.coordinateCalls, 1);
        clock.elapse(const Duration(seconds: 7));
        expect(api.coordinateCalls, 1);
        clock.elapse(const Duration(seconds: 1));
        expect(api.coordinateCalls, 2);
        expect(snapshots.last.buses, hasLength(1));
        expect(snapshots.last.historical, isTrue);
        expect(snapshots.last.error, isNotNull);
        clock.elapse(const Duration(seconds: 15));
        expect(api.coordinateCalls, 2);
        clock.elapse(const Duration(seconds: 1));
        expect(api.coordinateCalls, 3);
        expect(snapshots.last.buses, isEmpty);
        expect(snapshots.last.error, isNull);
        unawaited(sub.cancel());
        clock.flushMicrotasks();
        unawaited(repo.dispose());
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'restored positions are historical and never reused for alert evaluation',
    () async {
      final cache = MemoryCache();
      final at = DateTime.now();
      await cache.put(
        'live:R1',
        LiveSnapshot(
          routeCode: 'R1',
          buses: [bus('R1')],
          fetchedAt: at,
        ).toJson(),
      );
      final api = FakeApi();
      final gate = Completer<List<BusLocation>>();
      api.coordinates = (code, token) => gate.future;
      final repo = MapRepositoryImpl(api, cache: cache);
      final snapshots = <LiveSnapshot>[];
      final sub = repo.watchLiveSnapshots(['R1']).listen(snapshots.add);
      await flush();
      expect(snapshots.single.historical, isTrue);
      final alert = repo.getCoordinatesForAlert('R1');
      expect(api.coordinateCalls, 1);
      gate.complete([]);
      expect(await alert, isEmpty);
      await flush();
      expect(snapshots.last.historical, isFalse);
      expect(snapshots.last.buses, isEmpty);
      await sub.cancel();
      await repo.dispose();
    },
  );
  test('backoff honors Retry-After and HTTP dates', () async {
    final at = DateTime.utc(2026, 10, 19, 12);
    final repo = MapRepositoryImpl(
      FakeApi(),
      cache: MemoryCache(),
      now: () => at,
      jitter: false,
    );
    expect(repo.retryDelay(1, null), const Duration(seconds: 16));
    expect(repo.retryDelay(2, null), const Duration(seconds: 32));
    expect(repo.retryDelay(3, null), const Duration(seconds: 60));
    final options = RequestOptions(path: '/test');
    final error = DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: 429,
        headers: Headers.fromMap({
          'retry-after': ['120'],
        }),
      ),
    );
    expect(repo.retryDelay(1, error), const Duration(seconds: 120));
    error.response!.headers.set('retry-after', 'Mon, 19 Oct 2026 12:03:00 GMT');
    expect(repo.retryDelay(1, error), const Duration(minutes: 3));
    await repo.dispose();
  });
  test(
    'cancelling map does not cancel coordinates still needed by an alert',
    () async {
      final api = FakeApi();
      final gate = Completer<List<BusLocation>>();
      api.coordinates = (code, token) => gate.future;
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final sub = repo.watchLiveSnapshots(['R1']).listen((_) {});
      await flush();
      final alert = repo.getCoordinatesForAlert('R1');
      await flush();
      expect(api.coordinateCalls, 1);
      await sub.cancel();
      await flush();
      expect(api.tokens.single.isCancelled, isFalse);
      gate.complete([bus('R1')]);
      expect(await alert, hasLength(1));
      await repo.dispose();
    },
  );
}
