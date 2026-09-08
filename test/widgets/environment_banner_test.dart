import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/widgets/environment_banner.dart';

void main() {
  group('EnvironmentBanner', () {
    testWidgets('mostra o selo LOCAL quando habilitado', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: EnvironmentBanner(enabled: true)),
        ),
      );

      final banner = tester.widget<Banner>(find.byType(Banner));
      expect(banner.message, 'LOCAL');
      expect(banner.location, BannerLocation.topStart);
    });

    testWidgets('nao mostra nada quando desabilitado', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: EnvironmentBanner(enabled: false)),
        ),
      );

      expect(find.byType(Banner), findsNothing);
    });
  });
}
