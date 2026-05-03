import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/debug_log.dart';
import '../../domain/entities/models.dart';
import '../controllers/map_controller.dart';
import '../widgets/layer_toggle_chip.dart';

const bool _forceMapPlaceholder = bool.fromEnvironment(
  'RTL_FORCE_MAP_PLACEHOLDER',
  defaultValue: false,
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  static const String _lightTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _darkTileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const List<String> _cartoSubdomains = ['a', 'b', 'c', 'd'];
  final fm.MapController _mapController = fm.MapController();
  int _lastFitNonce = -1;
  BusStop? _selectedStop;
  String? _selectedBusKey;
  bool _isFollowingSelectedBus = false;
  bool _isProgrammaticMapMove = false;
  LatLng? _lastFollowPoint;
  DateTime _lastFollowMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  ProviderSubscription<MapState>? _stateSub;
  final ScrollController _routeChipsScrollController = ScrollController();
  String _routeStopSearch = '';
  final Map<String, String?> _selectedDirectionByRoute = {};
  final Map<String, bool> _expandedStopScheduleByKey = {};
  final Map<String, bool> _expandedRouteStopTimesByKey = {};
  Object? _mapBuildError;
  static const Color _stableRouteFallbackColor = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(mapControllerProvider.notifier).setMapScreenActive(true);
    _stateSub = ref.listenManual<MapState>(mapControllerProvider, (prev, next) {
      final previousAreaCode = prev?.selectedAreaCode;
      if (previousAreaCode != null &&
          previousAreaCode != next.selectedAreaCode) {
        setState(() {
          _selectedStop = null;
          _selectedBusKey = null;
          _isFollowingSelectedBus = false;
          _lastFollowPoint = null;
          _routeStopSearch = '';
          _selectedDirectionByRoute.clear();
          _expandedStopScheduleByKey.clear();
          _expandedRouteStopTimesByKey.clear();
        });
      }
      _handleFollowState(next);
      DebugLog.throttled(
        'map_render_counts',
        'render stats routes=${next.geometries.length} stops=${next.routes.where((e) => next.selectedRouteCodes.contains(e.routeCode)).expand((r) => r.stops).length} buses=${next.liveBuses.length}',
        interval: const Duration(seconds: 10),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    ref.read(mapControllerProvider.notifier).setMapScreenActive(active);
  }

  @override
  void dispose() {
    _stateSub?.close();
    _routeChipsScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    ref.read(mapControllerProvider.notifier).setMapScreenActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapControllerProvider);
    final c = ref.read(mapControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final selectedRoutes = state.routes
        .where((e) => state.selectedRouteCodes.contains(e.routeCode))
        .toList();
    final selectedBus = _resolveSelectedBus(state);
    if (_selectedBusKey != null && selectedBus == null) {
      _isFollowingSelectedBus = false;
    }
    final primaryRoute = selectedRoutes.firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stopsByCode = <String, List<BusRoute>>{};

    for (final route in selectedRoutes) {
      for (final stop in route.stops) {
        stopsByCode.putIfAbsent(stop.code, () => <BusRoute>[]).add(route);
      }
    }

    if (_lastFitNonce != state.fitNonce) {
      _lastFitNonce = state.fitNonce;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitPoints(state.fitPoints),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: scheme.surface)),
          if (_forceMapPlaceholder || _mapBuildError != null)
            Positioned.fill(
              child: _buildMapFallbackCard(
                context,
                message: _mapBuildError == null
                    ? 'Map disabled for emulator diagnostics.'
                    : 'Map failed to initialize. You can still use route and schedule controls.',
              ),
            )
          else
            Builder(
              builder: (context) {
                try {
                  return fm.FlutterMap(
                    mapController: _mapController,
                    options: fm.MapOptions(
                      initialCenter: LatLng(
                        AppConfig.defaultLat,
                        AppConfig.defaultLng,
                      ),
                      initialZoom: 12,
                      onPositionChanged: (_, hasGesture) {
                        if (!_isProgrammaticMapMove &&
                            hasGesture &&
                            _isFollowingSelectedBus) {
                          setState(() => _isFollowingSelectedBus = false);
                        }
                      },
                    ),
                    children: [
                      fm.TileLayer(
                        urlTemplate: _lightTileUrl,
                        userAgentPackageName: 'com.farish278.rtl_bus_tracker',
                      ),
                      if (isDark)
                        fm.TileLayer(
                          urlTemplate: _darkTileUrl,
                          subdomains: _cartoSubdomains,
                          fallbackUrl: _lightTileUrl,
                          userAgentPackageName: 'com.farish278.rtl_bus_tracker',
                          errorTileCallback: _onDarkTileError,
                        ),
                      if (state.showRoutes)
                        fm.PolylineLayer(
                          polylines: state.geometries
                              .where((g) => g.points.isNotEmpty)
                              .map(
                                (g) => fm.Polyline(
                                  points: g.points
                                      .where(_isValidPoint)
                                      .toList(),
                                  strokeWidth: isDark ? 5.8 : 4.5,
                                  color: _colorFor(g.routeCode, state.routes),
                                  borderStrokeWidth: isDark ? 2.0 : 1.2,
                                  borderColor: Colors.white.withValues(
                                    alpha: isDark ? 0.78 : 0.5,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      if (state.activeAlert != null ||
                          state.previewAlert != null)
                        fm.CircleLayer(
                          circles: _buildAlertCircles(state, scheme),
                        ),
                      if (state.showStops)
                        fm.MarkerLayer(
                          markers: stopsByCode.entries.map((entry) {
                            final stop = entry.value.first.stops.firstWhere(
                              (s) => s.code == entry.key,
                            );
                            final routeColor = _routeColor(entry.value.first);
                            final multi = entry.value.length > 1;
                            final fill = scheme.surface;
                            return fm.Marker(
                              width: 24,
                              height: 24,
                              point: _isValidPoint(stop.point)
                                  ? stop.point
                                  : const LatLng(
                                      AppConfig.defaultLat,
                                      AppConfig.defaultLng,
                                    ),
                              child: GestureDetector(
                                onTap: () {
                                  final servingRoutes =
                                      stopsByCode[stop.code] ??
                                      const <BusRoute>[];
                                  setState(() {
                                    _selectedBusKey = null;
                                    _isFollowingSelectedBus = false;
                                    _lastFollowPoint = null;
                                    _selectedStop = stop;
                                    final previewRoute =
                                        entry.value.firstOrNull;
                                    if (previewRoute != null) {
                                      c.previewStopAlert(
                                        route: previewRoute,
                                        stop: stop,
                                        thresholdMeters:
                                            state.defaultAlertDistanceMeters,
                                      );
                                    }
                                  });
                                  c.loadSchedulesForStop(stop, servingRoutes);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: multi
                                        ? fill.withValues(
                                            alpha: isDark ? 0.94 : 1,
                                          )
                                        : routeColor.withValues(
                                            alpha: isDark ? 0.4 : 0.3,
                                          ),
                                    border: Border.all(
                                      color: routeColor,
                                      width: isDark ? 2.4 : 2.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.28 : 0.12,
                                        ),
                                        blurRadius: isDark ? 7 : 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: multi
                                      ? Icon(
                                          Icons.layers,
                                          size: 11,
                                          color: routeColor,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (state.showBuses)
                        fm.MarkerLayer(
                          markers: state.liveBuses
                              .where(
                                (b) => state.selectedRouteCodes.contains(
                                  b.routeCode,
                                ),
                              )
                              .where((b) => _isValidPoint(b.point))
                              .map((b) {
                                final color = _colorFor(
                                  b.routeCode,
                                  state.routes,
                                );
                                final angle = (b.heading ?? 0) * math.pi / 180;
                                return fm.Marker(
                                  width: 42,
                                  height: 42,
                                  point: b.point,
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedStop = null;
                                      _selectedBusKey = _busKey(b);
                                      _isFollowingSelectedBus = true;
                                      _lastFollowPoint = b.point;
                                      _moveToBus(b.point);
                                      c.clearPreviewStopAlert();
                                    }),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.6,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.18,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.directions_bus,
                                            color: Colors.white,
                                            size: 23,
                                          ),
                                        ),
                                        if (b.heading != null)
                                          Positioned(
                                            top: -7,
                                            right: -7,
                                            child: Transform.rotate(
                                              angle: angle,
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.95),
                                                  border: Border.all(
                                                    color: color,
                                                    width: 1.8,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.navigation,
                                                  size: 13,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      if (state.showUserLocation && state.userLocation != null)
                        fm.MarkerLayer(
                          markers: [
                            fm.Marker(
                              width: 24,
                              height: 24,
                              point: _isValidPoint(state.userLocation!)
                                  ? state.userLocation!
                                  : const LatLng(
                                      AppConfig.defaultLat,
                                      AppConfig.defaultLng,
                                    ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.tertiary,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      fm.RichAttributionWidget(
                        attributions: [
                          const fm.TextSourceAttribution(
                            'OpenStreetMap contributors',
                          ),
                          if (isDark) const fm.TextSourceAttribution('CARTO'),
                        ],
                      ),
                    ],
                  );
                } catch (e) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _mapBuildError = e);
                  });
                  return _buildMapFallbackCard(
                    context,
                    message:
                        'Map failed to initialize. You can still use route and schedule controls.',
                  );
                }
              },
            ),
          if (state.isLoading || state.error != null)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              child: _buildMapStatusOverlay(context, state),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(
                              alpha: isDark ? 0.9 : 0.78,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            'RTL Bus Tracker',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: () =>
                              c.loadInitial(force: true, shouldAutoFit: false),
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.surfaceContainerHigh
                                .withValues(alpha: isDark ? 0.94 : 0.86),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => context.push('/settings'),
                          icon: const Icon(Icons.settings),
                          tooltip: 'Settings',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.surfaceContainerHigh
                                .withValues(alpha: isDark ? 0.94 : 0.86),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Area',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showAreaSheet(
                              context,
                              state.areas,
                              state.selectedAreaCode,
                              c.selectArea,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      state.areas
                                              .firstWhereOrNull(
                                                (a) =>
                                                    a.code ==
                                                    state.selectedAreaCode,
                                              )
                                              ?.name ??
                                          AppConfig.defaultAreaName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                          SizedBox(
                            height: 44,
                            child: ListView(
                              key: const PageStorageKey<String>(
                                'route_chip_list',
                              ),
                              controller: _routeChipsScrollController,
                              scrollDirection: Axis.horizontal,
                              children: state.routes.map((r) {
                                final selected = state.selectedRouteCodes
                                    .contains(r.routeCode);
                                final color = _routeColor(r);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    selected: selected,
                                    showCheckmark: false,
                                    avatar: selected
                                        ? Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: _readableText(color),
                                          )
                                        : null,
                                    label: Text(
                                      r.routeNumber.isNotEmpty
                                          ? r.routeNumber
                                          : r.routeCode,
                                    ),
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? _readableText(color)
                                          : color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    side: BorderSide(color: color, width: 1.4),
                                    backgroundColor: Colors.transparent,
                                    selectedColor: color,
                                    onSelected: (_) =>
                                        c.toggleRoute(r.routeCode),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                LayerToggleChip(
                                  label: 'Routes',
                                  icon: Icons.alt_route,
                                  selected: state.showRoutes,
                                  onSelected: (v) => c.toggleLayer(routes: v),
                                ),
                                const SizedBox(width: 8),
                                LayerToggleChip(
                                  label: 'Stops',
                                  icon: Icons.location_on,
                                  selected: state.showStops,
                                  onSelected: (v) => c.toggleLayer(stops: v),
                                ),
                                const SizedBox(width: 8),
                                LayerToggleChip(
                                  label: 'Live Buses',
                                  icon: Icons.directions_bus,
                                  selected: state.showBuses,
                                  onSelected: (v) => c.toggleLayer(buses: v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.offlineNotice)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              'Offline mode: showing cached data',
                              style: TextStyle(color: scheme.onErrorContainer),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 180,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'map_zoom_in_fab',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_zoom_out_fab',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_fit_fab',
                  onPressed: () => _fitPoints(state.fitPoints),
                  child: const Icon(Icons.center_focus_strong),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_location_fab',
                  onPressed: () => c.toggleUserLocation(),
                  child: Icon(
                    state.showUserLocation
                        ? Icons.my_location
                        : Icons.location_searching,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 0,
            child: _buildDetailsSheet(
              context: context,
              state: state,
              primaryRoute: primaryRoute,
              selectedBus: selectedBus,
              stopsByCode: stopsByCode,
            ),
          ),
          if (_isFollowingSelectedBus && selectedBus != null)
            Positioned(
              left: 16,
              bottom: 160,
              child: ActionChip(
                avatar: const Icon(Icons.gps_fixed, size: 18),
                label: const Text('Following bus'),
                onPressed: () =>
                    setState(() => _isFollowingSelectedBus = false),
              ),
            ),
          if ((state.locationMessage ?? '').isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 140,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(state.locationMessage!),
                ),
              ),
            ),
          if (state.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsSheet({
    required BuildContext context,
    required MapState state,
    required BusRoute? primaryRoute,
    required BusLocation? selectedBus,
    required Map<String, List<BusRoute>> stopsByCode,
  }) {
    final selectedStop = _selectedStop;
    if (selectedStop == null && selectedBus == null && primaryRoute == null) {
      return const SizedBox.shrink();
    }
    return DraggableScrollableSheet(
      minChildSize: 0.16,
      initialChildSize: 0.26,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: const [0.26, 0.5, 0.94],
      builder: (context, scrollController) {
        return Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (selectedStop != null)
                  _buildStopCard(
                    context,
                    selectedStop,
                    stopsByCode[selectedStop.code] ?? const [],
                    state.stopEtas[selectedStop.code] ?? const [],
                  )
                else if (selectedBus != null)
                  _buildBusCard(context, selectedBus, state.routes)
                else if (primaryRoute != null)
                  _buildRouteCard(context, primaryRoute),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRouteCard(BuildContext context, BusRoute route) {
    final color = _routeColor(route);
    final viewState = ref.watch(mapControllerProvider);
    final schedule = viewState.routeSchedules[route.routeCode];
    final loading = viewState.loadingScheduleRouteCodes.contains(
      route.routeCode,
    );
    final error = viewState.scheduleErrorsByRouteCode[route.routeCode];
    final directions = (schedule?.stops ?? const <StopSchedule>[])
        .expand((stop) => stop.entries)
        .map((entry) => entry.direction)
        .whereType<ScheduleDirection>()
        .fold<Map<String, ScheduleDirection>>({}, (acc, direction) {
          acc[direction.id] = direction;
          return acc;
        })
        .values
        .toList();
    final hasDirections = directions.length > 1;
    final selectedDirectionId = _selectedDirectionByRoute[route.routeCode];
    if (hasDirections &&
        selectedDirectionId != null &&
        directions.every((d) => d.id != selectedDirectionId)) {
      _selectedDirectionByRoute.remove(route.routeCode);
    }
    final effectiveDirectionId = hasDirections
        ? _selectedDirectionByRoute[route.routeCode]
        : null;
    final stops = (schedule?.stops ?? const <StopSchedule>[])
        .where((s) {
          final query = _routeStopSearch.trim().toLowerCase();
          return query.isEmpty || s.stopName.toLowerCase().contains(query);
        })
        .where((s) {
          final entries = s.entries.where((entry) {
            if (effectiveDirectionId == null) return true;
            return entry.direction?.id == effectiveDirectionId;
          });
          return entries.isNotEmpty;
        })
        .toList();
    final entries =
        schedule?.stops
            .expand(
              (s) => s.entries
                  .where(
                    (entry) =>
                        effectiveDirectionId == null ||
                        entry.direction?.id == effectiveDirectionId,
                  )
                  .map((e) => _formatTime(e.timeLabel)),
            )
            .where((t) => t.isNotEmpty)
            .toList() ??
        const <String>[];
    final firstBus = entries.isEmpty ? '-' : entries.first;
    final lastBus = entries.isEmpty ? '-' : entries.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  route.routeNumber.isEmpty
                      ? route.routeCode
                      : route.routeNumber,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${route.startStationName ?? '-'} -> ${route.endStationName ?? '-'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => ref
                  .read(mapControllerProvider.notifier)
                  .loadScheduleForRoute(route, forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: _routeRefreshButtonStyle(context, color),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryCard(context, 'First bus', firstBus, color),
            ),
            const SizedBox(width: 8),
            Expanded(child: _summaryCard(context, 'Last bus', lastBus, color)),
            const SizedBox(width: 8),
            Expanded(
              child: _summaryCard(
                context,
                'Stops',
                '${schedule?.stops.length ?? route.stops.length}',
                color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (hasDirections) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All directions'),
                selected: effectiveDirectionId == null,
                onSelected: (_) => setState(
                  () => _selectedDirectionByRoute[route.routeCode] = null,
                ),
              ),
              ...directions.map(
                (direction) => ChoiceChip(
                  label: Text(direction.label),
                  selected: effectiveDirectionId == direction.id,
                  onSelected: (_) => setState(
                    () => _selectedDirectionByRoute[route.routeCode] =
                        direction.id,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          onChanged: (v) => setState(() => _routeStopSearch = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search stops',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          _scheduleMessageCard(
            context,
            message: error,
            icon: Icons.error_outline,
            actionLabel: 'Retry',
            onAction: () => ref
                .read(mapControllerProvider.notifier)
                .loadScheduleForRoute(route, forceRefresh: true),
          )
        else if (schedule == null)
          _scheduleMessageCard(context, message: 'Loading route schedule...')
        else if (stops.isEmpty)
          _scheduleMessageCard(
            context,
            message: 'No schedule rows match your filter.',
          )
        else
          ...stops.map((stop) {
            final stopExpansionKey =
                '${route.routeCode}:${stop.stopCode}:${effectiveDirectionId ?? 'all'}';
            final isExpanded =
                _expandedRouteStopTimesByKey[stopExpansionKey] ?? false;
            final times = stop.entries
                .where(
                  (entry) =>
                      effectiveDirectionId == null ||
                      entry.direction?.id == effectiveDirectionId,
                )
                .map((e) => _formatTime(e.timeLabel))
                .where((t) => t.isNotEmpty)
                .toSet()
                .toList();
            const collapsedLimit = 8;
            final hasMoreThanCollapsedLimit = times.length > collapsedLimit;
            final visibleTimes = isExpanded
                ? times
                : times.take(collapsedLimit).toList();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.stopName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'First: ${times.firstOrNull ?? '-'}   Last: ${times.lastOrNull ?? '-'}   Trips: ${times.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (times.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: visibleTimes
                                  .map(
                                    (t) => Chip(
                                      label: Text(t),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                  .toList(),
                            ),
                            if (hasMoreThanCollapsedLimit)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => setState(
                                    () =>
                                        _expandedRouteStopTimesByKey[stopExpansionKey] =
                                            !isExpanded,
                                  ),
                                  child: Text(
                                    isExpanded
                                        ? 'Show less'
                                        : 'Show all ${times.length}',
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStopCard(
    BuildContext context,
    BusStop stop,
    List<BusRoute> routes,
    List<StopEta> etas,
  ) {
    final viewState = ref.watch(mapControllerProvider);
    final selectedDistance = viewState.defaultAlertDistanceMeters;
    final activeAlert = viewState.activeAlert;
    final selectedRouteCode = viewState.selectedStopScheduleRouteCode;
    final selectedRoute =
        routes.firstWhereOrNull((r) => r.routeCode == selectedRouteCode) ??
        (routes.length == 1 ? routes.first : null);
    final selectedRouteLabel = selectedRoute == null
        ? null
        : (selectedRoute.routeNumber.isEmpty
              ? selectedRoute.routeCode
              : selectedRoute.routeNumber);
    final controller = ref.read(mapControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.setAlertDraftContext(
        routeCode: selectedRouteLabel,
        stopName: stop.name,
        distanceMeters: selectedDistance,
      );
    });
    final hasValidStopLocation =
        stop.point.latitude.abs() <= 90 && stop.point.longitude.abs() <= 180;
    final canNotify = selectedRoute != null && hasValidStopLocation;
    final disableReason = selectedRoute == null
        ? 'Select a route to enable alerts.'
        : (!hasValidStopLocation ? 'Stop location unavailable.' : null);
    final selectedSchedule = selectedRoute == null
        ? null
        : viewState.routeSchedules[selectedRoute.routeCode];
    final stopSchedule = selectedSchedule?.stops.firstWhereOrNull(
      (s) => s.stopCode == stop.code,
    );
    final stopScheduleExpansionKey = selectedRoute == null
        ? null
        : '${stop.code}:${selectedRoute.routeCode}';
    final isStopScheduleExpanded = stopScheduleExpansionKey != null
        ? (_expandedStopScheduleByKey[stopScheduleExpansionKey] ?? false)
        : false;
    final isActive =
        activeAlert?.stopCode == stop.code &&
        selectedRoute != null &&
        activeAlert?.routeCode == selectedRoute.routeCode;
    final options = const [200.0, 300.0, 500.0, 1000.0];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Stop code: ${stop.code}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () {
                ref
                    .read(mapControllerProvider.notifier)
                    .clearPreviewStopAlert();
                setState(() => _selectedStop = null);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: routes
              .map(
                (r) => FilterChip(
                  selected: selectedRouteCode == r.routeCode,
                  label: Text(
                    r.routeNumber.isEmpty ? r.routeCode : r.routeNumber,
                  ),
                  onSelected: (_) {
                    ref
                        .read(mapControllerProvider.notifier)
                        .selectStopScheduleRouteCode(r.routeCode);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Text('Upcoming', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (etas.isEmpty)
          _scheduleMessageCard(
            context,
            message: 'No live ETA currently available for this stop.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: etas
                .take(6)
                .map(
                  (e) => InputChip(
                    label: Text(
                      '${e.direction.toUpperCase()}: ${_formatTime(e.timeLabel)}',
                    ),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: selectedRoute == null
                  ? null
                  : () => ref
                        .read(mapControllerProvider.notifier)
                        .loadScheduleForRoute(
                          selectedRoute,
                          forceRefresh: true,
                        ),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: _routeRefreshButtonStyle(
                context,
                selectedRoute != null
                    ? _routeColor(selectedRoute)
                    : _stableRouteFallbackColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedRoute == null)
          _scheduleMessageCard(
            context,
            message: 'No route selected for this stop.',
          )
        else if (viewState.loadingScheduleRouteCodes.contains(
          selectedRoute.routeCode,
        ))
          const Center(child: CircularProgressIndicator())
        else if (viewState.scheduleErrorsByRouteCode[selectedRoute.routeCode] !=
            null)
          _scheduleMessageCard(
            context,
            message:
                viewState.scheduleErrorsByRouteCode[selectedRoute.routeCode]!,
            actionLabel: 'Retry',
            onAction: () => ref
                .read(mapControllerProvider.notifier)
                .loadScheduleForRoute(selectedRoute, forceRefresh: true),
          )
        else if (stopSchedule == null)
          _scheduleMessageCard(
            context,
            message: 'Route schedule shown. Stop-specific times unavailable.',
          )
        else ...[
          Builder(
            builder: (context) {
              const collapsedLimit = 10;
              final times = stopSchedule.entries
                  .map((e) => _formatTime(e.timeLabel))
                  .toSet()
                  .toList();
              final hasMoreThanCollapsedLimit = times.length > collapsedLimit;
              final visibleTimes = isStopScheduleExpanded
                  ? times
                  : times.take(collapsedLimit).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: visibleTimes
                        .map(
                          (t) => Chip(
                            label: Text(t),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                  if (hasMoreThanCollapsedLimit &&
                      stopScheduleExpansionKey != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(
                          () =>
                              _expandedStopScheduleByKey[stopScheduleExpansionKey] =
                                  !isStopScheduleExpanded,
                        ),
                        child: Text(
                          isStopScheduleExpanded
                              ? 'Show less'
                              : 'Show all ${times.length} times',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: selectedRoute == null
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Select a route chip to view the full schedule.',
                      ),
                    ),
                  );
                }
              : () => _showFullRouteScheduleSheet(context, selectedRoute),
          child: const Text('View full route schedule'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: options
              .map(
                (meters) => ChoiceChip(
                  label: Text(_distanceLabel(meters)),
                  selected: selectedDistance == meters,
                  onSelected: (_) {
                    final controller = ref.read(mapControllerProvider.notifier);
                    controller.setDefaultAlertDistance(meters);
                    if (selectedRoute != null) {
                      controller.previewStopAlert(
                        route: selectedRoute,
                        stop: stop,
                        thresholdMeters: meters,
                      );
                    }
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        if (disableReason != null)
          _scheduleMessageCard(
            context,
            icon: Icons.info_outline,
            message: disableReason,
          ),
        if (disableReason != null) const SizedBox(height: 6),
        if (isActive)
          _scheduleMessageCard(
            context,
            icon: Icons.notifications_active_outlined,
            message: 'Alert active: within ${_distanceLabel(selectedDistance)}',
          ),
        if (viewState.alertStatusMessage != null &&
            !_isTriggeredStatusMessage(viewState.alertStatusMessage!))
          _scheduleMessageCard(
            context,
            icon: Icons.info_outline,
            message: viewState.alertStatusMessage!,
          ),
        if (viewState.notificationError != null)
          _scheduleMessageCard(
            context,
            icon: Icons.error_outline,
            message: viewState.notificationError!,
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: !canNotify
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final result = await ref
                          .read(mapControllerProvider.notifier)
                          .enableStopAlert(
                            route: selectedRoute,
                            stop: stop,
                            thresholdMeters: selectedDistance,
                          );
                      if (!mounted) return;
                      final snack = result.backgroundWarning ?? result.message;
                      messenger.showSnackBar(SnackBar(content: Text(snack)));
                    },
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(isActive ? 'Alert enabled' : 'Notify me'),
            ),
            OutlinedButton.icon(
              onPressed: isActive
                  ? () => ref
                        .read(mapControllerProvider.notifier)
                        .cancelStopAlert()
                  : null,
              icon: const Icon(Icons.notifications_off_outlined),
              label: const Text('Cancel alert'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _scheduleMessageCard(
    BuildContext context, {
    required String message,
    IconData icon = Icons.schedule,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            if (actionLabel != null && onAction != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStatusOverlay(BuildContext context, MapState state) {
    if (state.error != null) {
      final controller = ref.read(mapControllerProvider.notifier);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.error!)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => controller.loadInitial(force: true),
                    child: const Text('Retry'),
                  ),
                  OutlinedButton(
                    onPressed: controller.clearCache,
                    child: const Text('Clear cache'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Expanded(child: Text('Loading map data...')),
          ],
        ),
      ),
    );
  }

  Widget _buildMapFallbackCard(
    BuildContext context, {
    required String message,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.map_outlined),
                  SizedBox(width: 8),
                  Text('Map unavailable'),
                ],
              ),
              const SizedBox(height: 8),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  void _onDarkTileError(Object tile, Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    final message = error.toString();
    final hasAuthError = message.contains('401') || message.contains('403');
    DebugLog.throttled(
      hasAuthError ? 'map_dark_tile_auth_error' : 'map_dark_tile_error',
      hasAuthError
          ? 'Dark tile auth error detected ($message). Falling back to light tiles.'
          : 'Dark tile fetch error: $message',
      interval: const Duration(seconds: 8),
    );
  }

  String _formatTime(String raw) {
    final text = raw.trim();
    if (text.length >= 5 && text[2] == ':') return text.substring(0, 5);
    return text;
  }

  bool _isTriggeredStatusMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized == 'alert triggered' ||
        normalized == 'alert triggered.' ||
        normalized.contains('alert triggered');
  }

  Widget _buildBusCard(
    BuildContext context,
    BusLocation bus,
    List<BusRoute> routes,
  ) {
    final route = routes.firstWhereOrNull((r) => r.routeCode == bus.routeCode);
    return Card(
      key: ValueKey('bus:${bus.busCode}-${bus.plateNumber}'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${route?.routeNumber ?? bus.routeCode} • ${bus.busCode.isNotEmpty ? bus.busCode : bus.plateNumber}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((bus.destination ?? '').isNotEmpty)
              Text('Destination: ${bus.destination}'),
            if ((bus.tripDirection ?? bus.direction ?? '').isNotEmpty)
              Text('Direction: ${bus.tripDirection ?? bus.direction}'),
            if ((bus.nextStop ?? '').isNotEmpty)
              Text('Next stop: ${bus.nextStop}'),
            Text(
              bus.heading == null
                  ? 'Bearing: Direction unavailable'
                  : 'Bearing: ${bus.heading!.toStringAsFixed(0)}°',
            ),
            Text('Updated: now', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => setState(() {
                    _isFollowingSelectedBus = !_isFollowingSelectedBus;
                    if (_isFollowingSelectedBus) {
                      _moveToBus(bus.point);
                    }
                  }),
                  child: Text(
                    _isFollowingSelectedBus ? 'Stop following' : 'Follow bus',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullRouteScheduleSheet(BuildContext context, BusRoute route) {
    ref.read(mapControllerProvider.notifier).loadScheduleForRoute(route);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _buildFullRouteScheduleSheet(sheetContext, route),
      ),
    );
  }

  Widget _buildFullRouteScheduleSheet(BuildContext context, BusRoute route) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        color: scheme.surface,
        elevation: 10,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [_buildRouteCard(context, route)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAreaSheet(
    BuildContext context,
    List<BusArea> areas,
    String selectedAreaCode,
    Future<void> Function(String) onSelect,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          children: areas
              .map(
                (area) => ListTile(
                  leading: Icon(
                    area.type == AreaType.atoll
                        ? Icons.sailing
                        : Icons.location_city,
                  ),
                  title: Text(area.name),
                  subtitle: Text(
                    area.type == AreaType.atoll
                        ? 'Atoll buses'
                        : 'Greater Male area',
                  ),
                  trailing: area.code == selectedAreaCode
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onSelect(area.code);
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }

  void _fitPoints(List<LatLng> points) {
    try {
      DebugLog.throttled(
        'map_fit',
        'fitPoints called with ${points.length} points',
        interval: const Duration(seconds: 2),
      );
      if (points.isEmpty) {
        _mapController.move(
          const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
          12,
        );
        return;
      }
      if (points.length == 1) {
        _mapController.move(points.first, 12);
        return;
      }
      _mapController.fitCamera(
        fm.CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(44, 190, 44, 190),
        ),
      );
    } catch (e) {
      DebugLog.info('fitPoints error: $e');
    }
  }

  List<fm.CircleMarker> _buildAlertCircles(MapState state, ColorScheme scheme) {
    final circles = <fm.CircleMarker>[];
    if (state.previewAlert != null) {
      circles.add(
        _circleForAlert(
          state.previewAlert!,
          scheme,
          routes: state.routes,
          isPreview: true,
        ),
      );
    }
    if (state.activeAlert != null) {
      circles.add(
        _circleForAlert(
          state.activeAlert!,
          scheme,
          routes: state.routes,
          isPreview: false,
        ),
      );
    }
    return circles;
  }

  fm.CircleMarker _circleForAlert(
    StopAlert alert,
    ColorScheme scheme, {
    required List<BusRoute> routes,
    required bool isPreview,
  }) {
    final route = routes.firstWhereOrNull(
      (r) => r.routeCode == alert.routeCode,
    );
    final color = route == null ? scheme.primary : _routeColor(route);
    return fm.CircleMarker(
      point: alert.stopPoint,
      radius: alert.distanceThresholdMeters,
      useRadiusInMeter: true,
      color: color.withValues(alpha: isPreview ? 0.08 : 0.14),
      borderColor: color.withValues(alpha: isPreview ? 0.35 : 0.5),
      borderStrokeWidth: isPreview ? 1.2 : 1.6,
    );
  }

  String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  Color _colorFor(String routeCode, List<BusRoute> routes) {
    final route = routes.where((r) => r.routeCode == routeCode).firstOrNull;
    if (route == null) return _stableRouteFallbackColor;
    return _routeColor(route);
  }

  Color _routeColor(BusRoute route) {
    final colorHex = route.colorHex.replaceAll('#', '');
    final val = int.tryParse(colorHex, radix: 16);
    if (val == null) return _stableRouteFallbackColor;
    return Color(0xFF000000 | val);
  }

  ButtonStyle _routeRefreshButtonStyle(BuildContext context, Color routeColor) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = Color.alphaBlend(
      routeColor.withValues(alpha: isDark ? 0.36 : 0.18),
      isDark ? scheme.surfaceContainerHigh : scheme.surface,
    );
    final foreground = _readableText(background);
    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      iconColor: foreground,
      disabledBackgroundColor: scheme.surfaceContainer,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
    );
  }

  Color _readableText(Color c) {
    final bright = ThemeData.estimateBrightnessForColor(c);
    return bright == Brightness.dark ? Colors.white : Colors.black;
  }

  String _busKey(BusLocation bus) =>
      '${bus.routeCode}:${bus.busCode.isNotEmpty ? bus.busCode : bus.plateNumber}';

  BusLocation? _resolveSelectedBus(MapState state) {
    if (_selectedBusKey == null) return null;
    return state.liveBuses.firstWhereOrNull(
      (b) => _busKey(b) == _selectedBusKey,
    );
  }

  void _moveToBus(LatLng point) {
    if (!_isValidPoint(point)) return;
    final zoom = _mapController.camera.zoom;
    _isProgrammaticMapMove = true;
    DebugLog.throttled(
      'follow_move',
      'follow move -> lat=${point.latitude}, lng=${point.longitude}',
      interval: const Duration(seconds: 1),
    );
    _mapController.move(point, zoom);
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _isProgrammaticMapMove = false;
    });
  }

  void _handleFollowState(MapState next) {
    if (!_isFollowingSelectedBus || _selectedBusKey == null) return;
    final bus = next.liveBuses.firstWhereOrNull(
      (b) => _busKey(b) == _selectedBusKey,
    );
    if (bus == null) {
      if (mounted) setState(() => _isFollowingSelectedBus = false);
      return;
    }
    final lastPoint = _lastFollowPoint;
    final movedMeters = lastPoint == null
        ? 9999.0
        : const Distance().as(LengthUnit.Meter, lastPoint, bus.point);
    final now = DateTime.now();
    final cooldownOk =
        now.difference(_lastFollowMoveAt) >= const Duration(milliseconds: 900);
    if (movedMeters < 10 || !cooldownOk) return;
    _lastFollowPoint = bus.point;
    _lastFollowMoveAt = now;
    if (!mounted) return;
    _moveToBus(bus.point);
  }

  bool _isValidPoint(LatLng point) =>
      point.latitude.abs() <= 90 && point.longitude.abs() <= 180;
}
