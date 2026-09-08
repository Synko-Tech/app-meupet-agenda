import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/screens/home/home_destination.dart';

void main() {
  group('homeTabsFor', () {
    test('client gets the focused four-tab journey', () {
      final tabs = homeTabsFor(isStaff: false, canAccessAdminPanel: false);
      expect(tabs.map((tab) => tab.label), [
        'Inicio',
        'Agendar',
        'Pacotes',
        'Conta',
      ]);
    });

    test('staff keeps payments and panel until Wave C', () {
      final tabs = homeTabsFor(isStaff: true, canAccessAdminPanel: true);
      expect(tabs.map((tab) => tab.label), [
        'Inicio',
        'Agendar',
        'Pacotes',
        'Pagamento',
        'Painel',
        'Conta',
      ]);
    });

    test('staff without panel access still sees payments', () {
      final tabs = homeTabsFor(isStaff: true, canAccessAdminPanel: false);
      expect(tabs.map((tab) => tab.label).contains('Pagamento'), isTrue);
      expect(tabs.map((tab) => tab.label).contains('Painel'), isFalse);
    });

    test('user managers get the Clientes tab', () {
      final tabs = homeTabsFor(
        isStaff: true,
        canAccessAdminPanel: true,
        canManageUsers: true,
      );
      expect(tabs.map((tab) => tab.label), [
        'Inicio',
        'Agendar',
        'Pacotes',
        'Pagamento',
        'Painel',
        'Clientes',
        'Conta',
      ]);
    });

    test('clients never see Clientes even when flagged', () {
      final tabs = homeTabsFor(
        isStaff: false,
        canAccessAdminPanel: false,
        canManageUsers: true,
      );
      expect(tabs.map((tab) => tab.label).contains('Clientes'), isFalse);
    });

    test('tabs carry title and selected icon', () {
      final tabs = homeTabsFor(isStaff: false, canAccessAdminPanel: false);
      final inicio = tabs.first;
      expect(inicio.title, 'Inicio');
      expect(inicio.selectedIcon, isNotNull);
      expect(inicio.icon, isNotNull);
    });
  });
}
