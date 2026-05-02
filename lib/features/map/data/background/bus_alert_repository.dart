import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/debug_log.dart';
import '../../domain/entities/models.dart';

class PersistedBusAlert {
  const PersistedBusAlert({
    required this.id,
    required this.routeId,
    required this.routeCode,
    required this.routeLabel,
    required this.stopId,
    required this.stopCode,
    required this.stopName,
    required this.stopPoint,
    required this.distanceThresholdMeters,
    required this.enabled,
    required this.triggered,
    required this.createdAt,
    this.lastCheckedAt,
    this.lastNearestBusDistanceMeters,
    required this.notificationId,
    this.areaId,
    this.liveApiRouteParam,
  });

  final String id;
  final String routeId;
  final String routeCode;
  final String routeLabel;
  final String stopId;
  final String stopCode;
  final String stopName;
  final LatLng stopPoint;
  final double distanceThresholdMeters;
  final bool enabled;
  final bool triggered;
  final DateTime createdAt;
  final DateTime? lastCheckedAt;
  final double? lastNearestBusDistanceMeters;
  final int notificationId;
  final String? areaId;
  final String? liveApiRouteParam;

  StopAlert toStopAlert() => StopAlert(
    routeCode: routeCode,
    routeLabel: routeLabel,
    stopCode: stopCode,
    stopName: stopName,
    stopPoint: stopPoint,
    distanceThresholdMeters: distanceThresholdMeters,
    armedAt: createdAt,
  );

  PersistedBusAlert copyWith({
    bool? enabled,
    bool? triggered,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    double? lastNearestBusDistanceMeters,
    bool clearLastNearestBusDistanceMeters = false,
  }) {
    return PersistedBusAlert(
      id: id,
      routeId: routeId,
      routeCode: routeCode,
      routeLabel: routeLabel,
      stopId: stopId,
      stopCode: stopCode,
      stopName: stopName,
      stopPoint: stopPoint,
      distanceThresholdMeters: distanceThresholdMeters,
      enabled: enabled ?? this.enabled,
      triggered: triggered ?? this.triggered,
      createdAt: createdAt,
      lastCheckedAt: clearLastCheckedAt
          ? null
          : (lastCheckedAt ?? this.lastCheckedAt),
      lastNearestBusDistanceMeters: clearLastNearestBusDistanceMeters
          ? null
          : (lastNearestBusDistanceMeters ?? this.lastNearestBusDistanceMeters),
      notificationId: notificationId,
      areaId: areaId,
      liveApiRouteParam: liveApiRouteParam,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'routeCode': routeCode,
    'routeLabel': routeLabel,
    'stopId': stopId,
    'stopCode': stopCode,
    'stopName': stopName,
    'stopLat': stopPoint.latitude,
    'stopLng': stopPoint.longitude,
    'distanceThresholdMeters': distanceThresholdMeters,
    'enabled': enabled,
    'triggered': triggered,
    'createdAt': createdAt.toIso8601String(),
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    'lastNearestBusDistanceMeters': lastNearestBusDistanceMeters,
    'notificationId': notificationId,
    'areaId': areaId,
    'liveApiRouteParam': liveApiRouteParam,
  };

  static PersistedBusAlert fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value == null) {
        throw FormatException('Missing required alert field: $key');
      }
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null') {
        throw FormatException('Invalid required alert field: $key');
      }
      return text;
    }

    return PersistedBusAlert(
      id: requireString('id'),
      routeId: requireString('routeId'),
      routeCode: requireString('routeCode'),
      routeLabel: requireString('routeLabel'),
      stopId: requireString('stopId'),
      stopCode: requireString('stopCode'),
      stopName: requireString('stopName'),
      stopPoint: LatLng(
        (json['stopLat'] as num?)?.toDouble() ?? 0,
        (json['stopLng'] as num?)?.toDouble() ?? 0,
      ),
      distanceThresholdMeters:
          (json['distanceThresholdMeters'] as num?)?.toDouble() ?? 400,
      enabled: json['enabled'] == true,
      triggered: json['triggered'] == true,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      lastCheckedAt: json['lastCheckedAt'] == null
          ? null
          : DateTime.tryParse('${json['lastCheckedAt']}'),
      lastNearestBusDistanceMeters:
          (json['lastNearestBusDistanceMeters'] as num?)?.toDouble(),
      notificationId:
          (json['notificationId'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      areaId: json['areaId'] == null ? null : '${json['areaId']}',
      liveApiRouteParam: json['liveApiRouteParam'] == null
          ? null
          : '${json['liveApiRouteParam']}',
    );
  }
}

