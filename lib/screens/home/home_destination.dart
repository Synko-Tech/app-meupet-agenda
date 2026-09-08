import 'package:flutter/material.dart';

/// A top-level destination of the client/staff shell.
class HomeTab {
  const HomeTab({
    required this.label,
    required this.title,
    required this.icon,
    this.selectedIcon,
  });

  final String label;
  final String title;
  final IconData icon;
  final IconData? selectedIcon;
}

/// Destination list per audience. Clients get the focused four-tab journey
/// (Inicio, Agendar, Pacotes, Conta); staff keeps payments and the panel;
/// user managers (admin and super admin) also get the independent Clientes
/// tab.
List<HomeTab> homeTabsFor({
  required bool isStaff,
  required bool canAccessAdminPanel,
  bool canManageUsers = false,
}) {
  return [
    const HomeTab(
      label: 'Inicio',
      title: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    const HomeTab(
      label: 'Agendar',
      title: 'Agendar',
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available,
    ),
    const HomeTab(
      label: 'Pacotes',
      title: 'Pacotes',
      icon: Icons.card_membership_outlined,
      selectedIcon: Icons.card_membership,
    ),
    if (isStaff)
      const HomeTab(
        label: 'Pagamento',
        title: 'Pagamento',
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
      ),
    if (canAccessAdminPanel)
      const HomeTab(
        label: 'Painel',
        title: 'Painel',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
    if (isStaff && canManageUsers)
      const HomeTab(
        label: 'Clientes',
        title: 'Clientes',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
      ),
    const HomeTab(
      label: 'Conta',
      title: 'Conta',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];
}
