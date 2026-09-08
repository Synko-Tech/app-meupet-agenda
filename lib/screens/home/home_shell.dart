import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_brand_colors.dart';
import '../../app/app_typography.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/app_user.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../account/account_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../appointments/appointment_screen.dart';
import '../business/business_selector_screen.dart';
import '../calendar/admin_calendar_screen.dart';
import '../customers/customers_screen.dart';
import '../packages/packages_screen.dart';
import '../payments/payment_screen.dart';
import 'client_home_screen.dart';
import 'home_destination.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  Widget? _adminScreenOverride;
  String? _adminScreenTitle;

  /// Destinations are built on demand (lazy) so hidden tabs do not subscribe
  /// to streams before they are visited. Once built, the widget stays cached
  /// so switching tabs preserves its state (IndexedStack keeps them alive).
  final Map<int, Widget> _clientScreens = {};
  final Map<int, Widget> _adminScreens = {};
  final Set<int> _visitedClient = {};
  final Set<int> _visitedAdmin = {};
  String _clientTabsSignature = '';

  Widget _lazy(
    Map<int, Widget> cache,
    Set<int> visited,
    int index,
    Widget Function() build,
  ) {
    visited.add(index);
    return cache.putIfAbsent(index, build);
  }

  /// Fills [out] with one widget per tab: cached screens for visited tabs,
  /// the current tab (built on demand) and shrink placeholders elsewhere.
  void _fillScreens(
    List<Widget> out,
    Map<int, Widget> cache,
    Set<int> visited,
    int count,
    Widget Function(int index) build,
  ) {
    for (var index = 0; index < count; index++) {
      if (index == _selectedIndex || visited.contains(index)) {
        out.add(_lazy(cache, visited, index, () => build(index)));
      } else {
        out.add(const SizedBox.shrink());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.isSuperAdmin) {
      return _buildSuperAdminShell(context);
    }

    return _buildClientShell(context, auth);
  }

  Widget _buildClientShell(BuildContext context, AuthController auth) {
    final isStaff = auth.isStaff;
    final canAccessAdminPanel = auth.canAccessAdminPanel;
    final canManageUsers = auth.profile?.canManageUsers ?? false;
    final tabs = homeTabsFor(
      isStaff: isStaff,
      canAccessAdminPanel: canAccessAdminPanel,
      canManageUsers: canManageUsers,
    );

    final signature = tabs.map((tab) => tab.label).join('|');
    if (signature != _clientTabsSignature) {
      _clientTabsSignature = signature;
      _clientScreens.clear();
      _visitedClient.clear();
    }

    final screens = <Widget>[];
    _fillScreens(screens, _clientScreens, _visitedClient, tabs.length, (index) {
      return switch (index) {
        0 => ClientHomeScreen(
          onOpenAgenda: () => _select(1),
          onOpenPackages: () => _select(2),
        ),
        1 => const AppointmentScreen(),
        2 => const PackagesScreen(),
        3 when isStaff => const PaymentScreen(),
        4 when canAccessAdminPanel => AdminDashboardScreen(
          onOpenAgenda: () => _select(1),
        ),
        5 when canManageUsers => const CustomersScreen(),
        _ => const AccountScreen(),
      };
    });
    if (_selectedIndex >= screens.length) {
      _selectedIndex = 0;
    }

    return AdaptiveScaffold(
      topBar: _HomeTopBar(
        title: tabs[_selectedIndex].title,
        profile: auth.profile,
        businessName: context
            .watch<BusinessContextController>()
            .activeMembership
            ?.businessName,
        onSwitchBusiness: () => _openBusinessSelector(context),
      ),
      destinations: [
        for (final tab in tabs)
          AdaptiveDestination(
            label: tab.label,
            icon: tab.icon,
            selectedIcon: tab.selectedIcon,
          ),
      ],
      selectedIndex: _selectedIndex,
      onDestinationSelected: _select,
      body: IndexedStack(index: _selectedIndex, children: screens),
    );
  }

  Widget _buildSuperAdminShell(BuildContext context) {
    final adminTabs = [
      const _AdminTab(
        label: 'Dashboard',
        title: 'Painel administrativo',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      const _AdminTab(
        label: 'Agenda',
        title: 'Agendamentos',
        icon: Icons.event_available_outlined,
        selectedIcon: Icons.event_available,
      ),
      const _AdminTab(
        label: 'Calendario',
        title: 'Calendario',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
      ),
      const _AdminTab(
        label: 'Pagamento',
        title: 'Pagamento',
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
      ),
      const _AdminTab(
        label: 'Clientes',
        title: 'Clientes',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
      ),
      const _AdminTab(
        label: 'Perfil',
        title: 'Perfil',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
      ),
    ];

    if (_selectedIndex >= adminTabs.length) {
      _selectedIndex = 0;
    }

    final adminScreens = <Widget>[];
    _fillScreens(adminScreens, _adminScreens, _visitedAdmin, adminTabs.length, (
      index,
    ) {
      return switch (index) {
        0 => AdminDashboardScreen(onOpenAgenda: () => _selectAdminTab(1)),
        1 => const AppointmentScreen(),
        2 => const AdminCalendarScreen(),
        3 => const PaymentScreen(),
        4 => const CustomersScreen(),
        _ => const AccountScreen(),
      };
    });
    final currentTitle = _adminScreenTitle ?? adminTabs[_selectedIndex].title;
    final selectedNavigationIndex = _adminScreenOverride == null
        ? _selectedIndex
        : adminTabs.length - 1;

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 72,
      drawer: _AdminDrawer(
        onSelectTab: _selectAdminTab,
        onOpenScreen: _openAdminScreen,
      ),
      body: Column(
        children: [
          Container(
            height: 52,
            color: context.brand.navy,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Menu administrativo',
                    onPressed: _openDrawer,
                    icon: Icon(Icons.menu, color: context.brand.onNavy),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.brand.onNavy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Super admin',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sair',
                    onPressed: () => context.read<AuthController>().signOut(),
                    icon: const Icon(
                      Icons.logout,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child:
                  _adminScreenOverride ??
                  IndexedStack(index: _selectedIndex, children: adminScreens),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedNavigationIndex,
        onDestinationSelected: _selectAdminTab,
        destinations: [
          for (final tab in adminTabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  void _select(int index) {
    setState(() {
      _adminScreenOverride = null;
      _adminScreenTitle = null;
      _selectedIndex = index;
    });
  }

  void _selectAdminTab(int index) {
    setState(() {
      _adminScreenOverride = null;
      _adminScreenTitle = null;
      _selectedIndex = index;
    });
  }

  void _openAdminScreen(String title, Widget screen) {
    setState(() {
      _adminScreenTitle = title;
      _adminScreenOverride = screen;
    });
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openBusinessSelector(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BusinessSelectorScreen()));
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.title,
    required this.profile,
    this.businessName,
    this.onSwitchBusiness,
  });

  final String title;
  final AppUser? profile;
  final String? businessName;
  final VoidCallback? onSwitchBusiness;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final name = profile?.name ?? '';
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      color: brand.navy,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('home-topbar-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        color: brand.onNavy,
                        fontSize: 19,
                      ),
                    ),
                    if (businessName != null && businessName!.isNotEmpty)
                      Text(
                        businessName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: brand.onNavy.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (onSwitchBusiness != null)
                IconButton(
                  tooltip: 'Trocar loja',
                  onPressed: onSwitchBusiness,
                  icon: Icon(
                    Icons.storefront_outlined,
                    color: brand.onNavy,
                    size: 20,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: brand.onNavy.withValues(alpha: 0.24),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: brand.onNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTab {
  const _AdminTab({
    required this.label,
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({required this.onSelectTab, required this.onOpenScreen});

  final ValueChanged<int> onSelectTab;
  final void Function(String title, Widget screen) onOpenScreen;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              color: context.brand.navy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: context.brand.onNavy,
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Central administrativa',
                    style: TextStyle(
                      color: context.brand.onNavy,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Acesso completo do super admin',
                    style: TextStyle(
                      color: context.brand.onNavy.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            _AdminDrawerItem(
              icon: Icons.dashboard_outlined,
              title: 'Dashboard',
              subtitle: 'Resumo, servicos e pacotes',
              onTap: () => _closeAndSelect(context, 0),
            ),
            _AdminDrawerItem(
              icon: Icons.event_available_outlined,
              title: 'Agendamentos',
              subtitle: 'Criar, visualizar e cancelar horarios',
              onTap: () => _closeAndSelect(context, 1),
            ),
            _AdminDrawerItem(
              icon: Icons.calendar_month_outlined,
              title: 'Calendario',
              subtitle: 'Agenda administrativa por data',
              onTap: () => _closeAndSelect(context, 2),
            ),
            _AdminDrawerItem(
              icon: Icons.payments_outlined,
              title: 'Pagamentos',
              subtitle: 'Registros e status financeiros',
              onTap: () => _closeAndSelect(context, 3),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                'Gestao',
                style: TextStyle(
                  color: context.brand.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _AdminDrawerItem(
              icon: Icons.people_outline,
              title: 'Clientes',
              subtitle: 'Ativar, inativar e consultar clientes',
              onTap: () => _closeAndSelect(context, 4),
            ),
            _AdminDrawerItem(
              icon: Icons.badge_outlined,
              title: 'Servicos',
              subtitle: 'Cadastro no dashboard',
              onTap: () => _closeAndSelect(context, 0),
            ),
            _AdminDrawerItem(
              icon: Icons.card_membership_outlined,
              title: 'Pacotes',
              subtitle: 'Gestao no dashboard e compra no app',
              onTap: () => _closeAndSelect(context, 0),
            ),
            _AdminDrawerItem(
              icon: Icons.manage_accounts_outlined,
              title: 'Perfil',
              subtitle: 'Perfil, senha e troca de usuario',
              onTap: () => _closeAndSelect(context, 5),
            ),
          ],
        ),
      ),
    );
  }

  void _closeAndSelect(BuildContext context, int index) {
    Navigator.of(context).pop();
    onSelectTab(index);
  }
}

class _AdminDrawerItem extends StatelessWidget {
  const _AdminDrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 28,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