class BackgroundAlertStatus {
  const BackgroundAlertStatus({
    required this.method,
    required this.workerRegistered,
    this.lastCheckAt,
    this.lastResult,
    this.lastError,
    this.activeAlertsCount = 0,
    this.lastNearestBusDistanceMeters,
    this.lastRouteBusesCount,
    this.lastTriggeredAlertId,
  });

  final String method;
  final bool workerRegistered;
  final DateTime? lastCheckAt;
  final String? lastResult;
  final String? lastError;
  final int activeAlertsCount;
  final double? lastNearestBusDistanceMeters;
  final int? lastRouteBusesCount;
  final String? lastTriggeredAlertId;

  BackgroundAlertStatus copyWith({
    String? method,
    bool? workerRegistered,
    DateTime? lastCheckAt,
    bool clearLastCheckAt = false,
    String? lastResult,
    bool clearLastResult = false,
    String? lastError,
    bool clearLastError = false,
    int? activeAlertsCount,
    double? lastNearestBusDistanceMeters,
    bool clearLastNearestBusDistanceMeters = false,
    int? lastRouteBusesCount,
    bool clearLastRouteBusesCount = false,
    String? lastTriggeredAlertId,
    bool clearLastTriggeredAlertId = false,
  }) {
    return BackgroundAlertStatus(
      method: method ?? this.method,
      workerRegistered: workerRegistered ?? this.workerRegistered,
      lastCheckAt: clearLastCheckAt ? null : (lastCheckAt ?? this.lastCheckAt),
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      activeAlertsCount: activeAlertsCount ?? this.activeAlertsCount,
      lastNearestBusDistanceMeters: clearLastNearestBusDistanceMeters
          ? null
          : (lastNearestBusDistanceMeters ?? this.lastNearestBusDistanceMeters),
      lastRouteBusesCount: clearLastRouteBusesCount
          ? null
          : (lastRouteBusesCount ?? this.lastRouteBusesCount),
      lastTriggeredAlertId: clearLastTriggeredAlertId
          ? null
          : (lastTriggeredAlertId ?? this.lastTriggeredAlertId),
    );
  }

  Map<String, dynamic> toJson() => {
    'method': method,
    'workerRegistered': workerRegistered,
    'lastCheckAt': lastCheckAt?.toIso8601String(),
    'lastResult': lastResult,
    'lastError': lastError,
    'activeAlertsCount': activeAlertsCount,
    'lastNearestBusDistanceMeters': lastNearestBusDistanceMeters,
    'lastRouteBusesCount': lastRouteBusesCount,
    'lastTriggeredAlertId': lastTriggeredAlertId,
  };

  static BackgroundAlertStatus fromJson(Map<String, dynamic> json) {
    return BackgroundAlertStatus(
      method: '${json['method'] ?? 'Foreground service'}',
      workerRegistered: json['workerRegistered'] == true,
      lastCheckAt: json['lastCheckAt'] == null
          ? null
          : DateTime.tryParse('${json['lastCheckAt']}'),
      lastResult: json['lastResult'] == null ? null : '${json['lastResult']}',
      lastError: json['lastError'] == null ? null : '${json['lastError']}',
      activeAlertsCount: (json['activeAlertsCount'] as num?)?.toInt() ?? 0,
      lastNearestBusDistanceMeters:
          (json['lastNearestBusDistanceMeters'] as num?)?.toDouble(),
      lastRouteBusesCount: (json['lastRouteBusesCount'] as num?)?.toInt(),
      lastTriggeredAlertId: json['lastTriggeredAlertId'] == null
          ? null
          : '${json['lastTriggeredAlertId']}',
    );
  }
}

class BusAlertRepository {
  static const alertsPrefKey = 'active_bus_alerts';
  static const statusPrefKey = 'background_alert_status_v1';
  static const alertBackgroundDisabledPrefKey = 'alert_background_disabled_v1';
  static const legacyAlertsPrefKey = 'active_stop_alerts_v2';
  static const legacyAlertPrefKey = 'active_stop_alert_v1';

  SharedPreferences? _sharedPreferences;
  bool _initLogged = false;

  Future<SharedPreferences> _prefs() async {
    if (_sharedPreferences != null) return _sharedPreferences!;
    return initialize();
  }

  Future<SharedPreferences> initialize() async {
    if (!_initLogged) {
      DebugLog.info('BusAlertRepository init start (shared_preferences)');
      _initLogged = true;
    }
    try {
      _sharedPreferences ??= await SharedPreferences.getInstance();
      DebugLog.info('BusAlertRepository init success');
      return _sharedPreferences!;
    } catch (e) {
      DebugLog.info('BusAlertRepository init failed: $e');
      rethrow;
    }
  }

