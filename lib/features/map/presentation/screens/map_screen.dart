import 'dart:math' as math;
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/debug_log.dart';
import '../../domain/entities/models.dart';
import '../../data/db/map_tile_cache.dart';
import '../controllers/map_controller.dart';
import '../widgets/layer_toggle_chip.dart';
import '../widgets/basemap_layer.dart';
import '../widgets/collapsible_map_details.dart';
import '../../../settings/presentation/controllers/theme_mode_controller.dart';

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
  String? _detailsRouteCode;
  String _routeStopSearch = '';
  final Map<String, String?> _selectedDirectionByRoute = {};
  final Map<String, bool> _expandedStopScheduleByKey = {};
  final Map<String, bool> _expandedRouteStopTimesByKey = {};
  Object? _mapBuildError;
  late final fm.NetworkTileProvider _tileProvider = fm.NetworkTileProvider(
    cachingProvider: MapTileCache.instance,
    attemptDecodeOfHttpErrorResponses: false,
  );
  Timer? _freshnessTimer;
  List<BusRoute>? _indexedRoutes;
  Set<String>? _indexedSelection;
  Map<String, List<BusRoute>> _stopsByCode = {};
  List<RouteGeometry>? _indexedGeometry;
  List<RouteGeometry> _validGeometry = [];
  Widget? _staticRoutes;
  Widget? _staticStops;
  ColorScheme? _staticScheme;
  List<BusRoute>? _routeColorSource;
  static const Color _stableRouteFallbackColor = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _freshnessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
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
          _detailsRouteCode = null;
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
    final active =
        state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    ref.read(mapControllerProvider.notifier).setMapScreenActive(active);
  }

  @override
  void dispose() {
    _stateSub?.close();
    _freshnessTimer?.cancel();
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
    final primaryRoute =
        selectedRoutes.firstWhereOrNull(
          (route) => route.routeCode == _detailsRouteCode,
        ) ??
        selectedRoutes.firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!identical(_indexedRoutes, state.routes) ||
        !identical(_indexedSelection, state.selectedRouteCodes)) {
      _indexedRoutes = state.routes;
      _indexedSelection = state.selectedRouteCodes;
      _stopsByCode = {};
      _staticStops = null;
      for (final route in selectedRoutes) {
        for (final stop in route.stops) {
          _stopsByCode.putIfAbsent(stop.code, () => []).add(route);
        }
      }
    }
    final stopsByCode = _stopsByCode;
    if (!identical(_indexedGeometry, state.geometries)) {
      _indexedGeometry = state.geometries;
      _staticRoutes = null;
      _validGeometry = state.geometries
          .map(
            (g) => RouteGeometry(
              routeCode: g.routeCode,
              points: g.points.where(_isValidPoint).toList(),
            ),
          )
          .where((g) => g.points.isNotEmpty)
          .toList();
    }
    if (_staticScheme != scheme ||
        !identical(_routeColorSource, state.routes)) {
      _staticRoutes = null;
      _staticStops = null;
      _staticScheme = scheme;
      _routeColorSource = state.routes;
    }
    if (_lastFitNonce != state.fitNonce) {
      _lastFitNonce = state.fitNonce;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitPoints(state.fitPoints),
      );
    }
    final isInformative =
        ref.watch(uiDetailLevelProvider) == UiDetailLevel.informative;
    final detailsKey = _selectedStop != null
        ? 'stop:${_selectedStop!.code}'
        : selectedBus != null
        ? 'bus:${_busKey(selectedBus)}'
        : primaryRoute != null
        ? 'routes'
        : null;
    final selectionKey = detailsKey == null
        ? null
        : '${state.selectedAreaCode}:${state.selectedRouteCodes.join(',')}:$detailsKey';

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
                      BasemapLayer(isDark: isDark, tileProvider: _tileProvider),
                      if (state.showRoutes)
                        (_staticRoutes ??= fm.PolylineLayer(
                          polylines: _validGeometry
                              .map(
                                (g) => fm.Polyline(
                                  points: g.points,
                                  strokeWidth: isDark ? 5.8 : 4.5,
                                  color: _colorFor(g.routeCode, state.routes),
                                  borderStrokeWidth: isDark ? 2.0 : 1.2,
                                  borderColor: Colors.white.withValues(
                                    alpha: isDark ? 0.78 : 0.5,
                                  ),
                                ),
                              )
                              .toList(),
                        )),
                      if (state.activeAlert != null ||
                          state.previewAlert != null)
                        fm.CircleLayer(
                          circles: _buildAlertCircles(state, scheme),
                        ),
                      if (state.showStops)
                        (_staticStops ??= fm.MarkerLayer(
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
                                        thresholdMeters: ref
                                            .read(mapControllerProvider)
                                            .defaultAlertDistanceMeters,
                                      );
                                    }
                                  });
                                  c.setViewedEtaRoutes(
                                    servingRoutes
                                        .map((r) => r.routeCode)
                                        .toSet(),
                                  );
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
                        )),
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
                                      c.setViewedEtaRoutes({});
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
              top:
                  MediaQuery.paddingOf(context).top +
                  (isInformative ? 150 : 112),
              left: 12,
              right: 12,
              child: _buildMapStatusOverlay(context, state),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(context, state, c, isInformative),
                    const SizedBox(height: 8),
                    _buildRouteStrip(context, state, c, isInformative),
                    ..._buildStatusPills(context, state, isInformative),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CollapsibleMapDetails(
              selectionKey: selectionKey,
              icon: _selectedStop != null
                  ? Icons.location_on_outlined
                  : selectedBus != null
                  ? Icons.directions_bus
                  : Icons.route_outlined,
              onOpened: () {
                if (_selectedStop == null &&
                    selectedBus == null &&
                    primaryRoute != null) {
                  unawaited(c.loadScheduleForRoute(primaryRoute));
                }
              },
              detailsBuilder: (context) => _buildDetailsContent(
                context: context,
                state: state,
                primaryRoute: primaryRoute,
                selectedRoutes: selectedRoutes,
                selectedBus: selectedBus,
                stopsByCode: stopsByCode,
              ),
              overlaysBuilder: (context, controlsBottom) => [
                Positioned(
                  right: 12,
                  bottom: controlsBottom,
                  child: _buildMapControls(context, state, c),
                ),
                if (_isFollowingSelectedBus && selectedBus != null)
                  Positioned(
                    left: 12,
                    bottom: controlsBottom,
                    child: ActionChip(
                      avatar: const Icon(Icons.gps_fixed, size: 18),
                      label: Text(
                        isInformative
                            ? 'Following bus · tap to stop'
                            : 'Following bus',
                      ),
                      onPressed: () =>
                          setState(() => _isFollowingSelectedBus = false),
                    ),
                  ),
                if ((state.locationMessage ?? '').isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 72,
                    bottom: controlsBottom + 52,
                    child: _floatingSurface(
                      context,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(state.locationMessage!),
                      ),
                    ),
                  ),
              ],
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

  // ---------------------------------------------------------------------------
  // Floating map chrome
  // ---------------------------------------------------------------------------

  Widget _floatingSurface(
    BuildContext context, {
    required Widget child,
    double radius = 20,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: scheme.surface.withValues(alpha: isDark ? 0.94 : 0.97),
      elevation: 0,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  String _routeLabel(BusRoute r) =>
      r.routeNumber.isNotEmpty ? r.routeNumber : r.routeCode;

  String _routeDescriptiveName(BusRoute r) {
    var name = r.name.trim();
    if (name.isNotEmpty) {
      if (name == name.toUpperCase() && name.length > 3) {
        name = name
            .split(' ')
            .map(
              (word) => word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
            )
            .join(' ');
      }
      return name;
    }
    final from = (r.startStationName ?? '').trim();
    final to = (r.endStationName ?? '').trim();
    if (from.isNotEmpty && to.isNotEmpty && from != to) {
      return '$from to $to';
    }
    return r.routeNumber.isNotEmpty ? r.routeNumber : r.routeCode;
  }

  Widget _buildTopBar(
    BuildContext context,
    MapState state,
    MapController c,
    bool isInformative,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final areaName =
        state.areas
            .firstWhereOrNull((a) => a.code == state.selectedAreaCode)
            ?.name ??
        AppConfig.defaultAreaName;
    final selectedCount = state.selectedRouteCodes.length;
    return Row(
      children: [
        Expanded(
          child: _floatingSurface(
            context,
            radius: 28,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _showAreaSheet(
                        context,
                        state.areas,
                        state.selectedAreaCode,
                        c.selectArea,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 8),
                        child: Row(
                          children: [
                            Icon(Icons.place_outlined, color: scheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isInformative)
                                    Text(
                                      'Area',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  Text(
                                    areaName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.expand_more_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 26, color: scheme.outlineVariant),
                  InkWell(
                    onTap: () => _showRoutePickerSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            selectedCount == 0
                                ? (isInformative ? 'Find route' : 'Routes')
                                : '$selectedCount',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _floatingSurface(
          context,
          radius: 26,
          child: IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              c.setMapScreenActive(false);
              await context.push('/settings');
              if (mounted) c.setMapScreenActive(true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRouteStrip(
    BuildContext context,
    MapState state,
    MapController c,
    bool isInformative,
  ) {
    if (state.routes.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: isInformative ? 58 : 40,
      child: ListView.separated(
        key: const PageStorageKey<String>('route_chip_list'),
        controller: _routeChipsScrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: state.routes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final r = state.routes[index];
          final selected = state.selectedRouteCodes.contains(r.routeCode);
          final color = _routeColor(r);
          final onColor = _readableText(color);
          final routeName = _routeDescriptiveName(r);
          final bg = selected ? color : scheme.surface.withValues(alpha: 0.96);
          final fg = selected ? onColor : scheme.onSurface;
          return Material(
            color: bg,
            borderRadius: BorderRadius.circular(isInformative ? 16 : 20),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              borderRadius: BorderRadius.circular(isInformative ? 16 : 20),
              onTap: () => c.toggleRoute(r.routeCode),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isInformative ? 280 : 120,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isInformative ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isInformative ? 16 : 20),
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isInformative)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? onColor.withValues(alpha: 0.18)
                              : color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _routeLabel(r),
                          style: TextStyle(
                            color: selected ? onColor : _readableText(color),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else ...[
                      if (selected) ...[
                        Icon(Icons.check_rounded, size: 16, color: fg),
                        const SizedBox(width: 4),
                      ] else ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _routeLabel(r),
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (isInformative) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              '${r.stops.length} stops${r.fare != null ? ' · MVR ${r.fare!.toStringAsFixed(r.fare! % 1 == 0 ? 0 : 2)}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: fg.withValues(alpha: 0.8),
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle, size: 16, color: fg),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusPill(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color? background,
    Color? foreground,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color:
            background ?? scheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: foreground ?? scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground ?? scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatusPills(
    BuildContext context,
    MapState state,
    bool isInformative,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final pills = <Widget>[];
    if (state.loadingResources.isNotEmpty) {
      pills.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        ),
      );
    }
    if (state.offlineNotice) {
      pills.add(
        _statusPill(
          context,
          icon: Icons.cloud_off_rounded,
          text: 'Offline mode: showing cached data',
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        ),
      );
    }
    if (state.resourceStatuses.entries.any(
      (e) =>
          e.key.startsWith('live:') &&
          state.selectedRouteCodes.contains(e.key.substring(5)) &&
          (e.value.stale ||
              e.value.fetchedAt == null ||
              DateTime.now().difference(e.value.fetchedAt!) >
                  const Duration(seconds: 30)),
    )) {
      pills.add(
        _statusPill(
          context,
          icon: Icons.history_rounded,
          text: _liveAgeLabel(state),
        ),
      );
    }
    if (state.resourceStatuses.entries.any(
      (entry) =>
          entry.value.error != null &&
          (entry.key == 'routes' ||
              state.selectedRouteCodes.any(
                (code) =>
                    entry.key == 'geometry:$code' || entry.key == 'eta:$code',
              )),
    )) {
      pills.add(
        _statusPill(
          context,
          icon: Icons.sync_problem_rounded,
          text:
              'Some route information could not be refreshed · Saved data remains available',
        ),
      );
    }
    if (isInformative &&
        state.selectedRouteCodes.isEmpty &&
        state.routes.isNotEmpty &&
        !state.isLoading) {
      pills.add(
        _statusPill(
          context,
          icon: Icons.touch_app_outlined,
          text:
              'Tap a route to show it on the map, then tap a stop for arrival times',
          background: scheme.primaryContainer.withValues(alpha: 0.95),
          foreground: scheme.onPrimaryContainer,
        ),
      );
    }
    return pills;
  }

  Widget _buildMapControls(
    BuildContext context,
    MapState state,
    MapController c,
  ) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      icon: Icon(icon),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
    Widget divider() => SizedBox(
      width: 28,
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _floatingSurface(
          context,
          radius: 22,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(
                Icons.layers_outlined,
                'Map layers',
                () => _showLayersSheet(context),
              ),
              divider(),
              btn(
                Icons.refresh_rounded,
                'Refresh',
                () => c.loadInitial(force: true, shouldAutoFit: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _floatingSurface(
          context,
          radius: 22,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(
                Icons.add,
                'Zoom in',
                () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                ),
              ),
              divider(),
              btn(
                Icons.remove,
                'Zoom out',
                () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                ),
              ),
              divider(),
              btn(
                Icons.center_focus_strong_outlined,
                'Fit selected routes',
                () => _fitPoints(state.fitPoints),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _floatingSurface(
          context,
          radius: 22,
          child: IconButton(
            tooltip: 'My location',
            isSelected: state.showUserLocation,
            color: state.showUserLocation
                ? Theme.of(context).colorScheme.primary
                : null,
            icon: Icon(
              state.showUserLocation
                  ? Icons.my_location
                  : Icons.location_searching,
            ),
            onPressed: () => c.toggleUserLocation(),
          ),
        ),
      ],
    );
  }

  void _showLayersSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(mapControllerProvider);
          final ctrl = ref.read(mapControllerProvider.notifier);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Show on map',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      LayerToggleChip(
                        label: 'Routes',
                        icon: Icons.alt_route,
                        selected: s.showRoutes,
                        onSelected: (v) => ctrl.toggleLayer(routes: v),
                      ),
                      LayerToggleChip(
                        label: 'Stops',
                        icon: Icons.location_on,
                        selected: s.showStops,
                        onSelected: (v) => ctrl.toggleLayer(stops: v),
                      ),
                      LayerToggleChip(
                        label: 'Live Buses',
                        icon: Icons.directions_bus,
                        selected: s.showBuses,
                        onSelected: (v) => ctrl.toggleLayer(buses: v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRoutePickerSheet(BuildContext context) {
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Consumer(
            builder: (context, ref, _) {
              final s = ref.watch(mapControllerProvider);
              final ctrl = ref.read(mapControllerProvider.notifier);
              final informative =
                  ref.watch(uiDetailLevelProvider) == UiDetailLevel.informative;
              final q = query.trim().toLowerCase();
              final routes = s.routes.where((r) {
                if (q.isEmpty) return true;
                return [
                  r.routeNumber,
                  r.routeCode,
                  r.name,
                  r.startStationName ?? '',
                  r.endStationName ?? '',
                  ...r.stops.map((st) => st.name),
                ].any((v) => v.toLowerCase().contains(q));
              }).toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setSheetState(() => query = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: informative
                            ? 'Search by route, place or stop name'
                            : 'Search routes',
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: routes.isEmpty
                        ? const Center(child: Text('No matching routes'))
                        : ListView.builder(
                            itemCount: routes.length,
                            itemBuilder: (context, i) {
                              final r = routes[i];
                              final color = _routeColor(r);
                              final selected = s.selectedRouteCodes.contains(
                                r.routeCode,
                              );
                              final routeName = _routeDescriptiveName(r);
                              return ListTile(
                                onTap: () => ctrl.toggleRoute(r.routeCode),
                                leading: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _routeLabel(r),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _readableText(color),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  routeName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: informative
                                    ? Text(
                                        [
                                          'Route ${_routeLabel(r)}',
                                          '${r.stops.length} stops',
                                          if (r.fare != null)
                                            'Fare MVR ${r.fare!.toStringAsFixed(r.fare! % 1 == 0 ? 0 : 2)}',
                                        ].join(' · '),
                                      )
                                    : null,
                                trailing: Checkbox(
                                  value: selected,
                                  onChanged: (_) =>
                                      ctrl.toggleRoute(r.routeCode),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsContent({
    required BuildContext context,
    required MapState state,
    required BusRoute? primaryRoute,
    required List<BusRoute> selectedRoutes,
    required BusLocation? selectedBus,
    required Map<String, List<BusRoute>> stopsByCode,
  }) {
    final selectedStop = _selectedStop;
    if (selectedStop != null) {
      return _buildStopCard(
        context,
        selectedStop,
        stopsByCode[selectedStop.code] ?? const [],
        state.stopEtas[selectedStop.code] ?? const [],
      );
    }
    if (selectedBus != null) {
      return _buildBusCard(context, selectedBus, state.routes);
    }
    if (primaryRoute != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedRoutes.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final route in selectedRoutes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('details-route:${route.routeCode}'),
                        selected: route.routeCode == primaryRoute.routeCode,
                        label: Text(_routeLabel(route)),
                        tooltip: _routeDescriptiveName(route),
                        onSelected: (_) {
                          if (route.routeCode == primaryRoute.routeCode) return;
                          setState(() {
                            _detailsRouteCode = route.routeCode;
                            _routeStopSearch = '';
                          });
                          unawaited(
                            ref
                                .read(mapControllerProvider.notifier)
                                .loadScheduleForRoute(route),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          KeyedSubtree(
            key: ValueKey('route-details:${primaryRoute.routeCode}'),
            child: _buildRouteCard(context, primaryRoute),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
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
                    _routeDescriptiveName(route),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${route.stops.length} stops · ${route.areaName}${route.fare != null ? ' · MVR ${route.fare!.toStringAsFixed(route.fare! % 1 == 0 ? 0 : 2)}' : ''}',
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
        if (routes.any((route) {
          final status = viewState.resourceStatuses['eta:${route.routeCode}'];
          return status != null &&
              (status.stale ||
                  (status.fetchedAt != null &&
                      DateTime.now().difference(status.fetchedAt!) >=
                          const Duration(seconds: 60)));
        }))
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Showing last known arrival estimates · Refreshing when connected',
            ),
          ),

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
                ref.read(mapControllerProvider.notifier).setViewedEtaRoutes({});
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
                    ref.watch(uiDetailLevelProvider) ==
                            UiDetailLevel.informative
                        ? '${_routeLabel(r)} · ${_routeDescriptiveName(r)}'
                        : _routeLabel(r),
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

  String _liveAgeLabel(MapState state) {
    final times = state.resourceStatuses.entries
        .where(
          (e) =>
              e.key.startsWith('live:') &&
              state.selectedRouteCodes.contains(e.key.substring(5)),
        )
        .map((e) => e.value.fetchedAt)
        .whereType<DateTime>()
        .where((t) => t.millisecondsSinceEpoch > 0)
        .toList();
    if (times.isEmpty) return 'Live positions unavailable · Retrying';
    final oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
    final seconds = DateTime.now().difference(oldest).inSeconds;
    final age = seconds < 60
        ? '$seconds seconds ago'
        : '${seconds ~/ 60} minutes ago';
    return 'Showing last known positions · Updated $age';
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
            if (route != null &&
                ref.watch(uiDetailLevelProvider) == UiDetailLevel.informative)
              Text(
                'Route ${_routeLabel(route)}: ${_routeDescriptiveName(route)}',
                style: Theme.of(context).textTheme.bodyMedium,
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
