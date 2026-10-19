import 'dart:async';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:rtl_bus_tracker/core/network/dio_client.dart';
import 'package:rtl_bus_tracker/features/map/data/api/rtl_bus_api.dart';
import 'package:rtl_bus_tracker/features/map/data/db/cache_store.dart';
import 'package:rtl_bus_tracker/features/map/domain/entities/models.dart';

final sampleRoute = BusRoute(
  id: '1',
  routeCode: 'R1',
  routeNumber: '1',
  name: 'Route',
  areaCode: '101',
  areaName: 'Male',
  areaType: AreaType.greaterMale,
  colorHex: '#ff0000',
  stops: [
    const BusStop(
      id: 'S1',
      code: 'S1',
      name: 'Stop',
      order: 1,
      point: LatLng(4.1755, 73.5093),
      timings: ['08:00'],
    ),
  ],
);
BusLocation bus(String code) => BusLocation(
  routeCode: code,
  busCode: 'B1',
  plateNumber: 'P1',
  point: const LatLng(4.1755, 73.5093),
);

class MemoryCache implements CacheStore {
  final values = <String, Map<String, dynamic>>{};
  bool failWrites = false;
  int reads = 0;
  @override
  Future<Map<String, dynamic>?> get(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> put(String key, Object value) async {
    if (failWrites) throw StateError('Disk full');
    values[key] = {
      'value': value,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> clear() async => values.clear();
}

class FakeApi extends RtlBusApi {
  FakeApi() : super(DioClient());
  int routeCalls = 0,
      geometryCalls = 0,
      etaCalls = 0,
      coordinateCalls = 0,
      enrichCalls = 0;
  List<BusRoute> routes = [sampleRoute];
  Future<void> Function()? routeWait;
  Future<List<BusLocation>> Function(String, CancelToken?)? coordinates;
  Future<List<BusLocation>> Function(String, List<BusLocation>, CancelToken?)?
  enrichment;
  Future<void> Function(String)? geometryWait;
  bool enrich = false;
  final tokens = <CancelToken>[];
  @override
  Future<List<BusRoute>> fetchRoutes({CancelToken? cancelToken}) async {
    routeCalls++;
    await routeWait?.call();
    return routes;
  }

  @override
  Future<RouteGeometry> fetchGeometry(
    String code, {
    CancelToken? cancelToken,
  }) async {
    geometryCalls++;
    await geometryWait?.call(code);
    return RouteGeometry(routeCode: code, points: const [LatLng(4, 73)]);
  }

  @override
  Future<Map<String, List<StopEta>>> fetchStopEtas(
    String code, {
    CancelToken? cancelToken,
  }) async {
    etaCalls++;
    return {
      'S1': [
        const StopEta(stopCode: 'S1', direction: 'inbound', timeLabel: '5 min'),
      ],
    };
  }

  @override
  Future<List<BusLocation>> fetchLiveCoordinates(
    String code, {
    CancelToken? cancelToken,
  }) async {
    coordinateCalls++;
    if (cancelToken != null) tokens.add(cancelToken);
    return coordinates == null ? [bus(code)] : coordinates!(code, cancelToken);
  }

  @override
  bool needsEnrichment(List<BusLocation> buses) => enrich && buses.isNotEmpty;
  @override
  Future<List<BusLocation>> enrichLive(
    String code,
    List<BusLocation> buses, {
    CancelToken? cancelToken,
  }) async {
    enrichCalls++;
    return enrichment == null ? buses : enrichment!(code, buses, cancelToken);
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
