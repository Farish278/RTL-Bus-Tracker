import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/utils/debug_log.dart';
import 'bus_alert_background_check_service.dart';
import 'bus_alert_repository.dart';

class BackgroundAlertWorker {
  static const taskName = 'rtl_bus_alert_check';
  static const uniqueTaskName = 'rtl_bus_alert_check';

  static final BusAlertRepository _repository = BusAlertRepository();
  static final BusAlertBackgroundCheckService _checkService =
      BusAlertBackgroundCheckService();

  static Future<void> initialize() async {
    DebugLog.info('Background worker initialize');
    await Workmanager().initialize(callbackDispatcher);
    await _repository.migrateLegacyIfNeeded();
  }

  static Future<void> registerPeriodicCheck() async {
    DebugLog.info('Background worker registration attempt');
    DebugLog.throttled(
      'bg_register',
      'Registering periodic background alert check',
      interval: const Duration(seconds: 10),
    );
    await Workmanager().registerPeriodicTask(
      uniqueTaskName,
      taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    final status = await _repository.getStatus();
    await _repository.saveStatus(
      status.copyWith(method: 'WorkManager', workerRegistered: true),
    );
    DebugLog.info('Background worker registration success');
  }

  static Future<void> cancelPeriodicCheck() async {
    await Workmanager().cancelByUniqueName(uniqueTaskName);
    final status = await _repository.getStatus();
    await _repository.saveStatus(status.copyWith(workerRegistered: false));
  }

  static Future<bool> runAlertCheck() async {
    try {
      DebugLog.info('Background alert task start');
      final result = await _checkService.runOnce(source: 'workmanager');
      if (result.error != null) {
        DebugLog.info('Background alert task error: ${result.error}');
      }
      return true;
    } catch (e) {
      DebugLog.info('Background alert task error: $e');
      return true;
    } finally {
      DebugLog.info('Background alert task end');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != BackgroundAlertWorker.taskName) return true;
    return BackgroundAlertWorker.runAlertCheck();
  });
}
