import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';
import 'customer_details_screen.dart';

enum _CustomerFilter { all, active, inactive }

/// Admin list of every client (active and inactive) with local search and
/// status filtering. Replaces the six-client preview that used to live on the
/// dashboard.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  _CustomerFilter _filter = _CustomerFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppUser> _applyFilter(List<AppUser> clients) {
    final query = _query.trim().toLowerCase();
    return clients.where((client) {
      final matchesFilter = switch (_filter) {
        _CustomerFilter.all => true,
        _CustomerFilter.active => client.isActive,
        _CustomerFilter.inactive => !client.isActive,
      };
      if (!matchesFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return client.name.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query) ||
          (client.phone ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<UserRepository>();
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Clientes',
            subtitle: 'Ativos e inativos do estabelecimento',
          ),
          AppTextField(
            key: const ValueKey('customer-search'),
            label: 'Buscar',
            hintText: 'Nome, e-mail ou telefone',
            prefixIcon: const Icon(Icons.search),
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          _StatusFilterBar(
            filter: _filter,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AppUser>>(
            stream: repository.allClientsStream(),
            builder: (context, snapshot) {
              return AsyncStateView<List<AppUser>>(
                snapshot: snapshot,
                onRetry: () => setState(() {}),
                emptyTitle: 'Nenhum cliente',
                emptyMessage: 'Clientes cadastrados aparecerao aqui.',
                emptyIcon: Icons.people_outline,
                builder: (context, clients) {
                  final filtered = _applyFilter(clients);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${filtered.length} ${filtered.length == 1 ? 'resultado' : 'resultados'}',
                        key: const ValueKey('customer-count'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      if (filtered.isEmpty)
                        const EmptyFilteredState()
                      else
                        ...filtered.map(
                          (client) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              key: ValueKey('customer-card-${client.id}'),
                              variant: AppCardVariant.interactive,
                              onTap: () => _openDetails(client),
                              trailing: StatusBadge(
                                label: client.isActive ? 'Ativo' : 'Inativo',
                                variant: client.isActive
                                    ? StatusBadgeVariant.success
                                    : StatusBadgeVariant.warning,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    client.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(client.email),
                                  if (client.phone != null &&
                                      client.phone!.isNotEmpty)
                                    Text(client.phone!),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _openDetails(AppUser client) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailsScreen(clientId: client.id),
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.filter, required this.onChanged});

  final _CustomerFilter filter;
  final ValueChanged<_CustomerFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in const [
          (_CustomerFilter.all, 'Todos'),
          (_CustomerFilter.active, 'Ativos'),
          (_CustomerFilter.inactive, 'Inativos'),
        ])
          ChoiceChip(
            key: ValueKey('customer-filter-${entry.$1.name}'),
            label: Text(entry.$2),
            selected: filter == entry.$1,
            onSelected: (_) => onChanged(entry.$1),
          ),
      ],
    );
  }
}

class EmptyFilteredState extends StatelessWidget {
  const EmptyFilteredState({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off,
      title: 'Nenhum resultado',
      message: 'Tente ajustar a busca ou o filtro de status.',
    );
  }
}
