import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/adaptive_scaffold.dart';

const destinations = [
  AdaptiveDestination(
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  AdaptiveDestination(
    label: 'Agendar',
    icon: Icons.event_available_outlined,
    selectedIcon: Icons.event_available,
  ),
];

void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdaptiveScaffold(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          body: const Text('conteudo'),
        ),
      ),
    );
  }

  group('AdaptiveScaffold', () {
    testWidgets('compact width uses bottom NavigationBar', (tester) async {
      await pump(tester, 360);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('conteudo'), findsOneWidget);
    });

    testWidgets('tablet width uses NavigationRail', (tester) async {
      await pump(tester, 840);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('conteudo'), findsOneWidget);
    });

    testWidgets('destinations appear in both layouts', (tester) async {
      await pump(tester, 360);
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Agendar'), findsOneWidget);

      tester.view.physicalSize = const Size(840, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Agendar'), findsOneWidget);
    });
  });
}
