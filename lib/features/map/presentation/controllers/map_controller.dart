import 'dart:async';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/debug_log.dart';
import '../../data/api/rtl_bus_api.dart';
import '../../data/background/bus_alert_background_check_service.dart';
import '../../data/background/bus_alert_repository.dart';
import '../../data/background/foreground_alert_service.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/models.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/services/alert_evaluation_service.dart';

class MapState {
  const MapState({
    this.areas = const [],
    this.routes = const [],
    this.selectedAreaCode = AppConfig.defaultAreaCode,
    this.selectedRouteCodes = const {},
    this.geometries = const [],
    this.liveBuses = const [],
    this.stopEtas = const {},
    this.fitPoints = const [],
    this.fitNonce = 0,
    this.showRoutes = true,
    this.showStops = true,
    this.showBuses = true,
    this.isLoading = false,
    this.error,
    this.lastSync,
    this.offlineNotice = false,
    this.activeAlert,
    this.previewAlert,
    this.defaultAlertDistanceMeters = 400,
    this.scheduleMessage = 'Schedule information unavailable',
    this.notificationError,
    this.userLocation,
    this.showUserLocation = false,
    this.locationMessage,
    this.routeSchedules = const {},
    this.loadingScheduleRouteCodes = const {},
    this.scheduleErrorsByRouteCode = const {},
    this.selectedStopScheduleRouteCode,
    this.notificationPermissionGranted,
    this.notificationChannelReady = false,
    this.lastAlertCheckAt,
    this.lastNearestBusDistanceMeters,
    this.lastAlertRouteBusCount,
    this.lastAlertTriggeredAt,
    this.alertStatusMessage,
    this.alertTriggered = false,
    this.backgroundCheckingMethod = 'Foreground service',
    this.backgroundWorkerRegistered = false,
    this.lastBackgroundCheckAt,
    this.lastBackgroundCheckResult,
    this.lastBackgroundError,
    this.backgroundActiveAlertsCount = 0,
    this.lastAlertCreated = false,
    this.lastBackgroundRegistrationAttempted = false,
    this.lastBackgroundRegistrationSucceeded = false,
    this.alertDraftRouteCode,
    this.alertDraftStopName,
    this.alertDraftDistanceMeters,
    this.lastAlertCreationError,
    this.lastAlertStorageOperation,
    this.storedAlertsCount = 0,
    this.activeStoredAlertsCount = 0,
    this.triggeredStoredAlertsCount = 0,
    this.cancelledStoredAlertsCount = 0,
    this.alertStorageSelfTestPassed,
    this.alertStorageSelfTestMessage,
    this.alertBackgroundDisabled = false,
    this.foregroundServiceSupported = true,
    this.lastServiceStartAttempted = false,
    this.lastServiceStartSucceeded = false,
    this.lastServiceStopAttempted = false,
    this.lastServiceStopSucceeded = false,
  });
  final List<BusArea> areas;
  final List<BusRoute> routes;
  final String selectedAreaCode;
  final Set<String> selectedRouteCodes;
  final List<RouteGeometry> geometries;
  final List<BusLocation> liveBuses;
  final Map<String, List<StopEta>> stopEtas;
  final List<LatLng> fitPoints;
  final int fitNonce;
  final bool showRoutes;
  final bool showStops;
  final bool showBuses;
  final bool isLoading;
  final String? error;
  final DateTime? lastSync;
  final bool offlineNotice;
  final StopAlert? activeAlert;
  final StopAlert? previewAlert;
  final double defaultAlertDistanceMeters;
  final String scheduleMessage;
  final String? notificationError;
  final LatLng? userLocation;
  final bool showUserLocation;
  final String? locationMessage;
  final Map<String, RouteSchedule> routeSchedules;
  final Set<String> loadingScheduleRouteCodes;
  final Map<String, String> scheduleErrorsByRouteCode;
  final String? selectedStopScheduleRouteCode;
  final bool? notificationPermissionGranted;
  final bool notificationChannelReady;
  final DateTime? lastAlertCheckAt;
  final double? lastNearestBusDistanceMeters;
  final int? lastAlertRouteBusCount;
  final DateTime? lastAlertTriggeredAt;
  final String? alertStatusMessage;
  final bool alertTriggered;
  final String backgroundCheckingMethod;
  final bool backgroundWorkerRegistered;
  final DateTime? lastBackgroundCheckAt;
  final String? lastBackgroundCheckResult;
  final String? lastBackgroundError;
  final int backgroundActiveAlertsCount;
  final bool lastAlertCreated;
  final bool lastBackgroundRegistrationAttempted;
  final bool lastBackgroundRegistrationSucceeded;
  final String? alertDraftRouteCode;
  final String? alertDraftStopName;
  final double? alertDraftDistanceMeters;
  final String? lastAlertCreationError;
  final String? lastAlertStorageOperation;
  final int storedAlertsCount;
  final int activeStoredAlertsCount;
  final int triggeredStoredAlertsCount;
  final int cancelledStoredAlertsCount;
  final bool? alertStorageSelfTestPassed;
  final String? alertStorageSelfTestMessage;
  final bool alertBackgroundDisabled;
  final bool foregroundServiceSupported;
  final bool lastServiceStartAttempted;
  final bool lastServiceStartSucceeded;
  final bool lastServiceStopAttempted;
  final bool lastServiceStopSucceeded;

