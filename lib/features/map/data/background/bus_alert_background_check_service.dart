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
  }) : _repository = repository ?? BusAlertRepository(),
       _alertEvaluationService =
           alertEvaluationService ?? AlertEvaluationService();

  final BusAlertRepository _repository;
  final AlertEvaluationService _alertEvaluationService;

  static const _notificationChannelId = 'rtl_stop_alerts';
  static const _notificationChannelName = 'RTL Stop Alerts';
  static const _notificationChannelDescription =
      'Notifications when a selected bus route is near a selected stop';

  Future<BusAlertCheckResult> runOnce({required String source}) async {
    final checkedAt = DateTime.now();
    DebugLog.info('RTLBusAlertService runOnce start source=$source');

    try {
      await _repository.migrateLegacyIfNeeded();
      final alerts = await _repository.getActiveAlerts();
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

      final api = RtlBusApi(DioClient());
      final List<BusLocation> buses = [];
      for (final route in routeParams) {
        DebugLog.info('RTLBusAlertService live bus fetch start route=$route');
        final live = await api.fetchLive(route);
        buses.addAll(live);
        DebugLog.info(
          'RTLBusAlertService live bus fetch end route=$route count=${live.length}',
        );
      }

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

        triggeredCount++;
        final bus = result.nearestBus!;
        try {
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
          DebugLog.info('RTLBusAlertService alert notification error: $e');
        }
      }

      await _repository.saveStatus(
        (await _repository.getStatus()).copyWith(
          method: 'Foreground service',
          lastCheckAt: checkedAt,
          lastResult:
              'Checked ${alerts.length} active alert(s), triggered $triggeredCount',
          clearLastError: true,
          activeAlertsCount: alerts.length,
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
        activeAlertsCount: alerts.length,
        triggeredAlertsCount: triggeredCount,
        routeBusesCount: buses.length,
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
        activeAlertsCount: 0,
        triggeredAlertsCount: 0,
        routeBusesCount: 0,
        error: message,
      );
    }
  }

  Future<void> _ensureNotificationsReady() async {
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
  }
}
