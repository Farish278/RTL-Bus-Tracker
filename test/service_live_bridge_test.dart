import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:rtl_bus_tracker/core/network/request_scheduler.dart';
import 'package:rtl_bus_tracker/features/map/data/background/service_live_bridge.dart';
import 'package:rtl_bus_tracker/features/map/data/repositories/map_repository_impl.dart';
import 'package:rtl_bus_tracker/features/map/domain/entities/resource_update.dart';
import 'support/fakes.dart';

class FakeService implements FlutterBackgroundService {
  bool running = false;
  final messages = <({String method, Map<String, dynamic>? args})>[];
  final events = StreamController<Map<String, dynamic>?>.broadcast();
  @override
  Future<bool> isRunning() async => running;
  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    messages.add((method: method, args: args));
  }

  @override
  Stream<Map<String, dynamic>?> on(String method) => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    RequestScheduler.shared.limit = 4;
  });
  test(
    'UI yields polling to service, receives snapshots, and takes over after stop',
    () async {
      final api = FakeApi();
      final repo = MapRepositoryImpl(api, cache: MemoryCache());
      final service = FakeService();
      final snapshots = <LiveSnapshot>[];
      final sub = ServiceLiveBridge(
        repo,
        service: service,
        heartbeatInterval: const Duration(milliseconds: 20),
      ).watch(['R1']).listen(snapshots.add);
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(ready(), isTrue);
      }

      await until(() => api.coordinateCalls == 1);
      service.running = true;
      await until(() => service.messages.any((m) => m.method == 'live_watch'));
      expect(RequestScheduler.shared.limit, 2);
      final watch = service.messages.lastWhere((m) => m.method == 'live_watch');
      service.events.add({
        'id': watch.args!['id'],
        'snapshot': LiveSnapshot(
          routeCode: 'R1',
          buses: [bus('R1')],
          fetchedAt: DateTime.now(),
        ).toJson(),
      });
      await flush();
      expect(snapshots.last.buses, hasLength(1));
      expect(api.coordinateCalls, 1);
      service.running = false;
      await until(() => api.coordinateCalls == 2);
      expect(RequestScheduler.shared.limit, 4);
      await sub.cancel();
      expect(service.messages.last.method, 'live_unwatch');
      await repo.dispose();
      await service.events.close();
    },
  );
}
