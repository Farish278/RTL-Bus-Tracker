import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/debug_log.dart';
import '../../domain/entities/models.dart';
import '../../domain/services/alert_evaluation_service.dart';
import '../api/rtl_bus_api.dart';
import 'bus_alert_repository.dart';

class BusAlertCheckResult {
  const BusAlertCheckResult({
    required this.checkedAt,
    required this.activeAlertsCount,
    required this.triggeredAlertsCount,
    required this.routeBusesCount,
    this.lastNearestBusDistanceMeters,
    this.error,
  });

  final DateTime checkedAt;
  final int activeAlertsCount;
  final int triggeredAlertsCount;
  final int routeBusesCount;
  final double? lastNearestBusDistanceMeters;
  final String? error;
}

class BusAlertBackgroundCheckService {
  BusAlertBackgroundCheckService({
    BusAlertRepository? repository,
    AlertEvaluationService? alertEvaluationService,
    Future<List<BusLocation>> Function(String)? liveFetcher,
    Future<void> Function()? prepareNotifications,
    Future<void> Function(PersistedBusAlert, BusLocation)? notify,
  }) : _prepareNotifications = prepareNotifications,
       _notify = notify,
       _liveFetcher = liveFetcher,
       _repository = repository ?? BusAlertRepository(),
       _alertEvaluationService =
           alertEvaluationService ?? AlertEvaluationService();

  final Future<void> Function()? _prepareNotifications;
  final Future<void> Function(PersistedBusAlert, BusLocation)? _notify;
  bool _notificationsReady = false;
  Future<BusAlertCheckResult>? _inFlight;
  final BusAlertRepository _repository;
  final Future<List<BusLocation>> Function(String)? _liveFetcher;
  final RtlBusApi _api = RtlBusApi(DioClient());
  final AlertEvaluationService _alertEvaluationService;

  static const _notificationChannelId = 'rtl_stop_alerts';
  static const _notificationChannelName = 'RTL Stop Alerts';
  static const _notificationChannelDescription =
      'Notifications when a selected bus route is near a selected stop';

