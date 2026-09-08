import 'package:flutter/material.dart';

/// Corner radius scale for the MeuPet Agenda brand.
///
/// Use these tokens instead of ad-hoc `BorderRadius.circular(...)` values.
/// Mapping: inputs/chips use [sm]/[md], cards use [lg], dialogs use [xl],
/// bottom sheets use [full].
abstract final class AppRadius {
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 24;

  static const BorderRadius xsRadius = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));

  static const BorderRadius fullTopRadius = BorderRadius.vertical(
    top: Radius.circular(full),
  );

  static BorderRadius of(double radius) => BorderRadius.circular(radius);
}
