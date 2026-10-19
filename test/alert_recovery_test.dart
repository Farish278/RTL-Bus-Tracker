import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rtl_bus_tracker/features/map/data/background/bus_alert_repository.dart';
import 'package:rtl_bus_tracker/features/map/data/background/bus_alert_background_check_service.dart';
import 'support/fakes.dart';

PersistedBusAlert alert(String route) => PersistedBusAlert(
  id: route,
  routeId: route,
  routeCode: route,
  routeLabel: route,
  stopId: 'S1',
  stopCode: 'S1',
  stopName: 'Stop',
  stopPoint: const LatLng(4.1755, 73.5093),
  distanceThresholdMeters: 400,
  enabled: true,
  triggered: false,
  createdAt: DateTime(2026),
  notificationId: route.hashCode,
);

class MemoryAlerts extends BusAlertRepository {
  MemoryAlerts(this.alerts);
  List<PersistedBusAlert> alerts;
  final claims = <String>{};
  BackgroundAlertStatus status = const BackgroundAlertStatus(
    method: 'Foreground service',
    workerRegistered: true,
  );
  @override
  Future<void> migrateLegacyIfNeeded() async {}
  @override
  Future<List<PersistedBusAlert>> getActiveAlerts() async =>
      alerts.where((a) => a.enabled && !a.triggered).toList();
  @override
  Future<BackgroundAlertStatus> getStatus() async => status;
  @override
  Future<void> saveStatus(BackgroundAlertStatus value) async {
    status = value;
  }

  @override
  Future<void> markAlertChecked(
    String id, {
    DateTime? checkedAt,
    double? nearestDistanceMeters,
  }) async {}
  @override
  Future<void> markAlertTriggered(
    String id, {
    DateTime? lastCheckedAt,
    double? lastNearestBusDistanceMeters,
  }) async {
    alerts = alerts
        .map((a) => a.id == id ? a.copyWith(triggered: true) : a)
        .toList();
  }

  @override
  Future<bool> claimNotification(String id) async => claims.add(id);
  @override
  Future<void> completeNotification(String id) async {}
  @override
  Future<void> releaseNotification(String id) async {
    claims.remove(id);
  }
}

void main() {
  test(
    'network errors preserve active alert count and monitoring state',
    () async {
      final repository = MemoryAlerts([alert('R1')]);
      final checker = BusAlertBackgroundCheckService(
        repository: repository,
        prepareNotifications: () async {},
        liveFetcher: (_) async => throw StateError('timeout'),
      );
      final result = await checker.runOnce(source: 'test');
      expect(result.activeAlertsCount, 1);
      expect(result.error, isNotNull);
      expect(await repository.getActiveAlerts(), hasLength(1));
      expect(repository.status.lastError, isNotNull);
    },
  );
  test(
    'one failed route does not suppress alerts for successful routes',
    () async {
      final repository = MemoryAlerts([alert('bad'), alert('good')]);
      final sent = <String>[];
      final checker = BusAlertBackgroundCheckService(
        repository: repository,
        prepareNotifications: () async {},
        liveFetcher: (code) async {
          if (code == 'bad') throw StateError('offline');
          return [bus(code)];
        },
        notify: (alert, bus) async {
          sent.add(alert.id);
        },
      );
      final result = await checker.runOnce(source: 'test');
      expect(result.triggeredAlertsCount, 1);
      expect(sent, ['good']);
      expect((await repository.getActiveAlerts()).single.id, 'bad');
    },
  );
  test('concurrent checks share work and notify once', () async {
    final repository = MemoryAlerts([alert('R1')]);
    final gate = Completer<void>();
    var fetches = 0, sent = 0;
    final checker = BusAlertBackgroundCheckService(
      repository: repository,
      prepareNotifications: () async {},
      liveFetcher: (code) async {
        fetches++;
        await gate.future;
        return [bus(code)];
      },
      notify: (alert, bus) async {
        sent++;
      },
    );
    final first = checker.runOnce(source: 'first');
    final second = checker.runOnce(source: 'second');
    await flush();
    expect(fetches, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(sent, 1);
  });
  test(
    'notification failure releases the claim and next check can recover',
    () async {
      final repository = MemoryAlerts([alert('R1')]);
      var attempts = 0;
      final checker = BusAlertBackgroundCheckService(
        repository: repository,
        prepareNotifications: () async {},
        liveFetcher: (code) async => [bus(code)],
        notify: (alert, bus) async {
          attempts++;
          if (attempts == 1) throw StateError('notification unavailable');
        },
      );
      final first = await checker.runOnce(source: 'first');
      expect(first.triggeredAlertsCount, 0);
      final second = await checker.runOnce(source: 'second');
      expect(second.triggeredAlertsCount, 1);
      expect(attempts, 2);
    },
  );
  test('map snapshots do not poll alert-only routes', () async {
    final repository = MemoryAlerts([alert('map'), alert('background')]);
    final fetched = <String>[];
    final checker = BusAlertBackgroundCheckService(
      repository: repository,
      prepareNotifications: () async {},
      liveFetcher: (code) async {
        fetched.add(code);
        return [bus(code)];
      },
      notify: (alert, bus) async {},
    );
    await checker.runOnce(source: 'map', routeCodes: {'map'});
    expect(fetched, ['map']);
    expect((await repository.getActiveAlerts()).single.id, 'background');
  });
}
