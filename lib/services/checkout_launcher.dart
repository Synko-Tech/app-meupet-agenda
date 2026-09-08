import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens an external checkout (Mercado Pago Checkout Pro) in the device
/// browser. Wrapped so widget tests can inject a fake.
abstract interface class CheckoutLauncher {
  /// Returns false when the URL could not be opened.
  Future<bool> open(Uri uri);
}

class UrlLauncherCheckout implements CheckoutLauncher {
  const UrlLauncherCheckout();

  @override
  Future<bool> open(Uri uri) async {
    if (!await canLaunchUrl(uri)) {
      return false;
    }
    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }
}

@visibleForTesting
class FakeCheckoutLauncher implements CheckoutLauncher {
  FakeCheckoutLauncher({this.shouldOpen = true});

  bool shouldOpen;
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return shouldOpen;
  }
}