  MapState copyWith({
    List<BusArea>? areas,
    List<BusRoute>? routes,
    String? selectedAreaCode,
    Set<String>? selectedRouteCodes,
    List<RouteGeometry>? geometries,
    List<BusLocation>? liveBuses,
    Map<String, List<StopEta>>? stopEtas,
    List<LatLng>? fitPoints,
    int? fitNonce,
    bool? showRoutes,
    bool? showStops,
    bool? showBuses,
    bool? isLoading,
    String? error,
    DateTime? lastSync,
    bool clearError = false,
    bool? offlineNotice,
    StopAlert? activeAlert,
    bool clearActiveAlert = false,
    StopAlert? previewAlert,
    bool clearPreviewAlert = false,
    double? defaultAlertDistanceMeters,
    String? scheduleMessage,
    String? notificationError,
    bool clearNotificationError = false,
    LatLng? userLocation,
    bool clearUserLocation = false,
    bool? showUserLocation,
    String? locationMessage,
    bool clearLocationMessage = false,
    Map<String, RouteSchedule>? routeSchedules,
    Set<String>? loadingScheduleRouteCodes,
    Map<String, String>? scheduleErrorsByRouteCode,
    String? selectedStopScheduleRouteCode,
    bool clearSelectedStopScheduleRouteCode = false,
    bool? notificationPermissionGranted,
    bool clearNotificationPermissionGranted = false,
    bool? notificationChannelReady,
    DateTime? lastAlertCheckAt,
    bool clearLastAlertCheckAt = false,
    double? lastNearestBusDistanceMeters,
    bool clearLastNearestBusDistanceMeters = false,
    int? lastAlertRouteBusCount,
    bool clearLastAlertRouteBusCount = false,
    DateTime? lastAlertTriggeredAt,
    bool clearLastAlertTriggeredAt = false,
    String? alertStatusMessage,
    bool clearAlertStatusMessage = false,
    bool? alertTriggered,
    String? backgroundCheckingMethod,
    bool? backgroundWorkerRegistered,
    DateTime? lastBackgroundCheckAt,
    bool clearLastBackgroundCheckAt = false,
    String? lastBackgroundCheckResult,
    bool clearLastBackgroundCheckResult = false,
    String? lastBackgroundError,
    bool clearLastBackgroundError = false,
    int? backgroundActiveAlertsCount,
    bool? lastAlertCreated,
    bool? lastBackgroundRegistrationAttempted,
    bool? lastBackgroundRegistrationSucceeded,
    String? alertDraftRouteCode,
    bool clearAlertDraftRouteCode = false,
    String? alertDraftStopName,
    bool clearAlertDraftStopName = false,
    double? alertDraftDistanceMeters,
    bool clearAlertDraftDistanceMeters = false,
    String? lastAlertCreationError,
    bool clearLastAlertCreationError = false,
    String? lastAlertStorageOperation,
    bool clearLastAlertStorageOperation = false,
    int? storedAlertsCount,
    int? activeStoredAlertsCount,
    int? triggeredStoredAlertsCount,
    int? cancelledStoredAlertsCount,
    bool? alertStorageSelfTestPassed,
    bool clearAlertStorageSelfTestPassed = false,
    String? alertStorageSelfTestMessage,
    bool clearAlertStorageSelfTestMessage = false,
    bool? alertBackgroundDisabled,
    bool? foregroundServiceSupported,
    bool? lastServiceStartAttempted,
    bool? lastServiceStartSucceeded,
    bool? lastServiceStopAttempted,
    bool? lastServiceStopSucceeded,
  }) {
    return MapState(
      areas: areas ?? this.areas,
      routes: routes ?? this.routes,
      selectedAreaCode: selectedAreaCode ?? this.selectedAreaCode,
      selectedRouteCodes: selectedRouteCodes ?? this.selectedRouteCodes,
      geometries: geometries ?? this.geometries,
      liveBuses: liveBuses ?? this.liveBuses,
      stopEtas: stopEtas ?? this.stopEtas,
      fitPoints: fitPoints ?? this.fitPoints,
      fitNonce: fitNonce ?? this.fitNonce,
      showRoutes: showRoutes ?? this.showRoutes,
      showStops: showStops ?? this.showStops,
      showBuses: showBuses ?? this.showBuses,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastSync: lastSync ?? this.lastSync,
      offlineNotice: offlineNotice ?? this.offlineNotice,
      activeAlert: clearActiveAlert ? null : (activeAlert ?? this.activeAlert),
      previewAlert: clearPreviewAlert
          ? null
          : (previewAlert ?? this.previewAlert),
      defaultAlertDistanceMeters:
          defaultAlertDistanceMeters ?? this.defaultAlertDistanceMeters,
      scheduleMessage: scheduleMessage ?? this.scheduleMessage,
      notificationError: clearNotificationError
          ? null
          : (notificationError ?? this.notificationError),
      userLocation: clearUserLocation
          ? null
          : (userLocation ?? this.userLocation),
      showUserLocation: showUserLocation ?? this.showUserLocation,
      locationMessage: clearLocationMessage
          ? null
          : (locationMessage ?? this.locationMessage),
      routeSchedules: routeSchedules ?? this.routeSchedules,
      loadingScheduleRouteCodes:
          loadingScheduleRouteCodes ?? this.loadingScheduleRouteCodes,
      scheduleErrorsByRouteCode:
          scheduleErrorsByRouteCode ?? this.scheduleErrorsByRouteCode,
      selectedStopScheduleRouteCode: clearSelectedStopScheduleRouteCode
          ? null
          : (selectedStopScheduleRouteCode ??
                this.selectedStopScheduleRouteCode),
      notificationPermissionGranted: clearNotificationPermissionGranted
          ? null
          : (notificationPermissionGranted ??
                this.notificationPermissionGranted),
      notificationChannelReady:
          notificationChannelReady ?? this.notificationChannelReady,
      lastAlertCheckAt: clearLastAlertCheckAt
          ? null
          : (lastAlertCheckAt ?? this.lastAlertCheckAt),
      lastNearestBusDistanceMeters: clearLastNearestBusDistanceMeters
          ? null
          : (lastNearestBusDistanceMeters ?? this.lastNearestBusDistanceMeters),
      lastAlertRouteBusCount: clearLastAlertRouteBusCount
          ? null
          : (lastAlertRouteBusCount ?? this.lastAlertRouteBusCount),
      lastAlertTriggeredAt: clearLastAlertTriggeredAt
          ? null
          : (lastAlertTriggeredAt ?? this.lastAlertTriggeredAt),
      alertStatusMessage: clearAlertStatusMessage
          ? null
          : (alertStatusMessage ?? this.alertStatusMessage),
      alertTriggered: alertTriggered ?? this.alertTriggered,
      backgroundCheckingMethod:
          backgroundCheckingMethod ?? this.backgroundCheckingMethod,
      backgroundWorkerRegistered:
          backgroundWorkerRegistered ?? this.backgroundWorkerRegistered,
      lastBackgroundCheckAt: clearLastBackgroundCheckAt
          ? null
          : (lastBackgroundCheckAt ?? this.lastBackgroundCheckAt),
      lastBackgroundCheckResult: clearLastBackgroundCheckResult
          ? null
          : (lastBackgroundCheckResult ?? this.lastBackgroundCheckResult),
      lastBackgroundError: clearLastBackgroundError
          ? null
          : (lastBackgroundError ?? this.lastBackgroundError),
      backgroundActiveAlertsCount:
          backgroundActiveAlertsCount ?? this.backgroundActiveAlertsCount,
      lastAlertCreated: lastAlertCreated ?? this.lastAlertCreated,
      lastBackgroundRegistrationAttempted:
          lastBackgroundRegistrationAttempted ??
          this.lastBackgroundRegistrationAttempted,
      lastBackgroundRegistrationSucceeded:
          lastBackgroundRegistrationSucceeded ??
          this.lastBackgroundRegistrationSucceeded,
      alertDraftRouteCode: clearAlertDraftRouteCode
          ? null
          : (alertDraftRouteCode ?? this.alertDraftRouteCode),
      alertDraftStopName: clearAlertDraftStopName
          ? null
          : (alertDraftStopName ?? this.alertDraftStopName),
      alertDraftDistanceMeters: clearAlertDraftDistanceMeters
          ? null
          : (alertDraftDistanceMeters ?? this.alertDraftDistanceMeters),
      lastAlertCreationError: clearLastAlertCreationError
          ? null
          : (lastAlertCreationError ?? this.lastAlertCreationError),
      lastAlertStorageOperation: clearLastAlertStorageOperation
          ? null
          : (lastAlertStorageOperation ?? this.lastAlertStorageOperation),
      storedAlertsCount: storedAlertsCount ?? this.storedAlertsCount,
      activeStoredAlertsCount:
          activeStoredAlertsCount ?? this.activeStoredAlertsCount,
      triggeredStoredAlertsCount:
          triggeredStoredAlertsCount ?? this.triggeredStoredAlertsCount,
      cancelledStoredAlertsCount:
          cancelledStoredAlertsCount ?? this.cancelledStoredAlertsCount,
      alertStorageSelfTestPassed: clearAlertStorageSelfTestPassed
          ? null
          : (alertStorageSelfTestPassed ?? this.alertStorageSelfTestPassed),
      alertStorageSelfTestMessage: clearAlertStorageSelfTestMessage
          ? null
          : (alertStorageSelfTestMessage ?? this.alertStorageSelfTestMessage),
      alertBackgroundDisabled:
          alertBackgroundDisabled ?? this.alertBackgroundDisabled,
      foregroundServiceSupported:
          foregroundServiceSupported ?? this.foregroundServiceSupported,
      lastServiceStartAttempted:
          lastServiceStartAttempted ?? this.lastServiceStartAttempted,
      lastServiceStartSucceeded:
          lastServiceStartSucceeded ?? this.lastServiceStartSucceeded,
      lastServiceStopAttempted:
          lastServiceStopAttempted ?? this.lastServiceStopAttempted,
      lastServiceStopSucceeded:
          lastServiceStopSucceeded ?? this.lastServiceStopSucceeded,
    );
  }
}

class AlertEnableResult {
  const AlertEnableResult({
    required this.success,
    required this.message,
    this.backgroundWarning,
  });

  final bool success;
  final String message;
  final String? backgroundWarning;
}

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  return MapRepositoryImpl(RtlBusApi(DioClient()));
});

final mapControllerProvider = StateNotifierProvider<MapController, MapState>((
  ref,
) {
  final c = MapController(ref.read(mapRepositoryProvider));
  unawaited(c.loadInitial());
  return c;
});