  Future<void> migrateLegacyIfNeeded() async {
    final prefs = await _prefs();
    final hasV2 = (prefs.getString(alertsPrefKey) ?? '').isNotEmpty;
    if (!hasV2) {
      final oldV2Raw = prefs.getString(legacyAlertsPrefKey);
      if (oldV2Raw != null && oldV2Raw.isNotEmpty) {
        await prefs.setString(alertsPrefKey, oldV2Raw);
        await prefs.remove(legacyAlertsPrefKey);
        DebugLog.info('Migrated alert storage key to $alertsPrefKey');
      }
    }
    final legacy = prefs.getString(legacyAlertPrefKey);
    final hasCurrent = (prefs.getString(alertsPrefKey) ?? '').isNotEmpty;
    if (hasCurrent || legacy == null || legacy.isEmpty) return;
    try {
      final json = jsonDecode(legacy) as Map<String, dynamic>;
      final now = DateTime.now();
      final alert = PersistedBusAlert(
        id: 'legacy_${now.microsecondsSinceEpoch}',
        routeId: '${json['routeCode']}',
        routeCode: '${json['routeCode']}',
        routeLabel: '${json['routeLabel']}',
        stopId: '${json['stopCode']}',
        stopCode: '${json['stopCode']}',
        stopName: '${json['stopName']}',
        stopPoint: LatLng(
          (json['stopLat'] as num?)?.toDouble() ?? 0,
          (json['stopLng'] as num?)?.toDouble() ?? 0,
        ),
        distanceThresholdMeters:
            (json['distanceThresholdMeters'] as num?)?.toDouble() ?? 400,
        enabled: true,
        triggered: false,
        createdAt: DateTime.tryParse('${json['armedAt']}') ?? now,
        notificationId: now.millisecondsSinceEpoch.remainder(2147483647),
        liveApiRouteParam: '${json['routeCode']}',
      );
      await saveAlerts([alert]);
      await prefs.remove(legacyAlertPrefKey);
      DebugLog.info('Migrated legacy alert storage to v2');
    } catch (e) {
      DebugLog.info('Legacy alert migration failed: $e');
    }
  }