  Future<BusAlertCheckResult> runOnce({
    required String source,
    Set<String>? routeCodes,
  }) async {
    if (_inFlight case final existing?) return existing;
    final future = _runOnce(source: source, routeCodes: routeCodes);
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<BusAlertCheckResult> _runOnce({
    required String source,
    Set<String>? routeCodes,
  }) async {
    final checkedAt = DateTime.now();
    DebugLog.info('RTLBusAlertService runOnce start source=$source');

    var activeCount = 0;
    try {
      await _repository.migrateLegacyIfNeeded();
      final allAlerts = await _repository.getActiveAlerts();
      activeCount = allAlerts.length;
      final alerts = routeCodes == null
          ? allAlerts
          : allAlerts
                .where(
                  (a) => routeCodes.contains(
                    (a.liveApiRouteParam ?? a.routeCode).trim(),
                  ),
                )
                .toList();
      if (alerts.isEmpty && allAlerts.isNotEmpty) {
        return BusAlertCheckResult(
          checkedAt: checkedAt,
          activeAlertsCount: activeCount,
          triggeredAlertsCount: 0,
          routeBusesCount: 0,
        );
      }
      DebugLog.info(
        'RTLBusAlertService active alerts count loaded in service: ${alerts.length}',
      );
      if (alerts.isEmpty) {
        await _repository.saveStatus(
          (await _repository.getStatus()).copyWith(
            method: 'Foreground service',
            lastCheckAt: checkedAt,
            lastResult: 'No active alerts',
            clearLastError: true,
            activeAlertsCount: 0,
            clearLastNearestBusDistanceMeters: true,
            clearLastRouteBusesCount: true,
          ),
        );
        return BusAlertCheckResult(
          checkedAt: checkedAt,
          activeAlertsCount: 0,
          triggeredAlertsCount: 0,
          routeBusesCount: 0,
        );
      }

      await _ensureNotificationsReady();
      final routeParams = alerts
          .map((a) => (a.liveApiRouteParam ?? a.routeCode).trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final buses = <BusLocation>[];
      final failedRoutes = <String>{};
      await Future.wait(
        routeParams.map((route) async {
          try {
            buses.addAll(
              await (_liveFetcher?.call(route) ??
                  _api.fetchLiveCoordinates(route)),
            );
          } catch (error) {
            failedRoutes.add(route);
            DebugLog.info('Alert coordinates failed for $route: $error');
          }
        }),
      );

      final evaluations = _alertEvaluationService.evaluateAlerts(
        activeAlerts: alerts.map((a) => a.toStopAlert()).toList(),
        liveBuses: buses,
      );

      var triggeredCount = 0;
      double? latestNearest;
      int latestRouteBusesCount = 0;
      String? lastTriggeredAlertId;

      for (var i = 0; i < alerts.length; i++) {
        final alert = alerts[i];
        if (failedRoutes.contains(
          (alert.liveApiRouteParam ?? alert.routeCode).trim(),
        )) {
          continue;
        }
        final result = evaluations[i];
        latestNearest = result.nearestBusDistanceMeters ?? latestNearest;
        latestRouteBusesCount = result.matchedRouteBusCount;
        await _repository.markAlertChecked(
          alert.id,
          checkedAt: checkedAt,
          nearestDistanceMeters: result.nearestBusDistanceMeters,
        );
        if (!result.isTriggered || result.nearestBus == null) continue;
        DebugLog.info(
          'RTLBusAlertService alert evaluation result triggered alertId=${alert.id}',
        );

        if (!(await _repository.getActiveAlerts()).any(
          (a) => a.id == alert.id,
        )) {
          continue;
        }
        if (!await _repository.claimNotification(alert.id)) continue;
        final bus = result.nearestBus!;
        try {
          if (_notify != null) {
            await _notify(alert, bus);
          } else {
            final notifications = FlutterLocalNotificationsPlugin();
            await notifications.initialize(
              const InitializationSettings(
                android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              ),
            );
            await notifications.show(
              alert.notificationId,
              'Bus approaching ${alert.stopName}',
              '${alert.routeLabel}: ${bus.busCode.isNotEmpty ? bus.busCode : bus.plateNumber} is within ${alert.distanceThresholdMeters.toInt()}m',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  _notificationChannelId,
                  _notificationChannelName,
                  channelDescription: _notificationChannelDescription,
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
            );
          }
          await _repository.completeNotification(alert.id);
          triggeredCount++;
          DebugLog.info(
            'RTLBusAlertService alert notification shown alertId=${alert.id}',
          );
          await _repository.markAlertTriggered(
            alert.id,
            lastCheckedAt: checkedAt,
            lastNearestBusDistanceMeters: result.nearestBusDistanceMeters,
          );
          DebugLog.info(
            'RTLBusAlertService alert marked triggered alertId=${alert.id}',
          );
          lastTriggeredAlertId = alert.id;
        } catch (e) {
          await _repository.releaseNotification(alert.id);
          DebugLog.info('RTLBusAlertService alert notification error: $e');
        }
      }

      final remainingCount = (await _repository.getActiveAlerts()).length;
      await _repository.saveStatus(
        (await _repository.getStatus()).copyWith(
          method: 'Foreground service',
          lastCheckAt: checkedAt,
          lastResult:
              'Checked ${alerts.length} active alert(s), triggered $triggeredCount',
          lastError: failedRoutes.isEmpty
              ? null
              : 'Some routes could not be refreshed',
          clearLastError: failedRoutes.isEmpty,
          activeAlertsCount: remainingCount,
          lastNearestBusDistanceMeters: latestNearest,
          lastRouteBusesCount: latestRouteBusesCount,
          lastTriggeredAlertId: lastTriggeredAlertId,
          clearLastTriggeredAlertId: triggeredCount == 0,
        ),
      );

      DebugLog.info(
        'RTLBusAlertService runOnce end source=$source checked=${alerts.length} triggered=$triggeredCount',
      );
      return BusAlertCheckResult(
        checkedAt: checkedAt,
        activeAlertsCount: remainingCount,
        triggeredAlertsCount: triggeredCount,
        routeBusesCount: buses.length,
        error: failedRoutes.isEmpty
            ? null
            : 'Some routes could not be refreshed',
        lastNearestBusDistanceMeters: latestNearest,
      );
    } catch (e) {
      final message = 'Background alert check failed: $e';
      DebugLog.info('RTLBusAlertService service errors: $e');
      await _repository.saveStatus(
        (await _repository.getStatus()).copyWith(
          method: 'Foreground service',
          lastCheckAt: checkedAt,
          lastResult: 'Failed',
          lastError: message,
        ),
      );
      return BusAlertCheckResult(
        checkedAt: checkedAt,
        activeAlertsCount: activeCount,
        triggeredAlertsCount: 0,
        routeBusesCount: 0,
        error: message,
      );
    }
  }

  Future<void> _ensureNotificationsReady() async {
    if (_notificationsReady) return;
    if (_prepareNotifications != null) {
      await _prepareNotifications();
      _notificationsReady = true;
      return;
    }
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final androidImpl = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notificationChannelId,
        _notificationChannelName,
        description: _notificationChannelDescription,
        importance: Importance.max,
      ),
    );
    _notificationsReady = true;
  }
}
