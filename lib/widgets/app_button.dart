import 'package:flutter/material.dart';

import '../app/app_brand_colors.dart';

enum AppButtonVariant {
  /// Filled with the primary color (default action).
  primary,

  /// Tinted with the brand primary container (secondary action).
  secondary,

  /// Quiet surface-toned button (tertiary action).
  tonal,

  /// Text-only button (inline action).
  text,

  /// Destructive action.
  destructive,
}

/// Full-width primary action with a consistent 48 px target, icon support and
/// an inline loading state that never changes the button size.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isSecondary = false,
    AppButtonVariant? variant,
    this.expand = true,
  }) : variant =
           variant ??
           (isSecondary
               ? AppButtonVariant.secondary
               : AppButtonVariant.primary);

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  /// Legacy flag: maps to [AppButtonVariant.secondary].
  final bool isSecondary;
  final AppButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<AppBrandColors>()!;

    final (Color background, Color foreground) = switch (variant) {
      AppButtonVariant.primary => (scheme.primary, scheme.onPrimary),
      AppButtonVariant.secondary => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      AppButtonVariant.tonal => (brand.surfaceMuted, scheme.onSurface),
      AppButtonVariant.text => (Colors.transparent, scheme.primary),
      AppButtonVariant.destructive => (scheme.error, scheme.onError),
    };

    Widget? leading;
    if (isLoading) {
      leading = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
      );
    } else if (icon != null) {
      leading = Icon(icon, size: 18);
    }

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 8)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    final onTap = isLoading ? null : onPressed;
    final button = switch (variant) {
      AppButtonVariant.text => TextButton(onPressed: onTap, child: child),
      AppButtonVariant.primary ||
      AppButtonVariant.secondary ||
      AppButtonVariant.tonal ||
      AppButtonVariant.destructive => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        ),
        child: child,
      ),
    };

    return SizedBox(
      width: expand ? double.infinity : null,
      height: 48,
      child: button,
    );
  }
}
