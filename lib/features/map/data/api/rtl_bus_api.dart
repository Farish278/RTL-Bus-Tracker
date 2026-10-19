import 'dart:async';
import 'package:dio/dio.dart';
import '../../../../core/network/request_scheduler.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/text_sanitizer.dart';
import '../../domain/entities/models.dart';

class RtlBusApi {
  RtlBusApi(this._client);
  final DioClient _client;

  Dio get _dio => _client.dio;

  Future<List<BusRoute>> fetchRoutes({CancelToken? cancelToken}) async {
    final r = await _request(
      '/booking/v2/bus/routedetails',
      cancelToken: cancelToken,
    );
    final male = (r.data['routeResponse'] as List? ?? <dynamic>[])
        .map((e) => _toRoute(e, AreaType.greaterMale))
        .toList();
    final atollGroups = (r.data['atollRouteResponse'] as List? ?? <dynamic>[]);
    final atoll = <BusRoute>[];
    for (final group in atollGroups) {
      final groupRoutes = (group['routeResponse'] as List? ?? <dynamic>[]).map(
        (e) => _toRoute(e, AreaType.atoll),
      );
      atoll.addAll(groupRoutes);
    }
    return [...male, ...atoll];
  }

  BusRoute _toRoute(dynamic e, AreaType type) {
    final stopsRaw = (e['busRouteStopList'] as List? ?? <dynamic>[]);
    final stops = stopsRaw.map((s) {
      final timings = (s['timings'] as List? ?? <dynamic>[])
          .map((t) => '${t['timing'] ?? ''}'.trim())
          .where((t) => t.isNotEmpty && t != 'null')
          .toList();
      return BusStop(
        id: '${s['id']}',
        code: '${s['code'] ?? ''}',
        name: '${s['name'] ?? 'Unknown'}',
        order: (s['order'] as num?)?.toInt() ?? 0,
        point: LatLng(
          double.tryParse('${s['latitude']}') ?? 0,
          double.tryParse('${s['longitude']}') ?? 0,
        ),
        timings: timings,
      );
    }).toList();
    return BusRoute(
      id: '${e['id']}',
      routeCode: '${e['code'] ?? ''}',
      routeNumber: '${e['routeNumber'] ?? ''}',
      name: '${e['name'] ?? ''}',
      areaCode: '${e['depotCode'] ?? ''}',
      areaName: '${e['depotName'] ?? ''}',
      areaType: type,
      colorHex: '${e['color'] ?? '#E9222A'}',
      stops: stops,
      startStationName: e['startStationName'] == null
          ? null
          : '${e['startStationName']}',
      endStationName: e['endStationName'] == null
          ? null
          : '${e['endStationName']}',
      fare: (e['fare'] as num?)?.toDouble(),
      isMiniBusRoute: e['isMiniBusRoute'] == null
          ? null
          : e['isMiniBusRoute'] == 1,
    );
  }

  Future<RouteGeometry> fetchGeometry(
    String routeCode, {
    CancelToken? cancelToken,
  }) async {
    final r = await _request(
      '/booking/v2/bus/roadshape',
      data: {'routeCode': routeCode},
      cancelToken: cancelToken,
    );
    final raw = r.data['roadShape'];
    final features = (raw?['features'] as List? ?? <dynamic>[]);
    final points = <LatLng>[];
    for (final feature in features) {
      final coords = feature['geometry']?['coordinates'];
      if (coords is List) {
        for (final lines in coords) {
          if (lines is List) {
            for (final p in lines) {
              if (p is List && p.length >= 2) {
                points.add(
                  LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
                );
              }
            }
          }
        }
      }
    }
    return RouteGeometry(routeCode: routeCode, points: points);
  }

  Future<List<BusLocation>> fetchLiveCoordinates(
    String routeCode, {
    CancelToken? cancelToken,
  }) async {
    final r = await _request(
      '/booking/v1/bus/livecoordinates',
      priority: 0,
      data: {'routeCode': routeCode},
      cancelToken: cancelToken,
    );
    final list = (r.data['busList'] as List? ?? <dynamic>[]);
    final buses = list
        .map(
          (e) => BusLocation(
            routeCode: routeCode,
            busCode: '${e['busCode'] ?? ''}',
            plateNumber: '${e['plateNumber'] ?? ''}',
            point: LatLng(
              (e['latitude'] as num?)?.toDouble() ?? 0,
              (e['longitude'] as num?)?.toDouble() ?? 0,
            ),
            heading: _asDouble(e['heading']) ?? _asDouble(e['bearing']),
            direction: _asText(e['direction']),
            destination: _asText(e['destination']),
            nextStop: _asText(e['nextStop']),
            tripDirection:
                _asText(e['tripDirection']) ?? _asText(e['inboundOutbound']),
          ),
        )
        .toList();

    return buses;
  }

