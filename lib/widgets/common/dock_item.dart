import 'package:flutter/widgets.dart';

/// Dock item data class — extracted from liquid_dock.dart to avoid
/// pulling liquid_glass_easy GPU shaders into the dock tree.
class DockItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}