  Future<List<PersistedBusAlert>> getAlerts() async {
    final prefs = await _prefs();
    final raw = prefs.getString(alertsPrefKey);
    if (raw == null || raw.isEmpty) return <PersistedBusAlert>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        DebugLog.info('Persisted alerts payload is not a list. Resetting.');
        await prefs.remove(alertsPrefKey);
        return <PersistedBusAlert>[];
      }
      final list = <PersistedBusAlert>[];
      var dropped = 0;
      for (final item in decoded) {
        try {
          if (item is! Map<String, dynamic>) {
            dropped++;
            continue;
          }
          final alert = PersistedBusAlert.fromJson(item);
          if (!_isValidPersistedAlert(alert)) {
            dropped++;
            continue;
          }
          list.add(alert);
        } catch (e) {
          dropped++;
          DebugLog.info('Dropping malformed alert entry: $e');
        }
      }
      if (dropped > 0) {
        DebugLog.info('Dropped $dropped malformed persisted alert(s)');
        await saveAlerts(list);
      }
      return list;
    } catch (e) {
      DebugLog.info('Failed to decode alerts: $e');
      await prefs.remove(alertsPrefKey);
      DebugLog.info('Reset malformed persisted alerts at key=$alertsPrefKey');
      return <PersistedBusAlert>[];
    }
  }

  bool _isValidPersistedAlert(PersistedBusAlert alert) {
    if (alert.routeId.trim().isEmpty ||
        alert.routeCode.trim().isEmpty ||
        alert.routeLabel.trim().isEmpty ||
        alert.stopId.trim().isEmpty ||
        alert.stopCode.trim().isEmpty ||
        alert.stopName.trim().isEmpty) {
      return false;
    }
    if (alert.stopPoint.latitude.abs() > 90 ||
        alert.stopPoint.longitude.abs() > 180) {
      return false;
    }
    if (alert.distanceThresholdMeters <= 0 ||
        !alert.distanceThresholdMeters.isFinite) {
      return false;
    }
    return true;
  }

  Future<void> clearAlerts() async {
    final prefs = await _prefs();
    DebugLog.info('Clearing stored alerts');
    await prefs.remove(alertsPrefKey);
    final status = await getStatus();
    await saveStatus(
      status.copyWith(
        activeAlertsCount: 0,
        clearLastNearestBusDistanceMeters: true,
        clearLastTriggeredAlertId: true,
      ),
    );
  }

  Future<void> resetBackgroundStatus({String? lastResult}) async {
    await saveStatus(
      BackgroundAlertStatus(
        method: 'Foreground service',
        workerRegistered: false,
        lastResult: lastResult,
        activeAlertsCount: 0,
      ),
    );
  }

  Future<List<PersistedBusAlert>> getActiveAlerts() async {
    final alerts = await getAlerts();
    return alerts.where((a) => a.enabled && !a.triggered).toList();
  }

  Future<void> saveAlerts(List<PersistedBusAlert> alerts) async {
    final prefs = await _prefs();
    final raw = jsonEncode(alerts.map((a) => a.toJson()).toList());
    DebugLog.info('Saving ${alerts.length} alert(s) to $alertsPrefKey');
    await prefs.setString(alertsPrefKey, raw);
    final status = await getStatus();
    final active = alerts.where((a) => a.enabled && !a.triggered).length;
    await saveStatus(status.copyWith(activeAlertsCount: active));
    DebugLog.info('Stored active alerts count after save: $active');
  }

  Future<void> upsertAlert(PersistedBusAlert alert) async {
    DebugLog.info('Alert save attempt id=${alert.id}');
    final alerts = await getAlerts();
    final next = <PersistedBusAlert>[
      ...alerts.where((a) => a.id != alert.id),
      alert,
    ];
    await saveAlerts(next);
    DebugLog.info('Alert save success id=${alert.id}');
  }

  Future<void> saveAlert(PersistedBusAlert alert) => upsertAlert(alert);

  Future<void> updateAlert(PersistedBusAlert alert) => upsertAlert(alert);

  Future<void> markAlertCancelled(String alertId) async {
    final alerts = await getAlerts();
    final next = alerts
        .map(
          (a) => a.id == alertId
              ? a.copyWith(
                  enabled: false,
                  triggered: false,
                  clearLastNearestBusDistanceMeters: true,
                )
              : a,
        )
        .toList();
    await saveAlerts(next);
  }

  Future<void> cancelAlert(String alertId) => markAlertCancelled(alertId);

  Future<void> markAlertTriggered(
    String alertId, {
    DateTime? lastCheckedAt,
    double? lastNearestBusDistanceMeters,
  }) async {
    final alerts = await getAlerts();
    final next = alerts
        .map(
          (a) => a.id == alertId
              ? a.copyWith(
                  enabled: false,
                  triggered: true,
                  lastCheckedAt: lastCheckedAt,
                  lastNearestBusDistanceMeters: lastNearestBusDistanceMeters,
                )
              : a,
        )
        .toList();
    await saveAlerts(next);
  }

  Future<void> markTriggered(
    String alertId, {
    DateTime? lastCheckedAt,
    double? lastNearestBusDistanceMeters,
  }) => markAlertTriggered(
    alertId,
    lastCheckedAt: lastCheckedAt,
    lastNearestBusDistanceMeters: lastNearestBusDistanceMeters,
  );

  Future<void> markAlertChecked(
    String alertId, {
    required DateTime checkedAt,
    required double? nearestDistanceMeters,
  }) async {
    final alerts = await getAlerts();
    final next = alerts
        .map(
          (a) => a.id == alertId
              ? a.copyWith(
                  lastCheckedAt: checkedAt,
                  lastNearestBusDistanceMeters: nearestDistanceMeters,
                )
              : a,
        )
        .toList();
    await saveAlerts(next);
  }

  Future<BackgroundAlertStatus> getStatus() async {
    final prefs = await _prefs();
    final raw = prefs.getString(statusPrefKey);
    if (raw == null || raw.isEmpty) {
      return const BackgroundAlertStatus(
        method: 'Foreground service',
        workerRegistered: false,
      );
    }
    try {
      return BackgroundAlertStatus.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const BackgroundAlertStatus(
        method: 'Foreground service',
        workerRegistered: false,
      );
    }
  }

  Future<void> saveStatus(BackgroundAlertStatus status) async {
    final prefs = await _prefs();
    await prefs.setString(statusPrefKey, jsonEncode(status.toJson()));
  }

  Future<bool> getAlertBackgroundDisabled() async {
    final prefs = await _prefs();
    return prefs.getBool(alertBackgroundDisabledPrefKey) ?? false;
  }

  Future<void> setAlertBackgroundDisabled(bool value) async {
    final prefs = await _prefs();
    await prefs.setBool(alertBackgroundDisabledPrefKey, value);
  }
}