  bool needsEnrichment(List<BusLocation> buses) => buses.any(
    (bus) =>
        bus.heading == null ||
        bus.direction == null ||
        bus.destination == null ||
        bus.nextStop == null ||
        bus.tripDirection == null,
  );

  Future<List<BusLocation>> fetchLive(
    String routeCode, {
    CancelToken? cancelToken,
  }) async {
    final coordinates = await fetchLiveCoordinates(
      routeCode,
      cancelToken: cancelToken,
    );
    return enrichLive(routeCode, coordinates, cancelToken: cancelToken);
  }

  Future<List<BusLocation>> enrichLive(
    String routeCode,
    List<BusLocation> v1, {
    CancelToken? cancelToken,
  }) async {
    if (!needsEnrichment(v1)) return v1;
    try {
      final v3 = await _request(
        '/booking/v3/bus/livedata',
        priority: 2,
        data: {'routeCode': routeCode},
        cancelToken: cancelToken,
      );
      final raw = (v3.data['busList'] as List? ?? <dynamic>[]);
      if (raw.isEmpty) return v1;
      final extras = <String, dynamic>{};
      for (final e in raw) {
        final key = '${e['busCode'] ?? e['plateNumber'] ?? ''}';
        if (key.isNotEmpty) extras[key] = e;
      }
      return v1.map((bus) {
        final extra =
            extras[bus.busCode.isNotEmpty ? bus.busCode : bus.plateNumber];
        if (extra == null) return bus;
        return BusLocation(
          routeCode: bus.routeCode,
          busCode: bus.busCode,
          plateNumber: bus.plateNumber,
          point: bus.point,
          heading:
              bus.heading ??
              _asDouble(extra['heading']) ??
              _asDouble(extra['bearing']),
          direction: bus.direction ?? _asText(extra['direction']),
          destination: bus.destination ?? _asText(extra['destination']),
          nextStop:
              bus.nextStop ??
              _asText(extra['nextStop']) ??
              _asText(extra['nextStopName']),
          tripDirection:
              bus.tripDirection ??
              _asText(extra['tripDirection']) ??
              _asText(extra['inboundOutbound']),
        );
      }).toList();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return v1;
    } catch (_) {
      return v1;
    }
  }

  Future<Map<String, List<StopEta>>> fetchStopEtas(
    String routeCode, {
    CancelToken? cancelToken,
  }) async {
    final r = await _request(
      '/gps-engine/eta/all-stops-of-route',
      data: {'routeCode': routeCode},
      cancelToken: cancelToken,
    );
    final out = <String, List<StopEta>>{};
    _parseEtaList(out, routeCode, 'inbound', r.data['inboundStopsETAList']);
    _parseEtaList(out, routeCode, 'outbound', r.data['outboundStopsETAList']);
    return out;
  }

  void _parseEtaList(
    Map<String, List<StopEta>> out,
    String routeCode,
    String direction,
    dynamic rawList,
  ) {
    final list = (rawList as List? ?? <dynamic>[]);
    for (final e in list) {
      final stopCode =
          _asText(e['stopCode']) ??
          _asText(e['busStopCode']) ??
          _asText(e['code']) ??
          '';
      if (stopCode.isEmpty) continue;
      final etaLabel =
          _asText(e['eta']) ??
          _asText(e['etaText']) ??
          _asText(e['arrivalTime']) ??
          _asText(e['nextArrival']) ??
          '';
      if (etaLabel.isEmpty) continue;
      out
          .putIfAbsent(stopCode, () => <StopEta>[])
          .add(
            StopEta(
              stopCode: stopCode,
              direction: direction,
              timeLabel: etaLabel,
              busCode: _asText(e['busCode']),
              plateNumber: _asText(e['plateNumber']),
            ),
          );
    }
  }

  Future<Response<dynamic>> _request(
    String path, {
    Object? data,
    CancelToken? cancelToken,
    int priority = 1,
  }) {
    return RequestScheduler.shared.run(
      () => _dio.request<dynamic>(
        path,
        data: data,
        cancelToken: cancelToken,
        options: Options(method: data == null ? 'GET' : 'POST'),
      ),
      priority: priority,
      cancelToken: cancelToken,
    );
  }

  String? _asText(dynamic v) {
    final s = '$v'.trim();
    if (s.isEmpty || s == 'null') return null;
    return sanitizeNullableUiText(s);
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}
