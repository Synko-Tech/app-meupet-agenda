import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/business_model.dart';
import '../../repositories/business_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/async_state_view.dart';
import 'business_detail_screen.dart';

/// Lista publica de pet shops ativos. Permite ao cliente logado buscar e
/// descobrir estabelecimentos cadastrados (nome e cidade).
class BusinessListScreen extends StatefulWidget {
  const BusinessListScreen({super.key});

  @override
  State<BusinessListScreen> createState() => _BusinessListScreenState();
}

class _BusinessListScreenState extends State<BusinessListScreen> {
  Key _streamKey = UniqueKey();
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<BusinessRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Pet shops')),
      body: SafeArea(
        child: AppPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                title: 'Encontre um pet shop',
                subtitle: 'Estabelecimentos cadastrados na plataforma',
              ),
              AppTextField(
                key: const Key('business_list_search_field'),
                label: 'Buscar por nome ou cidade',
                prefixIcon: const Icon(Icons.search),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<BusinessModel>>(
                key: _streamKey,
                stream: repository.publicBusinessesStream(),
                builder: (context, snapshot) => AsyncStateView<List<BusinessModel>>(
                  snapshot: snapshot,
                  emptyTitle: 'Nenhum pet shop cadastrado',
                  emptyMessage:
                      'Ainda nao ha estabelecimentos cadastrados. Volte em breve.',
                  emptyIcon: Icons.storefront_outlined,
                  errorMessage:
                      'Nao foi possivel carregar os pet shops. Verifique sua conexao.',
                  onRetry: () => setState(() => _streamKey = UniqueKey()),
                  builder: (context, businesses) {
                    final filtered = _filter(businesses);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text('Nenhum pet shop encontrado.'),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final business in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BusinessListTile(
                              business: business,
                              onTap: () => _openDetails(context, business),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<BusinessModel> _filter(List<BusinessModel> businesses) {
    if (_query.isEmpty) {
      return businesses;
    }
    final query = _normalize(_query);
    return businesses.where((business) {
      final name = _normalize(business.name);
      final city = _normalize(business.address?.city ?? '');
      return name.contains(query) || city.contains(query);
    }).toList();
  }

  static String _normalize(String value) {
    return value.toLowerCase().trim();
  }

  void _openDetails(BuildContext context, BusinessModel business) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessDetailScreen(business: business),
      ),
    );
  }
}

class _BusinessListTile extends StatelessWidget {
  const _BusinessListTile({required this.business, required this.onTap});

  final BusinessModel business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final city = business.address?.city ?? '';
    final state = business.address?.state ?? '';

    return AppCard(
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.storefront_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(business.name, style: theme.textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (business.description?.isNotEmpty ?? false)
              Text(
                business.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (city.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14),
                    const SizedBox(width: 4),
                    Text('$city${state.isNotEmpty ? ' - $state' : ''}'),
                  ],
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
