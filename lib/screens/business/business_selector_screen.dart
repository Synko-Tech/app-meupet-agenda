import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/business_context_controller.dart';
import '../../models/business_membership.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';
import 'create_business_screen.dart';

/// Tela de selecao da loja ativa. O usuario ve apenas as lojas em que tem
/// membership (projecao `users/{uid}/businessMemberships`). Sem membership,
/// o onboarding segue para a criacao da primeira loja.
class BusinessSelectorScreen extends StatelessWidget {
  const BusinessSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final businessContext = context.watch<BusinessContextController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Selecionar loja')),
      body: SafeArea(
        child: AppPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                title: 'Suas lojas',
                subtitle: 'Escolha a loja que deseja acessar',
              ),
              if (businessContext.memberships.isEmpty)
                EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Nenhuma loja',
                  message: 'Crie sua primeira loja para comecar a usar o app.',
                  action: AppButton(
                    label: 'Criar loja',
                    icon: Icons.add_business_outlined,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateBusinessScreen(),
                      ),
                    ),
                  ),
                )
              else
                for (final membership in businessContext.memberships)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BusinessTile(
                      membership: membership,
                      isActive:
                          membership.businessId ==
                          businessContext.activeBusinessId,
                      onTap: membership.isActive
                          ? () => _select(context, membership)
                          : null,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    BusinessMembership membership,
  ) async {
    final controller = context.read<BusinessContextController>();
    await controller.selectBusiness(membership.businessId);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.membership,
    required this.isActive,
    required this.onTap,
  });

  final BusinessMembership membership;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.storefront_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          membership.businessName.isEmpty ? 'Loja' : membership.businessName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(membership.role.label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              const StatusBadge(
                label: 'Ativa',
                variant: StatusBadgeVariant.success,
              )
            else
              const Icon(Icons.chevron_right),
          ],
        ),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
