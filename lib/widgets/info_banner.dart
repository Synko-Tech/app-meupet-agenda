import 'package:flutter/material.dart';

import '../app/app_brand_colors.dart';

enum InfoBannerVariant { info, success, warning, danger }

/// Tinted informational banner with icon, optional title/message and action.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    this.title,
    required this.message,
    this.variant = InfoBannerVariant.info,
    this.icon,
    this.action,
  });

  final String? title;
  final String message;
  final InfoBannerVariant variant;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).extension<AppBrandColors>()!;
    final (Color color, IconData fallbackIcon) = switch (variant) {
      InfoBannerVariant.info => (brand.info, Icons.info_outline),
      InfoBannerVariant.success => (brand.success, Icons.check_circle_outline),
      InfoBannerVariant.warning => (
        brand.warning,
        Icons.warning_amber_outlined,
      ),
      InfoBannerVariant.danger => (brand.danger, Icons.error_outline),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallbackIcon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