class MapController extends StateNotifier<MapState> {
  MapController(this._repo) : super(const MapState());
  final MapRepository _repo;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Distance _distance = const Distance();
  final AlertEvaluationService _alertEvaluationService =
      AlertEvaluationService();
  final BusAlertRepository _alertRepository = BusAlertRepository();
  final BusAlertBackgroundCheckService _backgroundCheckService =
      BusAlertBackgroundCheckService();
  final Map<String, LatLng> _lastBusPoints = <String, LatLng>{};
  static const _notificationChannelId = 'rtl_stop_alerts';
  static const _notificationChannelName = 'RTL Stop Alerts';
  static const _notificationChannelDescription =
      'Notifications when a selected bus route is near a selected stop';
  final Map<String, double> _lastBusHeadings = <String, double>{};
  SharedPreferences? _prefs;
  StreamSubscription<List<BusLocation>>? _liveSub;
  bool _notificationInitDone = false;
  bool _isEvaluatingAlert = false;
  DateTime _lastAlertCheckThrottleAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _defaultAlertDistancePrefKey = 'default_alert_distance_m_v1';
  static const _selectedAreaCodePrefKey = 'selected_area_code_v1';
  int _liveWatchGeneration = 0;
  bool _isMapScreenActive = true;
  bool _isImmediateLiveFetchInFlight = false;
  int _staticRefreshGeneration = 0;

  Future<void> loadInitial({
    bool force = false,
    bool shouldAutoFit = true,
  }) async {
    DebugLog.info('loadInitial(force: $force) start');
    final hadRoutes = state.routes.isNotEmpty;
    state = state.copyWith(
      isLoading: !hadRoutes,
      clearError: true,
      offlineNotice: hadRoutes ? state.offlineNotice : false,
    );
    try {
      final loadStartedAt = DateTime.now();
      _prefs ??= await SharedPreferences.getInstance();
      await _alertRepository.initialize();
      await _alertRepository.migrateLegacyIfNeeded();
      final savedDistance =
          _prefs?.getDouble(_defaultAlertDistancePrefKey) ?? 400;
      final savedAreaCode = _prefs?.getString(_selectedAreaCodePrefKey);
      final preferredAreaCode =
          (savedAreaCode != null && savedAreaCode.isNotEmpty)
          ? savedAreaCode
          : state.selectedAreaCode;
      final areas = await _repo.getAreas(forceRefresh: false);
      final selected = areas.any((e) => e.code == preferredAreaCode)
          ? preferredAreaCode
          : (areas.any((e) => e.code == AppConfig.defaultAreaCode)
                ? AppConfig.defaultAreaCode
                : (areas.isNotEmpty ? areas.first.code : ''));
      final routes = await _repo.getRoutes(selected, forceRefresh: false);
      final routeCodes = routes.map((r) => r.routeCode).toSet();
      final selectedRouteCodes = state.selectedRouteCodes
          .where(routeCodes.contains)
          .toSet();
      final selectedStopScheduleRouteCode =
          selectedRouteCodes.contains(state.selectedStopScheduleRouteCode)
          ? state.selectedStopScheduleRouteCode
          : null;
      final geometries = selectedRouteCodes.isEmpty
          ? const <RouteGeometry>[]
          : await _repo.getRouteGeometry(
              selectedRouteCodes.toList(),
              forceRefresh: force,
            );
      final stopEtas = selectedRouteCodes.isEmpty
          ? const <String, List<StopEta>>{}
          : await _repo.getStopEtasForRoutes(selectedRouteCodes.toList());
      final scheduleRouteCodes = state.routeSchedules.keys
          .where(routeCodes.contains)
          .toSet();
      final shouldClearActiveAlert =
          state.activeAlert != null &&
          !selectedRouteCodes.contains(state.activeAlert!.routeCode);
      final nextSchedules = {
        for (final entry in state.routeSchedules.entries)
          if (scheduleRouteCodes.contains(entry.key)) entry.key: entry.value,
      };
      final nextScheduleErrors = {
        for (final entry in state.scheduleErrorsByRouteCode.entries)
          if (scheduleRouteCodes.contains(entry.key)) entry.key: entry.value,
      };
      await _prefs?.setString(_selectedAreaCodePrefKey, selected);
      state = state.copyWith(
        areas: areas,
        routes: routes,
        selectedAreaCode: selected,
        selectedRouteCodes: selectedRouteCodes,
        geometries: geometries,
        stopEtas: stopEtas,
        liveBuses: state.liveBuses
            .where((bus) => selectedRouteCodes.contains(bus.routeCode))
            .toList(),
        routeSchedules: nextSchedules,
        scheduleErrorsByRouteCode: nextScheduleErrors,
        clearSelectedStopScheduleRouteCode:
            selectedStopScheduleRouteCode == null,
        selectedStopScheduleRouteCode: selectedStopScheduleRouteCode,
        clearPreviewAlert: true,
        clearActiveAlert: shouldClearActiveAlert,
        isLoading: false,
        lastSync: DateTime.now(),
        offlineNotice: false,
        defaultAlertDistanceMeters: savedDistance,
        scheduleMessage: _scheduleSummaryForSelection(
          routes,
          selectedRouteCodes,
        ),
      );
      if (shouldAutoFit) {
        _scheduleFit();
      }
      await _restartLiveWatch();
      if (shouldClearActiveAlert) {
        if (state.activeAlert != null) {
          await _cancelPersistedAlertFor(state.activeAlert!);
        }
        await ForegroundAlertService.stopIfRunning();
      }
      await _restoreAlert();
      await _refreshBackgroundStatus();
      await _refreshNotificationPermissionStatus();
      DebugLog.throttled(
        'startup_cache_perf',
        'startup cache-first ready in ${DateTime.now().difference(loadStartedAt).inMilliseconds}ms routes=${routes.length}',
        interval: const Duration(seconds: 2),
      );
      if (force) {
        unawaited(_refreshStaticDataInBackground(selected));
      }
      DebugLog.info(
        'loadInitial done: areas=${areas.length}, routes=${routes.length}',
      );
    } catch (e, st) {
      DebugLog.info('loadInitial error: $e');
      DebugLog.info('loadInitial stack: $st');
      try {
        final fallbackAreas = await _repo.getAreas(forceRefresh: false);
        final fallbackSelected =
            fallbackAreas.any((a) => a.code == state.selectedAreaCode)
            ? state.selectedAreaCode
            : (fallbackAreas.any((a) => a.code == AppConfig.defaultAreaCode)
                  ? AppConfig.defaultAreaCode
                  : (fallbackAreas.firstOrNull?.code ?? ''));
        final fallbackRoutes = await _repo.getRoutes(
          fallbackSelected,
          forceRefresh: false,
        );
        state = state.copyWith(
          areas: fallbackAreas,
          routes: fallbackRoutes,
          selectedAreaCode: fallbackSelected,
          isLoading: false,
          error: await _friendlyStartupError(e),
          offlineNotice: true,
        );
      } catch (_) {
        state = state.copyWith(
          isLoading: false,
          error: await _friendlyStartupError(e),
          offlineNotice: true,
        );
      }
    }
  }

