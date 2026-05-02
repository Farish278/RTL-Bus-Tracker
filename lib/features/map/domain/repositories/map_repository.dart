import '../entities/models.dart';

abstract class MapRepository {
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
    List<String> routeCodes,
  );
  Future<RouteSchedule?> getRouteSchedule(
    String routeCode, {
    bool forceRefresh = false,
  });
  Future<List<BusLocation>> getLiveBusLocations(List<String> routeCodes);
  Stream<List<BusLocation>> watchLiveBusLocations(List<String> routeCodes);
  Future<void> clearCache();
}
