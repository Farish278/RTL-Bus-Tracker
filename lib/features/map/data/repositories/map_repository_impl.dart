import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/debug_log.dart';
import '../../../../core/utils/text_sanitizer.dart';
import '../../domain/entities/models.dart';
import '../../domain/repositories/map_repository.dart';
import '../api/rtl_bus_api.dart';
import '../db/cache_db.dart';

class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl(this._api);
  final RtlBusApi _api;
  final _db = CacheDb.instance;
  static const _ttlMs = 7 * 24 * 60 * 60 * 1000;
  static const _etaTtlMs = 60 * 1000;
  List<BusRoute>? _routesMemory;
  final Map<String, Future<RouteSchedule?>> _inFlightScheduleRequests = {};

  @override
  Future<List<BusArea>> getAreas({bool forceRefresh = false}) async {
    final routes = await _getAllRoutes(forceRefresh: forceRefresh);
    final seen = <String>{};
    final areas = <BusArea>[];
    for (final route in routes) {
      if (route.areaCode.isEmpty || seen.contains(route.areaCode)) continue;
      seen.add(route.areaCode);
      areas.add(
        BusArea(
          id: route.areaCode,
          code: route.areaCode,
          name: route.areaName,
          type: route.areaType,
        ),
      );
    }
    areas.sort((a, b) {
      if (a.type != b.type) {
        return a.type == AreaType.greaterMale ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return areas;
  }

  @override
  Future<List<BusRoute>> getRoutes(
    String areaCode, {
    bool forceRefresh = false,
  }) async {
    final all = await _getAllRoutes(forceRefresh: forceRefresh);
    return all
        .where((r) => areaCode.isEmpty || r.areaCode == areaCode)
        .toList();
  }

  Future<List<BusRoute>> _getAllRoutes({required bool forceRefresh}) async {
    final sw = Stopwatch()..start();
    final cache = await _db.get('routes');
    final fresh =
        cache != null &&
        (DateTime.now().millisecondsSinceEpoch - (cache['updatedAt'] as int) <
            _ttlMs);
    if (!forceRefresh && fresh) {
      _routesMemory ??= _decodeRoutes(cache['value']);
      sw.stop();
      DebugLog.throttled(
        'cache_routes_read',
        'routes cache hit fresh count=${_routesMemory!.length} took=${sw.elapsedMilliseconds}ms',
        interval: const Duration(seconds: 3),
      );
      return _routesMemory!;
    }
    if (!forceRefresh && cache != null) {
      unawaited(_refreshRoutes());
      _routesMemory ??= _decodeRoutes(cache['value']);
      sw.stop();
      DebugLog.throttled(
        'cache_routes_stale',
        'routes cache hit stale count=${_routesMemory!.length} took=${sw.elapsedMilliseconds}ms (refresh in background)',
        interval: const Duration(seconds: 3),
      );
      return _routesMemory!;
    }
    sw.stop();
    DebugLog.throttled(
      'cache_routes_miss',
      'routes cache miss force=$forceRefresh',
      interval: const Duration(seconds: 3),
    );
    return _refreshRoutes();
  }

  Future<List<BusRoute>> _refreshRoutes() async {
    final sw = Stopwatch()..start();
    final routes = await _api.fetchRoutes();
    await _db.put('routes', routes.map(_routeToJson).toList());
    _routesMemory = routes;
    sw.stop();
    DebugLog.throttled(
      'refresh_routes',
      'refreshRoutes count=${routes.length} took=${sw.elapsedMilliseconds}ms',
      interval: const Duration(seconds: 5),
    );
    return routes;
  }

  @override
  Future<List<RouteGeometry>> getRouteGeometry(
    List<String> routeCodes, {
    bool forceRefresh = false,
  }) async {
    final out = <RouteGeometry>[];
    for (final code in routeCodes) {
      final key = 'geometry:$code';
      final cache = await _db.get(key);
      final fresh =
          cache != null &&
          (DateTime.now().millisecondsSinceEpoch - (cache['updatedAt'] as int) <
              _ttlMs);
      if (!forceRefresh && cache != null) {
        out.add(_decodeGeometry(cache['value']));
        if (!fresh) {
          unawaited(_refreshGeometry(code));
        }
      } else {
        out.add(await _refreshGeometry(code));
      }
    }
    return out;
  }

  Future<RouteGeometry> _refreshGeometry(String code) async {
    final sw = Stopwatch()..start();
    final geo = await _api.fetchGeometry(code);
    await _db.put('geometry:$code', _geometryToJson(geo));
    sw.stop();
    DebugLog.throttled(
      'refresh_geo_$code',
      'refreshGeometry route=$code points=${geo.points.length} took=${sw.elapsedMilliseconds}ms',
      interval: const Duration(seconds: 10),
    );
    return geo;
  }

  @override
  Future<Map<String, List<StopEta>>> getStopEtasForRoutes(
    List<String> routeCodes,
  ) async {
    final merged = <String, List<StopEta>>{};
    for (final code in routeCodes) {
      final key = 'eta:$code';
      final cache = await _db.get(key);
      final fresh =
          cache != null &&
          (DateTime.now().millisecondsSinceEpoch - (cache['updatedAt'] as int) <
              _etaTtlMs);
      Map<String, List<StopEta>> current;
      if (cache != null) {
        current = _decodeEtas(cache['value']);
        if (!fresh) {
          unawaited(_refreshEta(code));
        }
      } else {
        current = await _refreshEta(code);
      }
      for (final entry in current.entries) {
        merged.putIfAbsent(entry.key, () => <StopEta>[]).addAll(entry.value);
      }
    }
    return merged;
  }

  Future<Map<String, List<StopEta>>> _refreshEta(String code) async {
    final sw = Stopwatch()..start();
    final etas = await _api.fetchStopEtas(code);
    await _db.put('eta:$code', _etasToJson(etas));
    sw.stop();
    DebugLog.throttled(
      'refresh_eta_$code',
      'refreshEta route=$code stops=${etas.length} took=${sw.elapsedMilliseconds}ms',
      interval: const Duration(seconds: 10),
    );
    return etas;
  }

  @override
  Future<RouteSchedule?> getRouteSchedule(
    String routeCode, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _inFlightScheduleRequests.containsKey(routeCode)) {
      return _inFlightScheduleRequests[routeCode];
    }
    final request = _loadRouteSchedule(routeCode, forceRefresh: forceRefresh);
    _inFlightScheduleRequests[routeCode] = request;
    try {
      return await request;
    } finally {
      _inFlightScheduleRequests.remove(routeCode);
    }
  }

  Future<RouteSchedule?> _loadRouteSchedule(
    String routeCode, {
    required bool forceRefresh,
  }) async {
    // Avoid blocking UI on schedule refresh: this endpoint returns a large
    // all-routes payload, so we serve cached routes immediately and refresh
    // in the background when a force refresh is requested.
    final routes = await _getAllRoutes(forceRefresh: false);
    if (forceRefresh) {
      unawaited(_refreshRoutes());
    }
    final route = routes.where((r) => r.routeCode == routeCode).firstOrNull;
    if (route == null) return null;
    final cache = await _db.get('routes');
    final updatedAtMs = cache?['updatedAt'] as int?;
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
      lastUpdated: updatedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      source: '/booking/v2/bus/routedetails',
      startStationName: route.startStationName,
      endStationName: route.endStationName,
      isRouteLevel: !hasAnyStopTiming,
    );
  }

  @override
  Stream<List<BusLocation>> watchLiveBusLocations(
    List<String> routeCodes,
  ) async* {
    if (routeCodes.isEmpty) {
      yield const [];
      return;
    }
    while (true) {
      yield await getLiveBusLocations(routeCodes);
      await Future<void>.delayed(const Duration(seconds: 8));
    }
  }

  @override
  Future<List<BusLocation>> getLiveBusLocations(List<String> routeCodes) async {
    if (routeCodes.isEmpty) return const <BusLocation>[];
    final sw = Stopwatch()..start();
    final jobs = routeCodes.map((code) async {
      try {
        return await _api
            .fetchLive(code)
            .timeout(const Duration(seconds: 6), onTimeout: () => const []);
      } catch (_) {
        return const <BusLocation>[];
      }
    }).toList();
    final results = await Future.wait(jobs);
    final all = results.expand((x) => x).toList();
    sw.stop();
    DebugLog.throttled(
      'live_poll',
      'live poll routes=${routeCodes.length} buses=${all.length} took=${sw.elapsedMilliseconds}ms',
      interval: const Duration(seconds: 8),
    );
    return all;
  }

  @override
  Future<void> clearCache() => _db.clear();

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
