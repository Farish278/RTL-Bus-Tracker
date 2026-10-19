import 'package:latlong2/latlong.dart';

enum AreaType { greaterMale, atoll }

class BusArea {
  const BusArea({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
  });
  final String id;
  final String code;
  final String name;
  final AreaType type;
}

class BusStop {
  const BusStop({
    required this.id,
    required this.code,
    required this.name,
    required this.order,
    required this.point,
    this.timings = const [],
  });
  final String id;
  final String code;
  final String name;
  final int order;
  final LatLng point;
  final List<String> timings;
}

class BusRoute {
  const BusRoute({
    required this.id,
    required this.routeCode,
    required this.routeNumber,
    required this.name,
    required this.areaCode,
    required this.areaName,
    required this.areaType,
    required this.colorHex,
    required this.stops,
    this.startStationName,
    this.endStationName,
    this.fare,
    this.isMiniBusRoute,
  });
  final String id;
  final String routeCode;
  final String routeNumber;
  final String name;
  final String areaCode;
  final String areaName;
  final AreaType areaType;
  final String colorHex;
  final List<BusStop> stops;
  final String? startStationName;
  final String? endStationName;
  final double? fare;
  final bool? isMiniBusRoute;
}

class RouteGeometry {
  const RouteGeometry({required this.routeCode, required this.points});
  final String routeCode;
  final List<LatLng> points;
}

class BusLocation {
  const BusLocation({
    required this.routeCode,
    required this.busCode,
    required this.plateNumber,
    required this.point,
    this.heading,
    this.direction,
    this.destination,
    this.nextStop,
    this.tripDirection,
  });
  final String routeCode;
  final String busCode;
  final String plateNumber;
  final LatLng point;
  final double? heading;
  final String? direction;
  final String? destination;
  final String? nextStop;
  final String? tripDirection;
  Map<String, dynamic> toJson() => {
    'routeCode': routeCode,
    'busCode': busCode,
    'plateNumber': plateNumber,
    'lat': point.latitude,
    'lng': point.longitude,
    'heading': heading,
    'direction': direction,
    'destination': destination,
    'nextStop': nextStop,
    'tripDirection': tripDirection,
  };
  factory BusLocation.fromJson(Map<String, dynamic> json) => BusLocation(
    routeCode: json['routeCode'] as String,
    busCode: json['busCode'] as String,
    plateNumber: json['plateNumber'] as String,
    point: LatLng(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
    ),
    heading: (json['heading'] as num?)?.toDouble(),
    direction: json['direction'] as String?,
    destination: json['destination'] as String?,
    nextStop: json['nextStop'] as String?,
    tripDirection: json['tripDirection'] as String?,
  );
}

class StopEta {
  const StopEta({
    required this.stopCode,
    required this.direction,
    required this.timeLabel,
    this.busCode,
    this.plateNumber,
  });

  final String stopCode;
  final String direction;
  final String timeLabel;
  final String? busCode;
  final String? plateNumber;
}

class RouteSchedule {
  const RouteSchedule({
    required this.routeId,
    required this.routeCode,
    required this.routeNumber,
    required this.routeName,
    required this.stops,
    required this.lastUpdated,
    required this.source,
    this.startStationName,
    this.endStationName,
    this.isRouteLevel = false,
  });

  final String routeId;
  final String routeCode;
  final String routeNumber;
  final String routeName;
  final List<StopSchedule> stops;
  final DateTime? lastUpdated;
  final String source;
  final String? startStationName;
  final String? endStationName;
  final bool isRouteLevel;
}

class StopSchedule {
  const StopSchedule({
    required this.stopId,
    required this.stopCode,
    required this.stopName,
    required this.entries,
  });

  final String stopId;
  final String stopCode;
  final String stopName;
  final List<ScheduleEntry> entries;
}

class ScheduleDirection {
  const ScheduleDirection({required this.id, required this.label});

  final String id;
  final String label;
}

class ScheduleEntry {
  const ScheduleEntry({
    required this.timeLabel,
    this.direction,
    this.serviceType,
  });

  final String timeLabel;
  final ScheduleDirection? direction;
  final String? serviceType;
}

class StopAlert {
  const StopAlert({
    required this.routeCode,
    required this.routeLabel,
    required this.stopCode,
    required this.stopName,
    required this.stopPoint,
    required this.distanceThresholdMeters,
    this.armedAt,
  });

  final String routeCode;
  final String routeLabel;
  final String stopCode;
  final String stopName;
  final LatLng stopPoint;
  final double distanceThresholdMeters;
  final DateTime? armedAt;
}
