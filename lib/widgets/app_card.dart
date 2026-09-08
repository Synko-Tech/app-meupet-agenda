import 'package:flutter/material.dart';

import '../app/app_brand_colors.dart';
import '../app/app_elevation.dart';

enum AppCardVariant {
  /// Default surface card with a subtle border.
  standard,

  /// Tinted surface for highlighted info (brand mint).
  highlighted,

  /// Interactive card with ink ripple and optional trailing affordance.
  interactive,
}

/// Consistent card with themed surface, radius and optional interaction.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.variant = AppCardVariant.standard,
    this.elevated = false,
    this.onTap,
    this.trailing,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final AppCardVariant variant;

  /// Lifts the card with an [AppElevation.card] shadow.
  final bool elevated;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).extension<AppBrandColors>()!;
    final scheme = Theme.of(context).colorScheme;

    final Color background = switch (variant) {
      AppCardVariant.standard => scheme.surface,
      AppCardVariant.highlighted => brand.mint,
      AppCardVariant.interactive => scheme.surface,
    };

    final Widget content = trailing == null
        ? Padding(padding: padding, child: child)
        : Padding(
            padding: padding,
            child: Row(
              children: [
                Expanded(child: child),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          );

    return Card(
      elevation: elevated ? AppElevation.card : AppElevation.none,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      color: background,
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
