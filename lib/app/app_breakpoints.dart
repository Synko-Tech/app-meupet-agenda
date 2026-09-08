import 'package:flutter/material.dart';

/// Breakpoint and layout constants for the adaptive layout.
class AppBreakpoints {
  AppBreakpoints._();

  /// Compact → medium threshold (Material 3): bottom navigation becomes a rail.
  static const double tablet = 600;

  /// Medium → expanded threshold: reserved for future desktop work.
  static const double desktop = 900;

  /// Maximum reading width for page content on large screens.
  static const double contentMaxWidth = 720;

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= tablet;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= desktop;
  }
}
