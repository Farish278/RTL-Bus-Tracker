import 'package:flutter/material.dart';

/// Keeps map details out of the way until explicitly opened.
class CollapsibleMapDetails extends StatefulWidget {
  const CollapsibleMapDetails({
    super.key,
    required this.selectionKey,
    required this.icon,
    required this.detailsBuilder,
    required this.overlaysBuilder,
    this.onOpened,
  });

  /// Called only when the user opens details, never during rebuilds or drags.
  final VoidCallback? onOpened;
  final Object? selectionKey;
  final IconData icon;
  final WidgetBuilder detailsBuilder;
  final List<Widget> Function(BuildContext context, double bottom)
  overlaysBuilder;

  @override
  State<CollapsibleMapDetails> createState() => _CollapsibleMapDetailsState();
}

class _CollapsibleMapDetailsState extends State<CollapsibleMapDetails> {
  bool _open = false;
  double _extent = 0.5;

  @override
  void didUpdateWidget(CollapsibleMapDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _open = false;
      _extent = 0.5;
    }
  }

  void _collapse() => setState(() {
    _open = false;
    _extent = 0.5;
  });

  @override
  Widget build(BuildContext context) {
    final hasDetails = widget.selectionKey != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottom = hasDetails
            ? (_open ? constraints.maxHeight * _extent : safeBottom + 72) + 12
            : safeBottom + 24;
        return Stack(
          children: [
            ...widget.overlaysBuilder(context, bottom),
            if (hasDetails && !_open)
              Positioned(
                left: 0,
                right: 0,
                bottom: safeBottom + 12,
                child: Center(
                  child: FilledButton.tonal(
                    key: const ValueKey('map-details-pill'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      elevation: 3,
                    ),
                    onPressed: () {
                      setState(() => _open = true);
                      widget.onOpened?.call();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 20),
                        const SizedBox(width: 8),
                        const Text('Details'),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_less_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            if (hasDetails && _open)
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  if (notification.depth != 0) return false;
                  final selection = widget.selectionKey;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted ||
                        !_open ||
                        selection != widget.selectionKey) {
                      return;
                    }
                    if (notification.extent <= notification.minExtent + 0.001) {
                      _collapse();
                    } else if ((_extent - notification.extent).abs() > 0.001) {
                      setState(() => _extent = notification.extent);
                    }
                  });
                  return false;
                },
                child: DraggableScrollableSheet(
                  key: ValueKey(widget.selectionKey),
                  minChildSize: 0.16,
                  initialChildSize: 0.5,
                  maxChildSize: 0.94,
                  snap: true,
                  snapSizes: const [0.5, 0.94],
                  snapAnimationDuration: MediaQuery.disableAnimationsOf(context)
                      ? const Duration(milliseconds: 1)
                      : const Duration(milliseconds: 180),
                  shouldCloseOnMinExtent: false,
                  builder: (context, scrollController) =>
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: Material(
                          elevation: 8,
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          clipBehavior: Clip.antiAlias,
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
                                      color: scheme.outlineVariant,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                widget.detailsBuilder(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}