  Future<void> _refreshStaticDataInBackground(String selectedAreaCode) async {
    final generation = ++_staticRefreshGeneration;
    final started = DateTime.now();
    DebugLog.throttled(
      'static_refresh_start',
      'background static refresh start area=$selectedAreaCode',
      interval: const Duration(seconds: 2),
    );
    try {
      final freshAreas = await _repo.getAreas(forceRefresh: true);
      if (generation != _staticRefreshGeneration) return;
      final selected = freshAreas.any((a) => a.code == selectedAreaCode)
          ? selectedAreaCode
          : (freshAreas.any((a) => a.code == AppConfig.defaultAreaCode)
                ? AppConfig.defaultAreaCode
                : (freshAreas.firstOrNull?.code ?? ''));
      final freshRoutes = await _repo.getRoutes(selected, forceRefresh: true);
      if (generation != _staticRefreshGeneration) return;
      final routeCodes = freshRoutes.map((r) => r.routeCode).toSet();
      final keptSelected = state.selectedRouteCodes
          .where(routeCodes.contains)
          .toSet();
      state = state.copyWith(
        areas: freshAreas,
        routes: freshRoutes,
        selectedAreaCode: selected,
        selectedRouteCodes: keptSelected,
        lastSync: DateTime.now(),
        offlineNotice: false,
      );
      DebugLog.throttled(
        'static_refresh_done',
        'background static refresh done in ${DateTime.now().difference(started).inMilliseconds}ms routes=${freshRoutes.length}',
        interval: const Duration(seconds: 2),
      );
    } catch (e) {
      DebugLog.info('background static refresh failed: $e');
      state = state.copyWith(offlineNotice: true);
    }
  }

  Future<void> selectArea(String code) async {
    DebugLog.info('selectArea($code)');
    final routes = await _repo.getRoutes(code);
    await _prefs?.setString(_selectedAreaCodePrefKey, code);
    state = state.copyWith(
      selectedAreaCode: code,
      routes: routes,
      selectedRouteCodes: {},
      geometries: [],
      liveBuses: [],
      stopEtas: {},
      clearActiveAlert: true,
      clearPreviewAlert: true,
      clearSelectedStopScheduleRouteCode: true,
      scheduleMessage: _scheduleSummaryForSelection(routes, const {}),
    );
    _scheduleFit();
    await _restartLiveWatch();
  }

  Future<void> toggleRoute(String code) async {
    final next = {...state.selectedRouteCodes};
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    DebugLog.info('toggleRoute($code) -> selected=${next.length}');
    state = state.copyWith(selectedRouteCodes: next, isLoading: true);
    if (state.previewAlert != null &&
        !next.contains(state.previewAlert!.routeCode)) {
      state = state.copyWith(clearPreviewAlert: true);
    }
    if (state.activeAlert != null &&
        !next.contains(state.activeAlert!.routeCode)) {
      state = state.copyWith(clearActiveAlert: true);
      await _cancelPersistedAlertFor(state.activeAlert!);
      await ForegroundAlertService.reconcileWithStoredAlerts();
    }
    _clearBusesForDeselectedRoutes(next);
    _scheduleFit();
    final geos = await _repo.getRouteGeometry(next.toList());
    if (!_sameSelection(next, state.selectedRouteCodes)) return;
    final etas = await _repo.getStopEtasForRoutes(next.toList());
    if (!_sameSelection(next, state.selectedRouteCodes)) return;
    state = state.copyWith(
      geometries: geos,
      stopEtas: etas,
      isLoading: false,
      scheduleMessage: _scheduleSummaryForSelection(state.routes, next),
    );
    _scheduleFit();
    await _restartLiveWatch();
  }

