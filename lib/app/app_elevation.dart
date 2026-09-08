import 'package:flutter/material.dart';

/// Elevation scale and shadow helpers for the MeuPet Agenda brand.
///
/// Use [none] for flat surfaces, [card] for resting cards and [raised] for
/// interactive/elevated surfaces. Shadows are tone-aware: darker brightness
/// uses a stronger alpha so elevation stays visible on dark surfaces.
abstract final class AppElevation {
  static const double none = 0;
  static const double card = 2;
  static const double raised = 6;

  /// Material 3-style elevation shadows. Returns an empty list for [none].
  static List<BoxShadow> forLevel(
    double level, {
    required Brightness brightness,
  }) {
    if (level <= 0) return const [];
    final alpha = brightness == Brightness.dark ? 0.32 : 0.22;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: alpha),
        blurRadius: 4 + level * 2,
        offset: Offset(0, level / 2),
        spreadRadius: 0,
      ),
    ];
  }

  static List<BoxShadow> cardShadow(BuildContext context) =>
      forLevel(card, brightness: Theme.of(context).brightness);

  static List<BoxShadow> raisedShadow(BuildContext context) =>
      forLevel(raised, brightness: Theme.of(context).brightness);
}
