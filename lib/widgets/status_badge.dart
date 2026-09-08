import 'package:flutter/material.dart';

import '../app/app_brand_colors.dart';
import '../app/app_radius.dart';

/// Semantic tone of a [StatusBadge]. Prefer these variants over raw colors:
/// they pair theme containers with high-contrast foregrounds (AA >= 4.5:1).
enum StatusBadgeVariant {
  /// Positive state (paid, active, available).
  success,

  /// Attention state (pending, scheduled).
  warning,

  /// Negative state (canceled, failed).
  danger,

  /// Informational state (refunded, in progress).
  info,

  /// Neutral/muted state.
  neutral,
}

/// Pill-shaped status indicator. Color is always paired with a label (and
/// optionally an icon) so status is never conveyed by color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.variant = StatusBadgeVariant.success,
    this.color,
    this.icon,
  });

  final String label;
  final StatusBadgeVariant variant;

  /// Custom accent color. When provided it overrides [variant] with the
  /// legacy tinted style; prefer semantic variants for guaranteed contrast.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).extension<AppBrandColors>()!;

    var background = switch (variant) {
      StatusBadgeVariant.success => brand.successContainer,
      StatusBadgeVariant.warning => brand.warningContainer,
      StatusBadgeVariant.danger => brand.dangerContainer,
      StatusBadgeVariant.info => brand.infoContainer,
      StatusBadgeVariant.neutral => brand.surfaceMuted,
    };
    var foreground = switch (variant) {
      StatusBadgeVariant.success => brand.onSuccessContainer,
      StatusBadgeVariant.warning => brand.onWarningContainer,
      StatusBadgeVariant.danger => brand.onDangerContainer,
      StatusBadgeVariant.info => brand.onInfoContainer,
      StatusBadgeVariant.neutral => brand.muted,
    };

    final custom = color;
    if (custom != null) {
      background = custom.withValues(alpha: 0.14);
      foreground = custom;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