  bool _sameSelection(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _scheduleFit() {
    final selectedRoutes = state.routes
        .where((e) => state.selectedRouteCodes.contains(e.routeCode))
        .toList();
    final points = <LatLng>[];
    for (final geo in state.geometries) {
      if (state.selectedRouteCodes.contains(geo.routeCode)) {
        points.addAll(geo.points);
      }
    }
    if (points.isEmpty) {
      for (final route in selectedRoutes) {
        points.addAll(route.stops.map((e) => e.point));
      }
    }
    if (points.isEmpty) {
      points.add(const LatLng(AppConfig.defaultLat, AppConfig.defaultLng));
    }
    state = state.copyWith(fitPoints: points, fitNonce: state.fitNonce + 1);
  }

  Future<void> _restartLiveWatch() async {
    await _liveSub?.cancel();
    _liveSub = null;
    _liveWatchGeneration++;
    final watchGeneration = _liveWatchGeneration;
    final selectedCodes = state.selectedRouteCodes.toSet();
    if (selectedCodes.isEmpty || !_isMapScreenActive) {
      DebugLog.info(
        'live watch stopped: selected=${selectedCodes.length}, mapActive=$_isMapScreenActive',
      );
      state = state.copyWith(liveBuses: const []);
      return;
    }
    DebugLog.info(
      'live watch start: routes=${selectedCodes.length}, interval=8s',
    );
    unawaited(_fetchLiveBusesImmediately(selectedCodes, watchGeneration));
    _liveSub = _repo.watchLiveBusLocations(selectedCodes.toList()).listen((
      buses,
    ) {
      if (watchGeneration != _liveWatchGeneration) return;
      final activeSelected = state.selectedRouteCodes;
      final filtered = buses
          .where((bus) => activeSelected.contains(bus.routeCode))
          .toList();
      final withDerivedBearing = _applyDerivedBearings(filtered);
      DebugLog.throttled(
        'live_watch_update',
        'live watch update: buses=${withDerivedBearing.length}',
      );
      state = state.copyWith(liveBuses: withDerivedBearing);
      unawaited(_evaluateAlert(withDerivedBearing));
    });
  }

  Future<void> _fetchLiveBusesImmediately(
    Set<String> selectedCodes,
    int watchGeneration,
  ) async {
    if (_isImmediateLiveFetchInFlight) return;
    _isImmediateLiveFetchInFlight = true;
    final sw = Stopwatch()..start();
    try {
      final buses = await _repo.getLiveBusLocations(selectedCodes.toList());
      if (watchGeneration != _liveWatchGeneration) return;
      final activeSelected = state.selectedRouteCodes;
      final filtered = buses
          .where((bus) => activeSelected.contains(bus.routeCode))
          .toList();
      final withDerivedBearing = _applyDerivedBearings(filtered);
      state = state.copyWith(liveBuses: withDerivedBearing);
      unawaited(_evaluateAlert(withDerivedBearing));
      DebugLog.throttled(
        'live_immediate_fetch',
        'immediate live fetch buses=${withDerivedBearing.length} took=${sw.elapsedMilliseconds}ms',
        interval: const Duration(seconds: 2),
      );
    } catch (e) {
      DebugLog.info('immediate live fetch failed: $e');
    } finally {
      _isImmediateLiveFetchInFlight = false;
      sw.stop();
    }
  }

  void _clearBusesForDeselectedRoutes(Set<String> nextSelected) {
    final nextBuses = state.liveBuses
        .where((bus) => nextSelected.contains(bus.routeCode))
        .toList();
    state = state.copyWith(liveBuses: nextBuses);
  }

  List<BusLocation> _applyDerivedBearings(List<BusLocation> buses) {
    final next = <BusLocation>[];
    for (final bus in buses) {
      final key =
          '${bus.routeCode}:${bus.busCode.isNotEmpty ? bus.busCode : bus.plateNumber}';
      final prev = _lastBusPoints[key];
      final heading =
          bus.heading ??
          _calculateBearing(prev, bus.point) ??
          _lastBusHeadings[key];
      _lastBusPoints[key] = bus.point;
      if (heading != null) {
        _lastBusHeadings[key] = heading;
      }
      next.add(
        BusLocation(
          routeCode: bus.routeCode,
          busCode: bus.busCode,
          plateNumber: bus.plateNumber,
          point: bus.point,
          heading: heading,
          direction: bus.direction,
          destination: bus.destination,
          nextStop: bus.nextStop,
          tripDirection: bus.tripDirection,
        ),
      );
    }
    return next;
  }

  double? _calculateBearing(LatLng? from, LatLng to) {
    if (from == null) return null;
    final movedMeters = _distance.as(LengthUnit.Meter, from, to);
    if (movedMeters < 15) return null;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void toggleLayer({bool? routes, bool? stops, bool? buses}) {
    state = state.copyWith(
      showRoutes: routes,
      showStops: stops,
      showBuses: buses,
    );
    if (buses != null) {
      DebugLog.info('toggleLayer(showBuses: $buses)');
      unawaited(_restartLiveWatch());
    }
  }

  void setMapScreenActive(bool active) {
    if (_isMapScreenActive == active) return;
    _isMapScreenActive = active;
    DebugLog.info('setMapScreenActive($active)');
    unawaited(_restartLiveWatch());
  }

  Future<void> clearCache() async {
    try {
      await _repo.clearCache();
      await loadInitial(force: true);
    } catch (e) {
      state = state.copyWith(
        error:
            'Failed to clear local cache. Please reinstall the app on emulator.',
      );
    }
  }

  void selectStopScheduleRouteCode(String routeCode) {
    state = state.copyWith(selectedStopScheduleRouteCode: routeCode);
  }

  void setAlertDraftContext({
    required String? routeCode,
    required String? stopName,
    required double? distanceMeters,
  }) {
    if (state.alertDraftRouteCode == routeCode &&
        state.alertDraftStopName == stopName &&
        state.alertDraftDistanceMeters == distanceMeters) {
      return;
    }
    state = state.copyWith(
      alertDraftRouteCode: routeCode,
      alertDraftStopName: stopName,
      alertDraftDistanceMeters: distanceMeters,
    );
  }

  Future<void> loadSchedulesForStop(
    BusStop stop,
    List<BusRoute> routes, {
    bool forceRefresh = false,
  }) async {
    if (routes.isEmpty) return;
    final preferred = state.selectedRouteCodes
        .where((code) => routes.any((r) => r.routeCode == code))
        .firstOrNull;
    final nextSelectedRouteCode =
        preferred ?? (routes.length == 1 ? routes.first.routeCode : null);
    state = state.copyWith(
      selectedStopScheduleRouteCode: nextSelectedRouteCode,
      clearSelectedStopScheduleRouteCode: nextSelectedRouteCode == null,
    );

    for (final route in routes) {
      final routeCode = route.routeCode;
      final hasCache = state.routeSchedules.containsKey(routeCode);
      if (hasCache && !forceRefresh) continue;

      final nextLoading = {...state.loadingScheduleRouteCodes, routeCode};
      final nextErrors = {...state.scheduleErrorsByRouteCode}
        ..remove(routeCode);
      state = state.copyWith(
        loadingScheduleRouteCodes: nextLoading,
        scheduleErrorsByRouteCode: nextErrors,
      );
      try {
        final schedule = await _repo.getRouteSchedule(
          routeCode,
          forceRefresh: forceRefresh,
        );
        final updatedSchedules = {...state.routeSchedules};
        if (schedule != null) {
          updatedSchedules[routeCode] = schedule;
        }
        final updatedLoading = {...state.loadingScheduleRouteCodes}
          ..remove(routeCode);
        state = state.copyWith(
          routeSchedules: updatedSchedules,
          loadingScheduleRouteCodes: updatedLoading,
        );
      } catch (_) {
        final updatedLoading = {...state.loadingScheduleRouteCodes}
          ..remove(routeCode);
        final updatedErrors = {...state.scheduleErrorsByRouteCode};
        updatedErrors[routeCode] = 'Schedule information unavailable';
        state = state.copyWith(
          loadingScheduleRouteCodes: updatedLoading,
          scheduleErrorsByRouteCode: updatedErrors,
        );
      }
    }
  }

  Future<void> loadScheduleForRoute(
    BusRoute route, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && state.routeSchedules.containsKey(route.routeCode)) {
      return;
    }
    if (state.loadingScheduleRouteCodes.contains(route.routeCode)) return;
    final loading = {...state.loadingScheduleRouteCodes, route.routeCode};
    final errors = {...state.scheduleErrorsByRouteCode}
      ..remove(route.routeCode);
    state = state.copyWith(
      loadingScheduleRouteCodes: loading,
      scheduleErrorsByRouteCode: errors,
      selectedStopScheduleRouteCode: route.routeCode,
    );
    try {
      final schedule = await _repo.getRouteSchedule(
        route.routeCode,
        forceRefresh: forceRefresh,
      );
      final nextLoading = {...state.loadingScheduleRouteCodes}
        ..remove(route.routeCode);
      final nextSchedules = {...state.routeSchedules};
      if (schedule != null) {
        nextSchedules[route.routeCode] = schedule;
      }
      state = state.copyWith(
        loadingScheduleRouteCodes: nextLoading,
        routeSchedules: nextSchedules,
      );
      if (forceRefresh) {
        unawaited(() async {
          await Future<void>.delayed(const Duration(seconds: 2));
          await loadScheduleForRoute(route);
        }());
      }
    } catch (_) {
      final nextLoading = {...state.loadingScheduleRouteCodes}
        ..remove(route.routeCode);
      final nextErrors = {...state.scheduleErrorsByRouteCode};
      nextErrors[route.routeCode] = 'Schedule information unavailable';
      state = state.copyWith(
        loadingScheduleRouteCodes: nextLoading,
        scheduleErrorsByRouteCode: nextErrors,
      );
    }
  }

  Future<AlertEnableResult> enableStopAlert({
    required BusRoute route,
    required BusStop stop,
    double? thresholdMeters,
  }) async {
    try {
      if (route.routeCode.trim().isEmpty || route.id.trim().isEmpty) {
        state = state.copyWith(
          notificationError: 'Select a route to enable alerts.',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError: 'ValidationError: route not selected',
          lastAlertStorageOperation: 'validate',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Select a route to enable alerts.',
        );
      }
      if (stop.id.trim().isEmpty ||
          stop.code.trim().isEmpty ||
          stop.name.trim().isEmpty) {
        state = state.copyWith(
          notificationError: 'Select a stop to enable alerts.',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError: 'ValidationError: stop not selected',
          lastAlertStorageOperation: 'validate',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Select a stop to enable alerts.',
        );
      }
      if (stop.point.latitude.abs() > 90 || stop.point.longitude.abs() > 180) {
        state = state.copyWith(
          notificationError: 'Stop location unavailable.',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError: 'ValidationError: stop coordinates invalid',
          lastAlertStorageOperation: 'validate',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Stop location unavailable.',
        );
      }
      await _requestNotificationPermissionIfNeeded();
      final notificationsAllowed = state.notificationPermissionGranted ?? false;
      if (!notificationsAllowed) {
        state = state.copyWith(
          notificationError:
              'Notification permission is required to enable alerts.',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError:
              'ValidationError: notification permission denied',
          lastAlertStorageOperation: 'validate',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Notification permission is required to enable alerts.',
        );
      }
      final effectiveThreshold =
          thresholdMeters ?? state.defaultAlertDistanceMeters;
      if (effectiveThreshold <= 0 || effectiveThreshold.isNaN) {
        state = state.copyWith(
          notificationError: 'Choose a notification distance.',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError: 'ValidationError: invalid distance',
          lastAlertStorageOperation: 'validate',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Choose a notification distance.',
        );
      }
      final alert = StopAlert(
        routeCode: route.routeCode,
        routeLabel: route.routeNumber.isEmpty
            ? route.routeCode
            : route.routeNumber,
        stopCode: stop.code,
        stopName: stop.name,
        stopPoint: stop.point,
        distanceThresholdMeters: effectiveThreshold,
        armedAt: DateTime.now(),
      );
      final alertId =
          '${route.id}_${stop.id}_${DateTime.now().millisecondsSinceEpoch}';
      try {
        state = state.copyWith(lastAlertStorageOperation: 'save');
        await _alertRepository.upsertAlert(
          PersistedBusAlert(
            id: alertId,
            routeId: route.id,
            routeCode: route.routeCode,
            routeLabel: route.routeNumber.isEmpty
                ? route.routeCode
                : route.routeNumber,
            stopId: stop.id,
            stopCode: stop.code,
            stopName: stop.name,
            stopPoint: stop.point,
            distanceThresholdMeters: effectiveThreshold,
            enabled: true,
            triggered: false,
            createdAt: DateTime.now(),
            notificationId: DateTime.now().millisecondsSinceEpoch.remainder(
              2147483647,
            ),
            areaId: route.areaCode,
            liveApiRouteParam: route.routeCode,
          ),
        );
        final persistedAlerts = await _alertRepository.getActiveAlerts();
        final saved = persistedAlerts.any((a) => a.id == alertId);
        if (!saved) {
          throw StateError('Alert save verification failed');
        }
      } catch (e, st) {
        DebugLog.info('enableStopAlert persist failed: $e');
        DebugLog.info('enableStopAlert persist stack: $st');
        state = state.copyWith(
          notificationError: 'Could not create alert. $e',
          lastBackgroundError: '$e\n$st',
          lastAlertCreated: false,
          lastBackgroundRegistrationAttempted: false,
          lastBackgroundRegistrationSucceeded: false,
          lastAlertCreationError: '${e.runtimeType}: $e',
          lastAlertStorageOperation: 'save_failed',
        );
        return const AlertEnableResult(
          success: false,
          message: 'Could not save alert. Please try clearing stored alerts.',
        );
      }
      final allAfterSave = await _alertRepository.getAlerts();
      final activeAlertsCount = allAfterSave
          .where((a) => a.enabled && !a.triggered)
          .length;
      state = state.copyWith(
        activeAlert: alert,
        clearPreviewAlert: true,
        clearNotificationError: true,
        clearLastAlertCreationError: true,
        alertStatusMessage:
            'Alert enabled for ${alert.stopName} within ${effectiveThreshold.toInt()} m.',
        alertTriggered: false,
        clearLastAlertTriggeredAt: true,
        scheduleMessage: _scheduleSummaryForSelection(
          state.routes,
          state.selectedRouteCodes,
        ),
        backgroundActiveAlertsCount: activeAlertsCount,
        storedAlertsCount: allAfterSave.length,
        activeStoredAlertsCount: activeAlertsCount,
        triggeredStoredAlertsCount: allAfterSave
            .where((a) => a.triggered)
            .length,
        cancelledStoredAlertsCount: allAfterSave
            .where((a) => !a.enabled && !a.triggered)
            .length,
        lastAlertCreated: true,
        lastBackgroundRegistrationAttempted: true,
        lastBackgroundRegistrationSucceeded: false,
        lastServiceStartAttempted: true,
        lastServiceStartSucceeded: false,
        lastAlertStorageOperation: 'save_success',
      );
      if (state.liveBuses.isEmpty) {
        state = state.copyWith(
          alertStatusMessage: 'Alert enabled. Waiting for live bus data.',
        );
      }

      // Run an immediate check so alerts already inside the selected radius
      // are triggered right away without keeping a background service alive.
      final immediateResult = await _backgroundCheckService.runOnce(
        source: 'notify_me_initial',
      );
      final activeAfterImmediate = await _alertRepository.getActiveAlerts();
      if (activeAfterImmediate.isEmpty &&
          immediateResult.triggeredAlertsCount > 0) {
        await ForegroundAlertService.stopIfRunning();
        await _refreshBackgroundStatus();
        state = state.copyWith(
          clearActiveAlert: true,
          alertTriggered: true,
          lastAlertTriggeredAt: DateTime.now(),
          alertStatusMessage:
              'Bus is already within ${effectiveThreshold.toInt()} m. Alert triggered.',
        );
        return AlertEnableResult(
          success: true,
          message:
              'Bus is already within ${effectiveThreshold.toInt()} m. Alert triggered.',
        );
      }

      String? backgroundWarning;
      try {
        final started = await ForegroundAlertService.ensureRunning();
        await _refreshBackgroundStatus();
        state = state.copyWith(
          lastBackgroundRegistrationSucceeded: started,
          lastServiceStartSucceeded: started,
          alertStatusMessage: started
              ? 'Alert enabled. Background monitoring is active.'
              : 'Alert saved, but background monitoring could not start.',
        );
        if (started) {
          await _alertRepository.setAlertBackgroundDisabled(false);
          state = state.copyWith(alertBackgroundDisabled: false);
        } else {
          backgroundWarning =
              'Alert saved, but background monitoring could not start.';
          await _alertRepository.setAlertBackgroundDisabled(true);
          state = state.copyWith(alertBackgroundDisabled: true);
        }
      } catch (e, st) {
        DebugLog.info('enableStopAlert background registration failed: $e');
        DebugLog.info('enableStopAlert background stack: $st');
        backgroundWarning =
            'Alert saved, but background monitoring could not start.';
        await _alertRepository.setAlertBackgroundDisabled(true);
        state = state.copyWith(
          alertBackgroundDisabled: true,
          lastBackgroundRegistrationSucceeded: false,
          lastServiceStartSucceeded: false,
          lastBackgroundError: '$e',
          alertStatusMessage: backgroundWarning,
        );
      }

      return AlertEnableResult(
        success: true,
        message:
            'Alert enabled for ${alert.stopName} within ${effectiveThreshold.toInt()} m.',
        backgroundWarning: backgroundWarning,
      );
    } catch (e, st) {
      DebugLog.info('enableStopAlert unexpected error: $e');
      DebugLog.info('enableStopAlert unexpected stack: $st');
      state = state.copyWith(
        notificationError: 'Could not enable alert safely.',
        lastAlertCreated: false,
        lastBackgroundRegistrationAttempted: false,
        lastBackgroundRegistrationSucceeded: false,
        lastAlertCreationError: '${e.runtimeType}: $e',
        lastAlertStorageOperation: 'unexpected_failed',
      );
      return AlertEnableResult(
        success: false,
        message: 'Could not enable alert safely.',
      );
    }
  }

  String _scheduleSummaryForSelection(
    List<BusRoute> routes,
    Set<String> selectedCodes,
  ) {
    final selected = routes
        .where(
          (r) => selectedCodes.isEmpty || selectedCodes.contains(r.routeCode),
        )
        .toList();
    if (selected.isEmpty) {
      return 'Select a route to view timetable';
    }
    final primary = selected.first;
    final orderedStops = [...primary.stops]
      ..sort((a, b) => a.order.compareTo(b.order));
    final stop = orderedStops.isEmpty ? null : orderedStops.first;
    final times = (stop?.timings ?? const <String>[])
        .where((t) => t.length >= 5)
        .map((t) => t.substring(0, 5))
        .toList();
    if (times.isEmpty) {
      return 'No published timetable for this route';
    }
    final preview = times.take(4).join(', ');
    final last = times.last;
    return '${stop?.name ?? 'First stop'}: $preview ... last $last (${times.length} trips)';
  }

  Future<void> setDefaultAlertDistance(double meters) async {
    await _prefs?.setDouble(_defaultAlertDistancePrefKey, meters);
    state = state.copyWith(defaultAlertDistanceMeters: meters);
  }

  Future<void> cancelStopAlert() async {
    if (state.activeAlert != null) {
      await _cancelPersistedAlertFor(state.activeAlert!);
    }
    final stillActive = await _alertRepository.getActiveAlerts();
    if (stillActive.isEmpty) {
      await ForegroundAlertService.stopIfRunning();
    } else {
      await ForegroundAlertService.reconcileWithStoredAlerts();
    }
    await _refreshBackgroundStatus();
    state = state.copyWith(
      clearActiveAlert: true,
      clearPreviewAlert: true,
      alertStatusMessage: 'Alert cancelled.',
      alertTriggered: false,
    );
  }

  Future<void> clearStoredAlerts() async {
    try {
      state = state.copyWith(lastAlertStorageOperation: 'clear');
      await _alertRepository.clearAlerts();
      await ForegroundAlertService.stopIfRunning();
      await _alertRepository.resetBackgroundStatus(
        lastResult: 'Alerts cleared',
      );
      await _refreshBackgroundStatus();
      state = state.copyWith(
        clearActiveAlert: true,
        clearPreviewAlert: true,
        alertStatusMessage: 'Stored alerts cleared.',
        clearNotificationError: true,
        lastAlertCreated: false,
        lastBackgroundRegistrationAttempted: false,
        lastBackgroundRegistrationSucceeded: false,
        clearLastAlertCreationError: true,
        storedAlertsCount: 0,
        activeStoredAlertsCount: 0,
        triggeredStoredAlertsCount: 0,
        cancelledStoredAlertsCount: 0,
        lastAlertStorageOperation: 'clear_success',
      );
    } catch (e, st) {
      DebugLog.info('clearStoredAlerts failed: $e');
      DebugLog.info('clearStoredAlerts stack: $st');
      state = state.copyWith(
        notificationError: 'Could not clear stored alerts.',
        lastAlertCreationError: '${e.runtimeType}: $e',
        lastAlertStorageOperation: 'clear_failed',
      );
    }
  }

  Future<void> testAlertStorage() async {
    final now = DateTime.now();
    final id = 'storage_test_${now.microsecondsSinceEpoch}';
    final alert = PersistedBusAlert(
      id: id,
      routeId: 'test_route_id',
      routeCode: 'R_TEST',
      routeLabel: 'R_TEST',
      stopId: 'test_stop_id',
      stopCode: 'TEST001',
      stopName: 'Storage Test Stop',
      stopPoint: const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
      distanceThresholdMeters: 200,
      enabled: true,
      triggered: false,
      createdAt: now,
      notificationId: now.millisecondsSinceEpoch.remainder(2147483647),
      areaId: state.selectedAreaCode,
      liveApiRouteParam: 'R_TEST',
    );
    try {
      state = state.copyWith(
        lastAlertStorageOperation: 'self_test_save',
        clearAlertStorageSelfTestMessage: true,
      );
      await _alertRepository.saveAlert(alert);
      final all = await _alertRepository.getAlerts();
      if (!all.any((a) => a.id == id)) {
        throw StateError('Self-test save/read verification failed');
      }
      state = state.copyWith(lastAlertStorageOperation: 'self_test_delete');
      await _alertRepository.cancelAlert(id);
      final active = await _alertRepository.getActiveAlerts();
      if (active.any((a) => a.id == id)) {
        throw StateError('Self-test cleanup failed');
      }
      state = state.copyWith(
        alertStorageSelfTestPassed: true,
        alertStorageSelfTestMessage: 'Storage self-test passed.',
        storedAlertsCount: active.length,
        lastAlertStorageOperation: 'self_test_success',
      );
    } catch (e, st) {
      DebugLog.info('testAlertStorage failed: $e');
      DebugLog.info('testAlertStorage stack: $st');
      state = state.copyWith(
        alertStorageSelfTestPassed: false,
        alertStorageSelfTestMessage: '${e.runtimeType}: $e',
        lastAlertCreationError: '${e.runtimeType}: $e',
        lastAlertStorageOperation: 'self_test_failed',
      );
    }
  }

  void previewStopAlert({
    required BusRoute route,
    required BusStop stop,
    required double thresholdMeters,
  }) {
    state = state.copyWith(
      alertDraftRouteCode: route.routeCode,
      alertDraftStopName: stop.name,
      alertDraftDistanceMeters: thresholdMeters,
      previewAlert: StopAlert(
        routeCode: route.routeCode,
        routeLabel: route.routeNumber.isEmpty
            ? route.routeCode
            : route.routeNumber,
        stopCode: stop.code,
        stopName: stop.name,
        stopPoint: stop.point,
        distanceThresholdMeters: thresholdMeters,
        armedAt: null,
      ),
    );
  }

  void clearPreviewStopAlert() {
    state = state.copyWith(
      clearPreviewAlert: true,
      clearAlertDraftRouteCode: true,
      clearAlertDraftStopName: true,
      clearAlertDraftDistanceMeters: true,
    );
  }

  Future<void> toggleUserLocation() async {
    if (state.showUserLocation) {
      state = state.copyWith(
        showUserLocation: false,
        clearLocationMessage: true,
      );
      return;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = state.copyWith(
        locationMessage: 'Enable location services to use this feature.',
      );
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      state = state.copyWith(
        locationMessage: 'Location permission was denied.',
      );
      return;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    state = state.copyWith(
      showUserLocation: true,
      userLocation: LatLng(p.latitude, p.longitude),
      clearLocationMessage: true,
    );
  }

  Future<void> _initNotifications() async {
    if (_notificationInitDone) return;
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
        _notificationChannelId,
        _notificationChannelName,
        description: _notificationChannelDescription,
        importance: Importance.max,
      ),
    );
    _notificationInitDone = true;
    state = state.copyWith(notificationChannelReady: true);
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    await _initNotifications();
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await _refreshNotificationPermissionStatus();
  }

