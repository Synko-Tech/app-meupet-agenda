/// Motion tokens. All interactions stay within the 150–250 ms window and
/// respect `MediaQuery.disableAnimations` (reduced motion).
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration pageTransition = Duration(milliseconds: 250);
}
