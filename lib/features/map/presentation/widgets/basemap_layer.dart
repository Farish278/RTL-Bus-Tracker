import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Both themes use the same keyless source and cached tile bytes. The dark
/// filter affects only the basemap, leaving transit overlays and UI unchanged.
class BasemapLayer extends StatelessWidget {
  const BasemapLayer({
    super.key,
    required this.isDark,
    required this.tileProvider,
  });
  final bool isDark;
  final TileProvider tileProvider;
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _identity = <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
  // Inverted luminance: pale land becomes charcoal, dark labels become light.
  // Keep alpha unchanged so the filter cannot obscure independent map layers.
  static const _dark = <double>[
    -.18071,
    -.60792,
    -.06137,
    0,
    229.5,
    -.18071,
    -.60792,
    -.06137,
    0,
    229.5,
    -.18071,
    -.60792,
    -.06137,
    0,
    229.5,
    0,
    0,
    0,
    1,
    0,
  ];
  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: ColorFilter.matrix(isDark ? _dark : _identity),
    child: TileLayer(
      urlTemplate: tileUrl,
      tileProvider: tileProvider,
      userAgentPackageName: 'com.farish278.rtl_bus_tracker',
    ),
  );
}