  Future<void> _refreshNotificationPermissionStatus() async {
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await androidImpl?.areNotificationsEnabled();
    state = state.copyWith(notificationPermissionGranted: enabled);
  }

  Future<void> _restoreAlert() async {
    try {
      final activeAlerts = await _alertRepository.getActiveAlerts();
      if (activeAlerts.isEmpty) return;
      final backgroundDisabled = await _alertRepository
          .getAlertBackgroundDisabled();
      final first = activeAlerts.first;
      state = state.copyWith(
        activeAlert: first.toStopAlert(),
        backgroundActiveAlertsCount: activeAlerts.length,
        alertStatusMessage: backgroundDisabled
            ? 'Background monitoring unavailable.'
            : 'Background monitoring active.',
      );
      final started = await ForegroundAlertService.ensureRunning();
      if (started && backgroundDisabled) {
        await _alertRepository.setAlertBackgroundDisabled(false);
      }
      await _refreshBackgroundStatus();
      state = state.copyWith(
        lastServiceStartAttempted: true,
        lastServiceStartSucceeded: started,
        alertStatusMessage: started
            ? 'Background monitoring active.'
            : 'Background monitoring unavailable.',
      );
    } catch (e, st) {
      DebugLog.info('restoreAlert failed safely: $e');
      DebugLog.info('restoreAlert stack: $st');
      state = state.copyWith(
        clearActiveAlert: true,
        backgroundActiveAlertsCount: 0,
        notificationError: 'Stored alert data was reset due to an error.',
      );
      await _alertRepository.clearAlerts();
    }
  }

