import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/app_page.dart';
import 'package:meupet_agenda_app/widgets/brand_mark.dart';
import 'package:meupet_agenda_app/widgets/empty_state.dart';
import 'package:meupet_agenda_app/widgets/info_banner.dart';
import 'package:meupet_agenda_app/widgets/status_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('PageHeader', () {
    testWidgets('renders title, subtitle and trailing', (tester) async {
      await pump(
        tester,
        const PageHeader(
          title: 'Perfil',
          subtitle: 'Dados da conta',
          trailing: Icon(Icons.person),
        ),
      );
      expect(find.text('Perfil'), findsOneWidget);
      expect(find.text('Dados da conta'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('SectionHeader', () {
    testWidgets('renders title and optional action', (tester) async {
      await pump(
        tester,
        const SectionHeader(title: 'Servicos', action: Icon(Icons.add)),
      );
      expect(find.text('Servicos'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders icon, title, message and action', (tester) async {
      await pump(
        tester,
        EmptyState(
          title: 'Sem pacotes',
          message: 'Compre um pacote.',
          icon: Icons.card_membership_outlined,
          action: TextButton(onPressed: () {}, child: const Text('Comprar')),
        ),
      );
      expect(find.text('Sem pacotes'), findsOneWidget);
      expect(find.text('Comprar'), findsOneWidget);
    });
  });

  group('StatusBadge', () {
    testWidgets('renders label with optional icon', (tester) async {
      await pump(
        tester,
        const StatusBadge(label: 'Ativo', icon: Icons.check_circle),
      );
      expect(find.text('Ativo'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('InfoBanner', () {
    testWidgets('renders message and variant icon', (tester) async {
      await pump(
        tester,
        const InfoBanner(
          variant: InfoBannerVariant.warning,
          message: 'Pagamento pendente.',
        ),
      );
      expect(find.text('Pagamento pendente.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });
  });

  group('BrandMark', () {
    testWidgets('renders paw mark and wordmark', (tester) async {
      await pump(tester, const BrandWordmark());
      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.text('MeuPet Agenda'), findsOneWidget);
    });
  });
}
