import 'package:flutter/material.dart';

class LayerToggleChip extends StatelessWidget {
  const LayerToggleChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      selectedColor: scheme.primaryContainer,
      labelPadding: const EdgeInsetsDirectional.only(start: 0, end: 2),
      avatar: Icon(
        icon,
        size: 17,
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}
