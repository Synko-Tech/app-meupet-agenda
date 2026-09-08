import 'package:flutter/material.dart';

import '../app/app_breakpoints.dart';

/// A navigation destination shared between compact and expanded layouts.
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String? tooltip;
}

/// Adaptive navigation host: [NavigationBar] below 600 dp, [NavigationRail]
/// from 600 dp up. The [topBar] (with its own SafeArea handling) is placed
/// above the body; the body itself is always kept clear of the top inset.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.topBar,
    this.floatingActionButton,
    this.drawer,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? topBar;
  final Widget? floatingActionButton;
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    final isTablet = AppBreakpoints.isTablet(context);
    final theme = Theme.of(context);

    final rail = NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: true,
      leading: const SizedBox(height: 8),
      destinations: [
        for (final destination in destinations)
          NavigationRailDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
            label: Text(destination.label),
          ),
      ],
    );

    return Scaffold(
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      body: isTablet
          ? Row(
              children: [
                rail,
                VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                Expanded(
                  child: Column(
                    children: [
                      ?topBar,
                      Expanded(child: SafeArea(top: false, child: body)),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                ?topBar,
                Expanded(child: SafeArea(top: false, child: body)),
              ],
            ),
      bottomNavigationBar: isTablet
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(
                      destination.selectedIcon ?? destination.icon,
                    ),
                    label: destination.label,
                    tooltip: destination.tooltip ?? destination.label,
                  ),
              ],
            ),
    );
  }
}
