/// 1021 T-R1 (2) — the icon on each 小讀本 row in 讀少少.
///
/// `manifest.json` names a Material Icons glyph (`"icon": "science"`).
/// Flutter cannot look an icon up by name at run time (and a release build
/// keeps only the glyphs the code names), so the App has this fixed map:
/// the 14 names of readers-1021.zip.  Any other name, or none → the
/// default book.  tool/check_reader_html.js lists the same names
/// (KNOWN_ICONS) and notes an unknown one.
library;

import 'package:flutter/material.dart';

/// The default when the manifest names no icon, or one not in [kReaderIcons].
const IconData kReaderDefaultIcon = Icons.auto_stories_outlined;

const Map<String, IconData> kReaderIcons = {
  'help_outline': Icons.help_outline,
  'self_improvement': Icons.self_improvement,
  'tune': Icons.tune,
  'favorite_border': Icons.favorite_border,
  'science': Icons.science,
  'stairs': Icons.stairs,
  'family_restroom': Icons.family_restroom,
  'psychology': Icons.psychology,
  'videocam': Icons.videocam,
  'directions_walk': Icons.directions_walk,
  'local_florist': Icons.local_florist,
  'location_city': Icons.location_city,
  'support_agent': Icons.support_agent,
  'smartphone': Icons.smartphone,
};

/// The icon for a manifest `icon` name.
IconData readerIconFor(String? name) =>
    (name == null ? null : kReaderIcons[name]) ?? kReaderDefaultIcon;