  Future<void> _evaluateAlert(List<BusLocation> buses) async {
    final alert = state.activeAlert;
    if (alert == null) return;
    final now = DateTime.now();
    if (_isEvaluatingAlert ||
        now.difference(_lastAlertCheckThrottleAt) <
            const Duration(seconds: 2)) {
      return;
    }
    _isEvaluatingAlert = true;
    _lastAlertCheckThrottleAt = now;
    try {
      final evaluation = _alertEvaluationService.evaluateAlerts(
        activeAlerts: [alert],
        liveBuses: buses,
      );
      final result = evaluation.first;
      state = state.copyWith(
        lastAlertCheckAt: now,
        lastNearestBusDistanceMeters: result.nearestBusDistanceMeters,
        lastAlertRouteBusCount: result.matchedRouteBusCount,
        alertStatusMessage: result.matchedRouteBusCount == 0
            ? 'Alert enabled. Waiting for buses on route ${alert.routeCode}.'
            : (result.nearestBusDistanceMeters == null
                  ? 'Alert enabled. Waiting for live bus data.'
                  : 'Nearest bus: ${result.nearestBusDistanceMeters!.toStringAsFixed(0)} m'),
      );
      if (!result.isTriggered || result.nearestBus == null) return;

      final bus = result.nearestBus!;
      DebugLog.info(
        'alert condition met: route=${alert.routeCode}, threshold=${alert.distanceThresholdMeters}',
      );
      await _initNotifications();
      await _refreshNotificationPermissionStatus();
      final notificationsAllowed = state.notificationPermissionGranted ?? true;
      if (!notificationsAllowed) {
        state = state.copyWith(
          notificationError:
              'Notification permission is disabled. Enable notifications and try again.',
        );
        return;
      }
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
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
      await _markPersistedAlertTriggered(
        alert,
        result.nearestBusDistanceMeters,
      );
      final stillActive = await _alertRepository.getActiveAlerts();
      if (stillActive.isEmpty) {
        await ForegroundAlertService.stopIfRunning();
      }
      await _refreshBackgroundStatus();
      state = state.copyWith(
        clearActiveAlert: true,
        clearPreviewAlert: true,
        alertTriggered: true,
        lastAlertTriggeredAt: DateTime.now(),
        alertStatusMessage: 'Alert triggered.',
      );
    } catch (e) {
      state = state.copyWith(notificationError: 'Alert check failed: $e');
    } finally {
      _isEvaluatingAlert = false;
    }
  }

