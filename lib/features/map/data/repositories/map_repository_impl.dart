import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/debug_log.dart';
import '../../../../core/utils/text_sanitizer.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/resource_update.dart';
import '../../domain/repositories/map_repository.dart';
import '../api/rtl_bus_api.dart';
import '../db/cache_db.dart';
import '../db/cache_store.dart';

class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl(
    this._api, {
    CacheStore? cache,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 8),
    this.jitter = true,
  }) : _db = cache ?? CacheDb.instance,
       _now = now ?? DateTime.now;
  final RtlBusApi _api;
  final CacheStore _db;
  final DateTime Function() _now;
  final Duration pollInterval;
  final bool jitter;
  static const _ttl = Duration(days: 7);
  static const _etaTtl = Duration(seconds: 60);
  final _events = StreamController<ResourceUpdate>.broadcast();
  final Map<String, Object> _memory = {};
  final Map<String, Future<Object>> _refreshes = {};
  final Map<String, Future<Object?>> _reads = {};
  final Map<String, CancelToken> _tokens = {};
  final Map<String, _LivePoll> _polls = {};
  final Map<String, LiveSnapshot> _live = {};
  final Map<String, _CoordinateFlight> _coordinates = {};
  final Map<String, DateTime> _coordinateRetryAt = {};
  final Map<String, int> _coordinateFailures = {};
  final Map<String, Object> _coordinateErrors = {};
  final Map<String, ResourceStatus> _statuses = {};
  final Map<String, DateTime> _retryAt = {};
  final Map<String, int> _failures = {};
  int _epoch = 0;
  bool _disposed = false;
  @override
  Stream<ResourceUpdate> get updates => _events.stream;
  @override
  Map<String, ResourceStatus> get resourceStatuses =>
      Map.unmodifiable(_statuses);

  void _publish(String key, Object? value, ResourceStatus status) {
    if (_disposed) return;
    _statuses[key] = status;
    _events.add(ResourceUpdate(key, value, status));
  }

  Future<void> _save(String key, Object value) async {
    try {
      await _db.put(key, value);
    } catch (error) {
      DebugLog.info('Cache write failed for $key: $error');
    }
  }

  Future<Object?> _cached<T extends Object>(
    String key,
    T Function(Object?) decode,
  ) {
    return _reads.putIfAbsent(key, () async {
      final epoch = _epoch;
      try {
        final cache = await _db.get(key);
        if (cache == null || epoch != _epoch || _disposed) return null;
        final decoded = decode(cache['value']);
        if (!_memory.containsKey(key)) {
          _memory[key] = decoded;
          _statuses[key] = ResourceStatus(
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(
              cache['updatedAt'] as int,
            ),
          );
        }
        return _memory[key];
      } catch (error) {
        DebugLog.info('Cache read failed for $key: $error');
        return null;
      } finally {
        _reads.remove(key);
      }
    });
  }

  Future<T> _load<T extends Object>(
    String key,
    Duration ttl,
    T Function(Object?) decode,
    Future<T> Function(CancelToken) fetch,
    Object Function(T) encode, {
    bool force = false,
  }) async {
    if (!force) {
      final cached = _memory[key] ?? await _cached(key, decode);
      if (cached != null) {
        final status = _statuses[key]!;
        if (status.fetchedAt == null ||
            _now().difference(status.fetchedAt!) >= ttl) {
          _statuses[key] = ResourceStatus(
            fetchedAt: status.fetchedAt,
            historical: true,
            error: status.error,
          );
          _background(_refresh<T>(key, fetch, encode));
        }
        return cached as T;
      }
    }
    return _refresh<T>(key, fetch, encode);
  }

  void _background(Future<Object?> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          DebugLog.info('Background refresh failed: $error');
        },
      ),
    );
  }

  Future<T> _refresh<T extends Object>(
    String key,
    Future<T> Function(CancelToken) fetch,
    Object Function(T) encode,
  ) async {
    if (_tokens[key]?.isCancelled ?? false) _refreshes.remove(key);
    if (_refreshes[key] case final existing?) return await existing as T;
    final retryAt = _retryAt[key];
    if (retryAt != null && _now().isBefore(retryAt)) {
      if (_memory[key] case final cached?) return cached as T;
      throw StateError('Waiting to retry $key');
    }
    final token = CancelToken();
    _tokens[key] = token;
    final epoch = _epoch;
    final request = () async {
      try {
        final value = await fetch(token);
        if (epoch == _epoch && !_disposed && !token.isCancelled) {
          _memory[key] = value;
          _retryAt.remove(key);
          _failures.remove(key);
          _publish(key, value, ResourceStatus(fetchedAt: _now()));
          await _save(key, encode(value));
        }
        return value;
      } catch (error) {
        if (!token.isCancelled && epoch == _epoch) {
          final failures = (_failures[key] ?? 0) + 1;
          _failures[key] = failures;
          _retryAt[key] = _now().add(retryDelay(failures, error));
          _publish(
            key,
            _memory[key],
            ResourceStatus(
              fetchedAt: _statuses[key]?.fetchedAt,
              error: '$error',
            ),
          );
        }
        rethrow;
      }
    }();
    _refreshes[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_refreshes[key], request)) {
        _refreshes.remove(key);
        _tokens.remove(key);
      }
    }
  }

  @override
  Future<List<BusArea>> getAreas({bool forceRefresh = false}) async {
    final routes = await _getAllRoutes(forceRefresh: forceRefresh);
    final seen = <String>{};
    final areas = <BusArea>[];
    for (final route in routes) {
      if (route.areaCode.isEmpty || !seen.add(route.areaCode)) continue;
      areas.add(
        BusArea(
          id: route.areaCode,
          code: route.areaCode,
          name: route.areaName,
          type: route.areaType,
        ),
      );
    }
    areas.sort(
      (a, b) => a.type != b.type
          ? (a.type == AreaType.greaterMale ? -1 : 1)
          : a.name.compareTo(b.name),
    );
    return areas;
  }

  @override
  Future<List<BusRoute>> getRoutes(
    String areaCode, {
    bool forceRefresh = false,
  }) async => (await _getAllRoutes(
    forceRefresh: forceRefresh,
  )).where((r) => areaCode.isEmpty || r.areaCode == areaCode).toList();
  Future<List<BusRoute>> _getAllRoutes({required bool forceRefresh}) => _load(
    'routes',
    _ttl,
    _decodeRoutes,
    (token) => _api.fetchRoutes(cancelToken: token),
    (routes) => routes.map(_routeToJson).toList(),
    force: forceRefresh,
  );
  @override
  Future<List<RouteGeometry>> getRouteGeometry(
    List<String> routeCodes, {
    bool forceRefresh = false,
  }) async {
    final values = await Future.wait(
      routeCodes.toSet().map((code) async {
        try {
          return await _load(
            'geometry:$code',
            _ttl,
            _decodeGeometry,
            (token) => _api.fetchGeometry(code, cancelToken: token),
            _geometryToJson,
            force: forceRefresh,
          );
        } catch (_) {
          return _memory['geometry:$code'] as RouteGeometry?;
        }
      }),
    );
    return values.whereType<RouteGeometry>().toList();
  }

  @override
  Future<Map<String, List<StopEta>>> getStopEtasForRoutes(
    List<String> routeCodes, {
    bool forceRefresh = false,
  }) async {
    final values = await Future.wait(
      routeCodes.toSet().map((code) async {
        try {
          return await _load(
            'eta:$code',
            _etaTtl,
            _decodeEtas,
            (token) => _api.fetchStopEtas(code, cancelToken: token),
            _etasToJson,
            force: forceRefresh,
          );
        } catch (_) {
          return _memory['eta:$code'] as Map<String, List<StopEta>>? ?? {};
        }
      }),
    );
    final merged = <String, List<StopEta>>{};
    for (final value in values) {
      for (final entry in value.entries) {
        merged.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    }
    return merged;
  }

  @override
  Future<RouteSchedule?> getRouteSchedule(
    String routeCode, {
    bool forceRefresh = false,
  }) async {
    final routes = await _getAllRoutes(forceRefresh: forceRefresh);
    final route = routes.where((r) => r.routeCode == routeCode).firstOrNull;
    if (route == null) return null;
    final stops = route.stops
        .map(
          (stop) => StopSchedule(
            stopId: stop.id,
            stopCode: stop.code,
            stopName: stop.name,
            entries: stop.timings
                .where((t) => t.trim().isNotEmpty)
                .map((t) => ScheduleEntry(timeLabel: t.trim()))
                .toList(),
          ),
        )
        .toList();
    final hasAnyStopTiming = stops.any((s) => s.entries.isNotEmpty);
    return RouteSchedule(
      routeId: route.id,
      routeCode: route.routeCode,
      routeNumber: route.routeNumber,
      routeName: route.name,
      stops: stops,
      lastUpdated: resourceStatuses['routes']?.fetchedAt,
      source: '/booking/v2/bus/routedetails',
      startStationName: route.startStationName,
      endStationName: route.endStationName,
      isRouteLevel: !hasAnyStopTiming,
    );
  }

  Future<List<BusLocation>> getCoordinatesForAlert(String code) async {
    final previous = _live[code];
    if (previous != null &&
        !previous.historical &&
        previous.error == null &&
        _now().difference(previous.fetchedAt) < pollInterval) {
      return previous.buses;
    }
    return _fetchCoordinates(code, CancelToken());
  }

  Future<List<BusLocation>> _fetchCoordinates(
    String code,
    CancelToken consumer,
  ) async {
    final retryAt = _coordinateRetryAt[code];
    if (retryAt != null && _now().isBefore(retryAt)) {
      throw _coordinateErrors[code]!;
    }
    var flight = _coordinates[code];
    if (flight == null || flight.token.isCancelled) {
      final token = CancelToken();
      flight = _CoordinateFlight(token);
      final current = flight;
      _coordinates[code] = current;
      current.future = () async {
        try {
          final buses = await _api.fetchLiveCoordinates(
            code,
            cancelToken: token,
          );
          _coordinateFailures.remove(code);
          _coordinateRetryAt.remove(code);
          _coordinateErrors.remove(code);
          return buses;
        } catch (error) {
          if (!token.isCancelled) {
            final failures = (_coordinateFailures[code] ?? 0) + 1;
            _coordinateFailures[code] = failures;
            _coordinateErrors[code] = error;
            _coordinateRetryAt[code] = _now().add(retryDelay(failures, error));
          }
          rethrow;
        } finally {
          current.finished = true;
          if (identical(_coordinates[code], current)) _coordinates.remove(code);
        }
      }();
    }
    flight.consumers++;
    try {
      if (consumer.isCancelled) throw consumer.cancelError!;
      return await Future.any([
        flight.future,
        consumer.whenCancel.then<List<BusLocation>>((error) => throw error),
      ]);
    } finally {
      flight.consumers--;
      if (flight.consumers == 0 && !flight.finished) {
        flight.token.cancel('No coordinate consumers');
      }
    }
  }

  void _emitLive(LiveSnapshot snapshot) {
    if (_disposed) return;
    _live[snapshot.routeCode] = snapshot;
    _publish('live:${snapshot.routeCode}', snapshot, snapshot.status);
  }

  @override
  Stream<LiveSnapshot> watchLiveSnapshots(List<String> routeCodes) {
    late StreamController<LiveSnapshot> output;
    final subscriptions = <StreamSubscription<LiveSnapshot>>[];
    output = StreamController<LiveSnapshot>(
      onListen: () {
        for (final code in routeCodes.toSet()) {
          final poll = _polls.putIfAbsent(code, () => _LivePoll(this, code));
          subscriptions.add(
            poll.stream.listen(output.add, onError: output.addError),
          );
        }
      },
      onCancel: () async {
        await Future.wait(subscriptions.map((s) => s.cancel()));
      },
    );
    return output.stream;
  }

  @override
  Stream<List<BusLocation>> watchLiveBusLocations(List<String> routeCodes) {
    final snapshots = <String, LiveSnapshot>{};
    return watchLiveSnapshots(routeCodes).map((snapshot) {
      snapshots[snapshot.routeCode] = snapshot;
      return snapshots.values.expand((s) => s.buses).toList();
    });
  }

  @override
  Future<List<BusLocation>> getLiveBusLocations(List<String> routeCodes) async {
    final values = await Future.wait(
      routeCodes.toSet().map((code) async {
        try {
          return await _api.fetchLive(code);
        } catch (_) {
          return _live[code]?.buses ?? <BusLocation>[];
        }
      }),
    );
    return values.expand((v) => v).toList();
  }

  Duration retryDelay(int failures, Object? error) {
    var seconds = math
        .min(60, 8 * math.pow(2, math.min(failures, 3)))
        .toDouble();
    if (jitter) seconds *= 1 + math.Random().nextDouble() * .15;
    var delay = Duration(milliseconds: (seconds * 1000).round());
    if (error is DioException) {
      final header = error.response?.headers.value('retry-after');
      final retrySeconds = int.tryParse(header ?? '');
      final date = header == null ? null : _httpDate(header);
      final serverDelay = retrySeconds != null
          ? Duration(seconds: retrySeconds)
          : date?.difference(_now());
      if (serverDelay != null && serverDelay > delay) delay = serverDelay;
    }
    return delay;
  }

  DateTime? _httpDate(String value) {
    final parts = value.replaceAll(',', '').split(' ');
    if (parts.length != 6 || parts.last != 'GMT') return null;
    final month =
        const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ].indexOf(parts[2]) +
        1;
    final time = parts[4].split(':');
    if (month == 0 || time.length != 3) return null;
    try {
      return DateTime.utc(
        int.parse(parts[3]),
        month,
        int.parse(parts[1]),
        int.parse(time[0]),
        int.parse(time[1]),
        int.parse(time[2]),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void cancelUnusedResources(Set<String> routeCodes) {
    for (final entry in _tokens.entries.toList()) {
      if ((entry.key.startsWith('geometry:') || entry.key.startsWith('eta:')) &&
          !routeCodes.contains(entry.key.split(':').last)) {
        entry.value.cancel('Resource no longer selected');
      }
    }
  }

  @override
  Future<void> clearCache() async {
    _epoch++;
    for (final token in _tokens.values) {
      token.cancel('Cache cleared');
    }
    _memory.clear();
    _reads.clear();
    _statuses.clear();
    _retryAt.clear();
    _failures.clear();
    _coordinateRetryAt.clear();
    _coordinateFailures.clear();
    _coordinateErrors.clear();
    _live.clear();
    _refreshes.clear();
    _tokens.clear();
    await _db.clear();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel('Repository disposed');
    }
    for (final flight in _coordinates.values.toList()) {
      flight.token.cancel('Repository disposed');
    }
    for (final poll in _polls.values.toList()) {
      await poll.close();
    }
    await _events.close();
  }

  List<BusRoute> _decodeRoutes(Object? value) {
    final list = (value as List? ?? <dynamic>[]);
    return list.map((e) => _routeFromJson(e)).toList();
  }

  Map<String, dynamic> _routeToJson(BusRoute r) => {
    'id': r.id,
    'routeCode': r.routeCode,
    'routeNumber': r.routeNumber,
    'name': r.name,
    'areaCode': r.areaCode,
    'areaName': r.areaName,
    'areaType': r.areaType.name,
    'colorHex': r.colorHex,
    'startStationName': r.startStationName,
    'endStationName': r.endStationName,
    'fare': r.fare,
    'isMiniBusRoute': r.isMiniBusRoute,
    'stops': r.stops
        .map(
          (s) => {
            'id': s.id,
            'code': s.code,
            'name': s.name,
            'order': s.order,
            'lat': s.point.latitude,
            'lng': s.point.longitude,
            'timings': s.timings,
          },
        )
        .toList(),
  };

  BusRoute _routeFromJson(dynamic j) => BusRoute(
    id: '${j['id']}',
    routeCode: '${j['routeCode']}',
    routeNumber: sanitizeUiText('${j['routeNumber']}'),
    name: sanitizeUiText('${j['name']}'),
    areaCode: '${j['areaCode']}',
    areaName: sanitizeUiText('${j['areaName']}'),
    areaType: '${j['areaType']}' == AreaType.atoll.name
        ? AreaType.atoll
        : AreaType.greaterMale,
    colorHex: '${j['colorHex']}',
    startStationName: j['startStationName'] == null
        ? null
        : sanitizeUiText('${j['startStationName']}'),
    endStationName: j['endStationName'] == null
        ? null
        : sanitizeUiText('${j['endStationName']}'),
    fare: (j['fare'] as num?)?.toDouble(),
    isMiniBusRoute: j['isMiniBusRoute'] as bool?,
    stops: (j['stops'] as List? ?? <dynamic>[])
        .map(
          (s) => BusStop(
            id: '${s['id']}',
            code: '${s['code']}',
            name: sanitizeUiText('${s['name']}'),
            order: (s['order'] as num).toInt(),
            point: LatLng(
              (s['lat'] as num).toDouble(),
              (s['lng'] as num).toDouble(),
            ),
            timings: (s['timings'] as List? ?? const <dynamic>[])
                .map((t) => sanitizeUiText('$t'))
                .where((t) => t.isNotEmpty)
                .toList(),
          ),
        )
        .toList(),
  );

  Map<String, dynamic> _geometryToJson(RouteGeometry g) => {
    'routeCode': g.routeCode,
    'points': g.points.map((e) => [e.latitude, e.longitude]).toList(),
  };

  RouteGeometry _decodeGeometry(Object? value) {
    final map = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
    final pointsRaw = (map['points'] as List? ?? <dynamic>[]);
    return RouteGeometry(
      routeCode: '${map['routeCode']}',
      points: pointsRaw
          .map(
            (e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()),
          )
          .toList(),
    );
  }

  Map<String, dynamic> _etasToJson(Map<String, List<StopEta>> etas) => {
    for (final entry in etas.entries)
      entry.key: entry.value
          .map(
            (e) => {
              'stopCode': e.stopCode,
              'direction': e.direction,
              'timeLabel': e.timeLabel,
              'busCode': e.busCode,
              'plateNumber': e.plateNumber,
            },
          )
          .toList(),
  };

  Map<String, List<StopEta>> _decodeEtas(Object? value) {
    final map = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
    final out = <String, List<StopEta>>{};
    for (final entry in map.entries) {
      final list = (entry.value as List? ?? <dynamic>[])
          .map(
            (e) => StopEta(
              stopCode: '${e['stopCode']}',
              direction: sanitizeUiText('${e['direction']}'),
              timeLabel: sanitizeUiText('${e['timeLabel']}'),
              busCode: e['busCode'] == null ? null : '${e['busCode']}',
              plateNumber: e['plateNumber'] == null
                  ? null
                  : '${e['plateNumber']}',
            ),
          )
          .toList();
      out[entry.key] = list;
    }
    return out;
  }
}

class _LivePoll {
  _LivePoll(this.repo, this.code) {
    _controller = StreamController<LiveSnapshot>.broadcast(
      onListen: _start,
      onCancel: close,
    );
  }
  final MapRepositoryImpl repo;
  final String code;
  late final StreamController<LiveSnapshot> _controller;
  Stream<LiveSnapshot> get stream => _controller.stream;
  final _token = CancelToken();
  Timer? _timer;
  bool _closed = false;
  int _failures = 0;
  void _add(LiveSnapshot snapshot) {
    if (_closed) return;
    repo._emitLive(snapshot);
    _controller.add(snapshot);
  }

  Future<void> _start() async {
    try {
      final cached = await repo._db.get('live:$code');
      if (!_closed && cached != null) {
        _add(
          LiveSnapshot.fromJson(
            Map<String, dynamic>.from(cached['value']),
            restored: true,
          ),
        );
      }
    } catch (error) {
      DebugLog.info('Live cache read failed: $error');
    }
    if (!_closed) await _tick();
  }

  Future<void> _tick() async {
    Object? failure;
    try {
      final coordinates = await repo._fetchCoordinates(code, _token);
      if (_closed) return;
      final at = repo._now();
      _failures = 0;
      var snapshot = LiveSnapshot(
        routeCode: code,
        buses: coordinates,
        fetchedAt: at,
      );
      _add(snapshot);
      repo._background(repo._save('live:$code', snapshot.toJson()));
      if (repo._api.needsEnrichment(coordinates)) {
        final enriched = await repo._api.enrichLive(
          code,
          coordinates,
          cancelToken: _token,
        );
        if (_closed) return;
        snapshot = LiveSnapshot(
          routeCode: code,
          buses: enriched,
          fetchedAt: at,
          metadataOnly: true,
        );
        _add(snapshot);
        repo._background(repo._save('live:$code', snapshot.toJson()));
      }
    } catch (error) {
      if (_closed) return;
      failure = error;
      _failures++;
      final previous = repo._live[code];
      _add(
        LiveSnapshot(
          routeCode: code,
          buses: previous?.buses ?? [],
          fetchedAt:
              previous?.fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          historical: true,
          error: '$error',
        ),
      );
    }
    if (!_closed) {
      _timer = Timer(
        failure == null
            ? repo.pollInterval
            : repo.retryDelay(_failures, failure),
        _tick,
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _token.cancel('No live consumers');
    if (identical(repo._polls[code], this)) repo._polls.remove(code);
    unawaited(_controller.close());
  }
}

class _CoordinateFlight {
  _CoordinateFlight(this.token);
  final CancelToken token;
  late final Future<List<BusLocation>> future;
  int consumers = 0;
  bool finished = false;
}
