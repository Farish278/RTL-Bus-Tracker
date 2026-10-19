import '../entities/models.dart';
import '../entities/resource_update.dart';

abstract class MapRepository {
  Stream<ResourceUpdate> get updates;
  Map<String, ResourceStatus> get resourceStatuses;
  Stream<LiveSnapshot> watchLiveSnapshots(List<String> routeCodes);
  void cancelUnusedResources(Set<String> routeCodes);
  Future<void> dispose();
  Future<List<BusArea>> getAreas({bool forceRefresh = false});
  Future<List<BusRoute>> getRoutes(
    String areaCode, {
    bool forceRefresh = false,
  });
  Future<List<RouteGeometry>> getRouteGeometry(
    List<String> routeCodes, {
    bool forceRefresh = false,
  });
  Future<Map<String, List<StopEta>>> getStopEtasForRoutes(
    List<String> routeCodes, {
    bool forceRefresh = false,
  });
  Future<RouteSchedule?> getRouteSchedule(
    String routeCode, {
    bool forceRefresh = false,
  });
  Future<List<BusLocation>> getLiveBusLocations(List<String> routeCodes);
  Stream<List<BusLocation>> watchLiveBusLocations(List<String> routeCodes);
  Future<void> clearCache();
}
