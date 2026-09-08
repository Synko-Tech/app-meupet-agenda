import 'package:flutter/material.dart';

/// Semantic color tokens for the MeuPet Agenda brand.
///
/// Screens must consume colors through the theme (`Theme.of(context)` and
/// `AppBrandColors`) instead of raw hex values. The legacy static palette in
/// [AppTheme] remains as a compatibility shim while screens migrate.
class AppSemanticColors {
  AppSemanticColors._();

  // --- Light palette ---
  // Primary is tuned for WCAG AA (>= 4.5:1) against white foreground text.
  static const Color primary = Color(0xFF107E78);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFD2EEE9);
  static const Color onPrimaryContainer = Color(0xFF063B38);
  static const Color secondary = Color(0xFF33434A);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF101826);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color coral = Color(0xFFEF7D6C);
  static const Color onCoral = Color(0xFF40130C);
  static const Color coralContainer = Color(0xFFFFE3DC);
  static const Color mint = Color(0xFFDCEFE6);
  static const Color cream = Color(0xFFFBF6EC);
  static const Color background = Color(0xFFF7F9F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F4F0);
  static const Color text = Color(0xFF0B1A18);
  static const Color muted = Color(0xFF4E645E);
  static const Color border = Color(0xFFD9E3DC);
  static const Color success = Color(0xFF1E8E5A);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFD8F2E3);
  static const Color onSuccessContainer = Color(0xFF0B3D24);
  static const Color warning = Color(0xFFB97A0A);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFBE9C8);
  static const Color onWarningContainer = Color(0xFF492F02);
  static const Color danger = Color(0xFFC93A32);
  static const Color onDanger = Color(0xFFFFFFFF);
  static const Color dangerContainer = Color(0xFFFADCD9);
  static const Color onDangerContainer = Color(0xFF5C140E);
  static const Color info = Color(0xFF2B6CB0);
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFFD8E9F8);
  static const Color onInfoContainer = Color(0xFF0B2F52);

  // --- Dark palette ---
  static const Color darkBackground = Color(0xFF0E1412);
  static const Color darkSurface = Color(0xFF161D1A);
  static const Color darkSurfaceMuted = Color(0xFF1D2622);
  static const Color darkPrimary = Color(0xFF3EC3BA);
  static const Color darkOnPrimary = Color(0xFF04302D);
  static const Color darkPrimaryContainer = Color(0xFF0E4A45);
  static const Color darkOnPrimaryContainer = Color(0xFFC0F0EB);
  static const Color darkNavy = Color(0xFF0B111B);
  static const Color darkOnNavy = Color(0xFFFFFFFF);
  static const Color darkCoral = Color(0xFFF29588);
  static const Color darkOnCoral = Color(0xFF40130C);
  static const Color darkCoralContainer = Color(0xFF5A2A22);
  static const Color darkMint = Color(0xFF173C31);
  static const Color darkCream = Color(0xFF26221A);
  static const Color darkText = Color(0xFFE3ECE7);
  static const Color darkMuted = Color(0xFF9CB1A8);
  static const Color darkBorder = Color(0xFF2A352F);
  static const Color darkSuccess = Color(0xFF55C892);
  static const Color darkOnSuccess = Color(0xFF06301C);
  static const Color darkSuccessContainer = Color(0xFF1C5437);
  static const Color darkOnSuccessContainer = Color(0xFFB9E8CC);
  static const Color darkWarning = Color(0xFFE0B04E);
  static const Color darkOnWarning = Color(0xFF3A2A02);
  static const Color darkWarningContainer = Color(0xFF5C4309);
  static const Color darkOnWarningContainer = Color(0xFFF5DCA2);
  static const Color darkDanger = Color(0xFFE5726B);
  static const Color darkOnDanger = Color(0xFF4A110C);
  static const Color darkDangerContainer = Color(0xFF66221C);
  static const Color darkOnDangerContainer = Color(0xFFF9C7C2);
  static const Color darkInfo = Color(0xFF7FB0E8);
  static const Color darkOnInfo = Color(0xFF0A2540);
  static const Color darkInfoContainer = Color(0xFF1F4166);
  static const Color darkOnInfoContainer = Color(0xFFC6DDF4);
}
