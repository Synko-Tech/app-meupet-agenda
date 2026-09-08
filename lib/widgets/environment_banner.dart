import 'package:flutter/material.dart';

import '../app/firebase_emulators.dart';

/// Selo discreto indicando que o app roda contra a suite local de emuladores
/// Firebase. Visivel apenas quando [enabled] (default: ambiente de emulador),
/// para que ninguem confunda dados de desenvolvimento com producao.
class EnvironmentBanner extends StatelessWidget {
  const EnvironmentBanner({super.key, this.enabled = kUseFirebaseEmulators});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const SizedBox.shrink();
    }
    return const Banner(message: 'LOCAL', location: BannerLocation.topStart);
  }
}
