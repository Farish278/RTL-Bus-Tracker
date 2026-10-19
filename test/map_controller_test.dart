import 'dart:async';
import 'package:rtl_bus_tracker/features/map/domain/entities/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtl_bus_tracker/features/map/data/repositories/map_repository_impl.dart';
import 'package:rtl_bus_tracker/features/map/presentation/controllers/map_controller.dart';
import 'support/fakes.dart';

class DelayedScheduleRepository extends MapRepositoryImpl {
  DelayedScheduleRepository(super.api, {required super.cache});
  final gate = Completer<void>();
  int scheduleCalls = 0;

  @override
  Future<RouteSchedule?> getRouteSchedule(
    String code, {
    bool forceRefresh = false,
  }) async {
    scheduleCalls++;
    await gate.future;
    return super.getRouteSchedule(code, forceRefresh: forceRefresh);
  }
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'slow geometry does not block live tracking or duplicate its first request',
    () async {
      final api = FakeApi();
      final gate = Completer<void>();
      api.geometryWait = (_) => gate.future;
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final controller = MapController(repo);
      await controller.selectArea('101');
      await controller.toggleRoute('R1');
      await flush();
      expect(api.coordinateCalls, 1);
      expect(controller.state.liveBuses, hasLength(1));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.loadingResources, contains('geometry:R1'));
      gate.complete();
      await flush();
      expect(controller.state.geometries, hasLength(1));
      controller.dispose();
      await repo.dispose();
    },
  );
  test(
    'force schedule refresh updates existing schedules immediately on completion',
    () async {
      final api = FakeApi();
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final controller = MapController(repo);
      await controller.selectArea('101');
      await controller.loadScheduleForRoute(sampleRoute);
      final before = api.routeCalls;
      await controller.loadSchedulesForStop(sampleRoute.stops.first, [
        sampleRoute,
        sampleRoute,
      ], forceRefresh: true);
      await flush();
      expect(api.routeCalls, before + 1);
      expect(controller.state.routeSchedules['R1'], isNotNull);
      controller.dispose();
      await repo.dispose();
    },
  );
  test(
    'opening and switching route schedules reuse the catalogue without API calls',
    () async {
      final otherRoute = BusRoute(
        id: '2',
        routeCode: 'R2',
        routeNumber: '2',
        name: 'Other route',
        areaCode: sampleRoute.areaCode,
        areaName: sampleRoute.areaName,
        areaType: sampleRoute.areaType,
        colorHex: '#0000ff',
        stops: sampleRoute.stops,
      );
      final api = FakeApi()..routes = [sampleRoute, otherRoute];
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final controller = MapController(repo);
      await controller.selectArea('101');
      await flush();
      final routeCalls = api.routeCalls;
      final etaCalls = api.etaCalls;
      final coordinateCalls = api.coordinateCalls;
      final geometryCalls = api.geometryCalls;
      for (final route in [sampleRoute, otherRoute, sampleRoute, otherRoute]) {
        await controller.loadScheduleForRoute(route);
        expect(
          controller
              .state
              .routeSchedules[route.routeCode]!
              .stops
              .first
              .entries
              .first
              .timeLabel,
          '08:00',
        );
      }
      expect(controller.state.routeSchedules.keys, containsAll(['R1', 'R2']));
      expect(api.routeCalls, routeCalls);
      expect(api.etaCalls, etaCalls);
      expect(api.coordinateCalls, coordinateCalls);
      expect(api.geometryCalls, geometryCalls);
      controller.dispose();
      await repo.dispose();
    },
  );

  test('reopening while a schedule is loading shares the same load', () async {
    final api = FakeApi();
    final repo = DelayedScheduleRepository(api, cache: MemoryCache());
    final controller = MapController(repo);
    await controller.selectArea('101');
    final first = controller.loadScheduleForRoute(sampleRoute);
    await controller.loadScheduleForRoute(sampleRoute);
    await controller.loadScheduleForRoute(sampleRoute);
    expect(repo.scheduleCalls, 1);
    expect(controller.state.loadingScheduleRouteCodes, contains('R1'));
    repo.gate.complete();
    await first;
    expect(api.routeCalls, 1);
    expect(controller.state.loadingScheduleRouteCodes, isEmpty);
    expect(controller.state.routeSchedules['R1'], isNotNull);
    controller.dispose();
    await repo.dispose();
  });

  test(
    'a details load can complete safely after controller disposal',
    () async {
      final repo = DelayedScheduleRepository(FakeApi(), cache: MemoryCache());
      final controller = MapController(repo);
      await controller.selectArea('101');
      final load = controller.loadScheduleForRoute(sampleRoute);
      controller.dispose();
      repo.gate.complete();
      await expectLater(load, completes);
      await repo.dispose();
    },
  );
  test('a details load can fail safely after controller disposal', () async {
    final repo = DelayedScheduleRepository(FakeApi(), cache: MemoryCache());
    final controller = MapController(repo);
    await controller.selectArea('101');
    final load = controller.loadScheduleForRoute(sampleRoute);
    controller.dispose();
    repo.gate.completeError(StateError('offline'));
    await expectLater(load, completes);
    await repo.dispose();
  });
}
