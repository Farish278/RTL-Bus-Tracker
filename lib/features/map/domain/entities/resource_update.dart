import 'models.dart';

class ResourceStatus {
  const ResourceStatus({this.fetchedAt, this.error, this.historical = false});
  final DateTime? fetchedAt;
  final String? error;
  final bool historical;
  bool get stale => historical || error != null;
}

class ResourceUpdate {
  const ResourceUpdate(this.key, this.value, this.status);
  final String key;
  final Object? value;
  final ResourceStatus status;
}

class LiveSnapshot {
  const LiveSnapshot({
    required this.routeCode,
    required this.buses,
    required this.fetchedAt,
    this.historical = false,
    this.error,
    this.metadataOnly = false,
  });
  final String routeCode;
  final List<BusLocation> buses;
  final DateTime fetchedAt;
  final bool historical;
  final String? error;
  final bool metadataOnly;
  ResourceStatus get status => ResourceStatus(
    fetchedAt: fetchedAt,
    error: error,
    historical: historical,
  );
  Map<String, dynamic> toJson() => {
    'routeCode': routeCode,
    'fetchedAt': fetchedAt.toIso8601String(),
    'historical': historical,
    'error': error,
    'metadataOnly': metadataOnly,
    'buses': buses.map((b) => b.toJson()).toList(),
  };
  factory LiveSnapshot.fromJson(
    Map<String, dynamic> json, {
    bool restored = false,
  }) => LiveSnapshot(
    routeCode: json['routeCode'] as String,
    buses: (json['buses'] as List)
        .map((b) => BusLocation.fromJson(Map<String, dynamic>.from(b)))
        .toList(),
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    historical: restored || json['historical'] == true,
    error: json['error'] as String?,
    metadataOnly: json['metadataOnly'] == true,
  );
}
