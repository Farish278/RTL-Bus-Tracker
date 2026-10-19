import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/utils/debug_log.dart';
import 'bus_alert_background_check_service.dart';
import 'bus_alert_repository.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/request_scheduler.dart';
import '../api/rtl_bus_api.dart';
import '../repositories/map_repository_impl.dart';
import '../../domain/entities/resource_update.dart';

class ForegroundAlertService {
  static const int serviceNotificationId = 445001;
  static const String serviceChannelId = 'rtl_bus_alert_monitor';
  static const String serviceChannelName = 'RTL Bus Alert Monitor';
  static const String serviceTitle = 'RTL Bus Tracker';
  static const String serviceBody = 'Watching for bus alerts';
  static const Duration pollInterval = Duration(seconds: 45);

  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static final BusAlertRepository _repository = BusAlertRepository();
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _configured = false;

  static Future<void> initialize() async {
    DebugLog.info('RTLBusAlertService configure called');
    if (_configured) return;
    await _repository.initialize();
    await _repository.migrateLegacyIfNeeded();
    await _ensureServiceNotificationChannel();
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: foregroundServiceEntryPoint,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: serviceChannelId,
        initialNotificationTitle: serviceTitle,
        initialNotificationContent: serviceBody,
        foregroundServiceNotificationId: serviceNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: foregroundServiceEntryPoint,
      ),
    );
    _configured = true;
    DebugLog.info('RTLBusAlertService configure success');
  }

  static Future<void> _ensureServiceNotificationChannel() async {
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        serviceChannelId,
        'Bus alert monitoring',
        description: 'Persistent notification while monitoring bus alerts',
        importance: Importance.low,
      ),
    );
  }

  static Future<bool> isRunning() async {
    try {
      if (!_configured) return false;
      return await _service.isRunning();
    } catch (e) {
      DebugLog.info('Foreground alert service isRunning failed: $e');
      return false;
    }
  }

  static Future<bool> ensureRunning() async {
    try {
      DebugLog.info('RTLBusAlertService service start requested');
      await RequestScheduler.shared.reserveForService();
      await initialize();
      if (await _service.isRunning()) {
        DebugLog.info('RTLBusAlertService service already running');
        await _saveServiceStatus(
          running: true,
          result: 'Service already running',
        );
        return true;
      }
      final started = await _service.startService();
      if (!started) RequestScheduler.shared.limit = 4;
      DebugLog.info(
        'RTLBusAlertService service start ${started ? 'success' : 'failure'}',
      );
      await _saveServiceStatus(
        running: started,
        result: started
            ? 'Foreground service started'
            : 'Failed to start foreground service',
      );
      return started;
    } catch (e) {
      DebugLog.info('RTLBusAlertService service start failed: $e');
      await _saveServiceStatus(
        running: false,
        result: 'Failed',
        error: 'Foreground service start failed: $e',
      );
      return false;
    }
  }

  static Future<void> stopIfRunning() async {
    try {
      DebugLog.info('RTLBusAlertService stop requested');
      await initialize();
      final running = await _service.isRunning();
      if (running) {
        _service.invoke('stop_service');
      }
      await _saveServiceStatus(
        running: false,
        result: running
            ? 'Foreground service stopped'
            : 'Foreground service already stopped',
      );
    } catch (e) {
      DebugLog.info('RTLBusAlertService stop failed: $e');
      await _saveServiceStatus(
        running: false,
        result: 'Failed',
        error: 'Foreground service stop failed: $e',
      );
    }
  }

  static Future<void> reconcileWithStoredAlerts() async {
    await initialize();
    final active = await _repository.getActiveAlerts();
    if (active.isEmpty) {
      await stopIfRunning();
      return;
    }
    await ensureRunning();
  }

  static Future<void> _saveServiceStatus({
    required bool running,
    required String result,
    String? error,
  }) async {
    final status = await _repository.getStatus();
    await _repository.saveStatus(
      status.copyWith(
        method: 'Foreground service',
        workerRegistered: running,
        lastResult: result,
        lastError: error,
        clearLastError: error == null,
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> foregroundServiceEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  DebugLog.info('RTLBusAlertService service onStart entered');

  final repository = BusAlertRepository();
  RequestScheduler.shared.limit = 2;
  final liveRepository = MapRepositoryImpl(RtlBusApi(DioClient()));
  final checker = BusAlertBackgroundCheckService(
    repository: repository,
    liveFetcher: liveRepository.getCoordinatesForAlert,
  );
  final views = <String, ({List<String> routes, DateTime seen})>{};
  final polls = <String, StreamSubscription<LiveSnapshot>>{};
  final latest = <String, LiveSnapshot>{};
  var stopped = false;
  Timer? timer;
  Timer? leaseTimer;
  final eventSubscriptions = <StreamSubscription<dynamic>>[];
  var isChecking = false;
  late Future<void> Function() stop;

  Future<void> runCheck(String source, {Set<String>? routeCodes}) async {
    if (isChecking) return;
    isChecking = true;
    DebugLog.info('RTLBusAlertService service tick start source=$source');
    try {
      final result = await checker.runOnce(
        source: source,
        routeCodes: routeCodes,
      );
      DebugLog.info(
        'RTLBusAlertService service tick end source=$source active=${result.activeAlertsCount} triggered=${result.triggeredAlertsCount} error=${result.error ?? 'none'}',
      );
      if ((await repository.getActiveAlerts()).isEmpty) {
        DebugLog.info(
          'RTLBusAlertService service stopped due to no active alerts',
        );
        final status = await repository.getStatus();
        await repository.saveStatus(
          status.copyWith(
            method: 'Foreground service',
            workerRegistered: false,
            lastResult: 'No active alerts. Service stopping.',
            clearLastError: true,
          ),
        );
        await stop();
      }
    } catch (e) {
      DebugLog.info('RTLBusAlertService service error: $e');
      final status = await repository.getStatus();
      await repository.saveStatus(
        status.copyWith(
          method: 'Foreground service',
          workerRegistered: true,
          lastResult: 'Failed',
          lastError: 'Foreground service check failed: $e',
        ),
      );
    } finally {
      isChecking = false;
    }
  }

  Future<void> reconcileViews() async {
    if (stopped) return;
    final now = DateTime.now();
    views.removeWhere(
      (_, view) => now.difference(view.seen) > const Duration(seconds: 15),
    );
    final routes = views.values.expand((view) => view.routes).toSet();
    for (final code in polls.keys.toList()) {
      if (!routes.contains(code)) {
        final subscription = polls.remove(code);
        await subscription?.cancel();
      }
    }
    for (final code in routes) {
      polls.putIfAbsent(
        code,
        () => liveRepository.watchLiveSnapshots([code]).listen((snapshot) {
          latest[code] = snapshot;
          for (final entry in views.entries) {
            if (entry.value.routes.contains(code)) {
              service.invoke('live_snapshot', {
                'id': entry.key,
                'snapshot': snapshot.toJson(),
              });
            }
          }
          if (!snapshot.historical &&
              snapshot.error == null &&
              !snapshot.metadataOnly) {
            unawaited(
              runCheck(
                'fresh_map_coordinates',
                routeCodes: {snapshot.routeCode},
              ),
            );
          }
        }),
      );
    }
  }

  stop = () async {
    if (stopped) return;
    stopped = true;
    timer?.cancel();
    leaseTimer?.cancel();
    for (final subscription in polls.values) {
      await subscription.cancel();
    }
    for (final subscription in eventSubscriptions) {
      unawaited(subscription.cancel());
    }
    await liveRepository.dispose();
    await service.stopSelf();
  };
  eventSubscriptions.add(
    service.on('live_watch').listen((message) {
      if (message == null || stopped) return;
      final id = message['id'] as String;
      final routes = List<String>.from(message['routes'] as List);
      final isNew = !views.containsKey(id);
      views[id] = (routes: routes, seen: DateTime.now());
      if (isNew) {
        for (final code in routes) {
          final snapshot = latest[code];
          if (snapshot != null) {
            // Replayed snapshots are display-only and cannot trigger alerts.
            final json = snapshot.toJson()..['historical'] = true;
            service.invoke('live_snapshot', {'id': id, 'snapshot': json});
          }
        }
      }
      unawaited(reconcileViews());
    }),
  );
  eventSubscriptions.add(
    service.on('live_unwatch').listen((message) {
      if (message != null) views.remove(message['id']);
      unawaited(reconcileViews());
    }),
  );
  leaseTimer = Timer.periodic(
    const Duration(seconds: 3),
    (_) => unawaited(reconcileViews()),
  );

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: ForegroundAlertService.serviceTitle,
      content: ForegroundAlertService.serviceBody,
    );
    DebugLog.info('RTLBusAlertService persistent notification shown');
  }

  eventSubscriptions.add(
    service.on('run_now').listen((_) {
      unawaited(runCheck('foreground_service_manual'));
    }),
  );
  eventSubscriptions.add(
    service.on('stop_service').listen((_) {
      unawaited(stop());
    }),
  );

  final status = await repository.getStatus();
  await repository.saveStatus(
    status.copyWith(
      method: 'Foreground service',
      workerRegistered: true,
      clearLastError: true,
      lastResult: 'Foreground service running',
    ),
  );

  await runCheck('foreground_service_startup');
  if (stopped) return;
  DebugLog.info('RTLBusAlertService service timer started');
  timer = Timer.periodic(ForegroundAlertService.pollInterval, (_) {
    unawaited(runCheck('foreground_service_periodic'));
  });
}
