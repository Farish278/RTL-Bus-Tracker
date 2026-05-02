import 'package:latlong2/latlong.dart';

import '../entities/models.dart';

class AlertEvaluationResult {
  const AlertEvaluationResult({
    required this.alert,
    required this.matchedRouteBusCount,
    required this.nearestBusDistanceMeters,
    required this.nearestBus,
    required this.isTriggered,
  });

  final StopAlert alert;
  final int matchedRouteBusCount;
  final double? nearestBusDistanceMeters;
  final BusLocation? nearestBus;
  final bool isTriggered;
}

class AlertEvaluationService {
  AlertEvaluationService({Distance? distance})
    : _distance = distance ?? const Distance();

  final Distance _distance;

  List<AlertEvaluationResult> evaluateAlerts({
    required List<StopAlert> activeAlerts,
    required List<BusLocation> liveBuses,
  }) {
    return activeAlerts.map((alert) {
      final routeBuses = liveBuses
          .where(
            (bus) => _routeKey(bus.routeCode) == _routeKey(alert.routeCode),
          )
          .toList();

      double? nearestDistanceMeters;
      BusLocation? nearestBus;
      for (final bus in routeBuses) {
        final distance = _distance.as(
          LengthUnit.Meter,
          bus.point,
          alert.stopPoint,
        );
        if (nearestDistanceMeters == null || distance < nearestDistanceMeters) {
          nearestDistanceMeters = distance;
          nearestBus = bus;
        }
      }

      final threshold = alert.distanceThresholdMeters;
      final isTriggered =
          nearestDistanceMeters != null && nearestDistanceMeters <= threshold;

      return AlertEvaluationResult(
        alert: alert,
        matchedRouteBusCount: routeBuses.length,
        nearestBusDistanceMeters: nearestDistanceMeters,
        nearestBus: nearestBus,
        isTriggered: isTriggered,
      );
    }).toList();
  }

  String _routeKey(String routeCode) => routeCode.trim().toUpperCase();
}