  Future<void> runAlertCheckNow() async {
    final activeBefore = await _alertRepository.getActiveAlerts();
    if (activeBefore.isEmpty) {
      await _refreshBackgroundStatus();
      state = state.copyWith(
        alertStatusMessage: 'No active alerts.',
        clearNotificationError: true,
      );
      return;
    }
    final result = await _backgroundCheckService.runOnce(
      source: 'debug_button',
    );
    await _refreshBackgroundStatus();
    if (result.error != null) {
      state = state.copyWith(notificationError: result.error);
      return;
    }
    final activeAlerts = await _alertRepository.getActiveAlerts();
    state = state.copyWith(
      activeAlert: activeAlerts.isEmpty
          ? null
          : activeAlerts.first.toStopAlert(),
      clearActiveAlert: activeAlerts.isEmpty,
      lastAlertCheckAt: result.checkedAt,
      lastNearestBusDistanceMeters: result.lastNearestBusDistanceMeters,
      lastAlertRouteBusCount: result.routeBusesCount,
      alertStatusMessage:
          'Manual check completed. Triggered ${result.triggeredAlertsCount} alert(s).',
      alertTriggered: result.triggeredAlertsCount > 0,
      lastAlertTriggeredAt: result.triggeredAlertsCount > 0
          ? DateTime.now()
          : state.lastAlertTriggeredAt,
    );
  }

  Future<void> sendTestNotification() async {
    try {
      await _requestNotificationPermissionIfNeeded();
      await _initNotifications();
      await _refreshNotificationPermissionStatus();
      final notificationsAllowed = state.notificationPermissionGranted ?? true;
      if (!notificationsAllowed) {
        state = state.copyWith(
          notificationError:
              'Notification permission is disabled. Allow notifications to receive alerts.',
        );
        return;
      }
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        'RTL Bus Tracker Test',
        'Test notification sent successfully.',
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
      state = state.copyWith(
        clearNotificationError: true,
        alertStatusMessage: 'Test notification sent.',
      );
    } catch (e) {
      state = state.copyWith(notificationError: 'Test notification failed: $e');
    }
  }

  Future<void> startAlertServiceForDebug() async {
    var started = false;
    try {
      await _alertRepository.setAlertBackgroundDisabled(false);
      started = await ForegroundAlertService.ensureRunning();
      state = state.copyWith(
        lastServiceStartAttempted: true,
        lastServiceStartSucceeded: started,
        lastBackgroundRegistrationAttempted: true,
        lastBackgroundRegistrationSucceeded: started,
      );
    } catch (e) {
      state = state.copyWith(
        lastBackgroundError: '$e',
        lastServiceStartAttempted: true,
        lastServiceStartSucceeded: false,
        lastBackgroundRegistrationAttempted: true,
        lastBackgroundRegistrationSucceeded: false,
      );
    } finally {
      await _refreshBackgroundStatus();
    }
  }

  Future<void> stopAlertServiceForDebug() async {
    var stopped = false;
    try {
      await ForegroundAlertService.stopIfRunning();
      stopped = true;
      state = state.copyWith(
        lastServiceStopAttempted: true,
        lastServiceStopSucceeded: true,
      );
    } catch (e) {
      state = state.copyWith(
        lastBackgroundError: '$e',
        lastServiceStopAttempted: true,
        lastServiceStopSucceeded: false,
      );
    } finally {
      if (!stopped) {
        state = state.copyWith(
          lastServiceStopAttempted: true,
          lastServiceStopSucceeded: false,
        );
      }
      await _refreshBackgroundStatus();
    }
  }

  Future<void> _refreshBackgroundStatus() async {
    final status = await _alertRepository.getStatus();
    final storedAlerts = await _alertRepository.getAlerts();
    final running = await ForegroundAlertService.isRunning();
    final backgroundDisabled = await _alertRepository
        .getAlertBackgroundDisabled();
    state = state.copyWith(
      backgroundCheckingMethod: 'Foreground service',
      backgroundWorkerRegistered: running,
      lastBackgroundCheckAt: status.lastCheckAt,
      lastBackgroundCheckResult: status.lastResult,
      lastBackgroundError: status.lastError,
      backgroundActiveAlertsCount: status.activeAlertsCount,
      storedAlertsCount: storedAlerts.length,
      activeStoredAlertsCount: storedAlerts
          .where((a) => a.enabled && !a.triggered)
          .length,
      triggeredStoredAlertsCount: storedAlerts.where((a) => a.triggered).length,
      cancelledStoredAlertsCount: storedAlerts
          .where((a) => !a.enabled && !a.triggered)
          .length,
      alertBackgroundDisabled: backgroundDisabled,
      foregroundServiceSupported: true,
    );
  }

  Future<void> resetAlertSystem() async {
    await ForegroundAlertService.stopIfRunning();
    await _alertRepository.clearAlerts();
    await _alertRepository.setAlertBackgroundDisabled(false);
    await _alertRepository.resetBackgroundStatus(
      lastResult: 'Alert system reset',
    );
    await _refreshBackgroundStatus();
    state = state.copyWith(
      clearActiveAlert: true,
      clearPreviewAlert: true,
      clearNotificationError: true,
      clearLastBackgroundError: true,
      clearLastBackgroundCheckResult: true,
      lastAlertCreated: false,
      lastBackgroundRegistrationAttempted: false,
      lastBackgroundRegistrationSucceeded: false,
      alertStatusMessage: 'Alert system reset.',
      alertTriggered: false,
      storedAlertsCount: 0,
      activeStoredAlertsCount: 0,
      triggeredStoredAlertsCount: 0,
      cancelledStoredAlertsCount: 0,
      alertBackgroundDisabled: false,
      foregroundServiceSupported: true,
      lastServiceStartAttempted: false,
      lastServiceStartSucceeded: false,
      lastServiceStopAttempted: false,
      lastServiceStopSucceeded: false,
    );
  }

  Future<void> _cancelPersistedAlertFor(StopAlert alert) async {
    final alerts = await _alertRepository.getAlerts();
    final target = alerts.firstWhereOrNull(
      (a) =>
          a.routeCode == alert.routeCode &&
          a.stopCode == alert.stopCode &&
          a.enabled,
    );
    if (target == null) return;
    await _alertRepository.markAlertCancelled(target.id);
  }

  Future<void> _markPersistedAlertTriggered(
    StopAlert alert,
    double? nearestDistanceMeters,
  ) async {
    final alerts = await _alertRepository.getAlerts();
    final target = alerts.firstWhereOrNull(
      (a) =>
          a.routeCode == alert.routeCode &&
          a.stopCode == alert.stopCode &&
          a.enabled,
    );
    if (target == null) return;
    await _alertRepository.markAlertTriggered(
      target.id,
      lastCheckedAt: DateTime.now(),
      lastNearestBusDistanceMeters: nearestDistanceMeters,
    );
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<String> _friendlyStartupError(Object error) async {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Request timed out. No connection or emulator network unavailable.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown) {
        return 'No connection or emulator network unavailable.';
      }
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'Server denied access for some map/schedule requests.';
      }
      return 'Unable to refresh network data right now.';
    }

    if (error is FormatException || '$error'.toLowerCase().contains('json')) {
      return 'Local cache data is invalid. Clear cache and retry.';
    }

    if ('$error'.toLowerCase().contains('database') ||
        '$error'.toLowerCase().contains('sqflite')) {
      return 'Local database failed to initialize. Clear cache and retry.';
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      return 'No connection or emulator network unavailable.';
    }
    return 'Unable to refresh from network';
  }
}
