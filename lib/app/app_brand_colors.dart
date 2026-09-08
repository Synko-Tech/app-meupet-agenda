import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

/// Brand colors exposed through the theme as a [ThemeExtension].
///
/// Access via `Theme.of(context).extension<AppBrandColors>()!`.
@immutable
class AppBrandColors extends ThemeExtension<AppBrandColors> {
  const AppBrandColors({
    required this.navy,
    required this.onNavy,
    required this.coral,
    required this.onCoral,
    required this.coralContainer,
    required this.mint,
    required this.cream,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.muted,
    required this.surfaceMuted,
  });

  final Color navy;
  final Color onNavy;
  final Color coral;
  final Color onCoral;
  final Color coralContainer;
  final Color mint;
  final Color cream;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color muted;
  final Color surfaceMuted;

  static const AppBrandColors light = AppBrandColors(
    navy: AppSemanticColors.navy,
    onNavy: AppSemanticColors.onNavy,
    coral: AppSemanticColors.coral,
    onCoral: AppSemanticColors.onCoral,
    coralContainer: AppSemanticColors.coralContainer,
    mint: AppSemanticColors.mint,
    cream: AppSemanticColors.cream,
    success: AppSemanticColors.success,
    warning: AppSemanticColors.warning,
    danger: AppSemanticColors.danger,
    info: AppSemanticColors.info,
    successContainer: AppSemanticColors.successContainer,
    onSuccessContainer: AppSemanticColors.onSuccessContainer,
    warningContainer: AppSemanticColors.warningContainer,
    onWarningContainer: AppSemanticColors.onWarningContainer,
    dangerContainer: AppSemanticColors.dangerContainer,
    onDangerContainer: AppSemanticColors.onDangerContainer,
    infoContainer: AppSemanticColors.infoContainer,
    onInfoContainer: AppSemanticColors.onInfoContainer,
    muted: AppSemanticColors.muted,
    surfaceMuted: AppSemanticColors.surfaceMuted,
  );

  static const AppBrandColors dark = AppBrandColors(
    navy: AppSemanticColors.darkNavy,
    onNavy: AppSemanticColors.darkOnNavy,
    coral: AppSemanticColors.darkCoral,
    onCoral: AppSemanticColors.darkOnCoral,
    coralContainer: AppSemanticColors.darkCoralContainer,
    mint: AppSemanticColors.darkMint,
    cream: AppSemanticColors.darkCream,
    success: AppSemanticColors.darkSuccess,
    warning: AppSemanticColors.darkWarning,
    danger: AppSemanticColors.darkDanger,
    info: AppSemanticColors.darkInfo,
    successContainer: AppSemanticColors.darkSuccessContainer,
    onSuccessContainer: AppSemanticColors.darkOnSuccessContainer,
    warningContainer: AppSemanticColors.darkWarningContainer,
    onWarningContainer: AppSemanticColors.darkOnWarningContainer,
    dangerContainer: AppSemanticColors.darkDangerContainer,
    onDangerContainer: AppSemanticColors.darkOnDangerContainer,
    infoContainer: AppSemanticColors.darkInfoContainer,
    onInfoContainer: AppSemanticColors.darkOnInfoContainer,
    muted: AppSemanticColors.darkMuted,
    surfaceMuted: AppSemanticColors.darkSurfaceMuted,
  );

  @override
  AppBrandColors copyWith({
    Color? navy,
    Color? onNavy,
    Color? coral,
    Color? onCoral,
    Color? coralContainer,
    Color? mint,
    Color? cream,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? muted,
    Color? surfaceMuted,
  }) {
    return AppBrandColors(
      navy: navy ?? this.navy,
      onNavy: onNavy ?? this.onNavy,
      coral: coral ?? this.coral,
      onCoral: onCoral ?? this.onCoral,
      coralContainer: coralContainer ?? this.coralContainer,
      mint: mint ?? this.mint,
      cream: cream ?? this.cream,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      muted: muted ?? this.muted,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    );
  }

  @override
  AppBrandColors lerp(AppBrandColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppBrandColors(
      navy: Color.lerp(navy, other.navy, t)!,
      onNavy: Color.lerp(onNavy, other.onNavy, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      onCoral: Color.lerp(onCoral, other.onCoral, t)!,
      coralContainer: Color.lerp(coralContainer, other.coralContainer, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      cream: Color.lerp(cream, other.cream, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(
        onDangerContainer,
        other.onDangerContainer,
        t,
      )!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
    );
  }
}

extension AppBrandColorsX on BuildContext {
  AppBrandColors get brand => Theme.of(this).extension<AppBrandColors>()!;
}
