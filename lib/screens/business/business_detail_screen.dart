import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/business_context_controller.dart';
import '../../models/business_model.dart';
import '../../models/postal_address.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_page.dart';
import '../../widgets/status_badge.dart';

/// Detalhes publicos de um pet shop e acao de entrada (join) para o cliente
/// logado. Apos entrar, a loja e selecionada como ativa e o shell passa a
/// usar aquele contexto.
class BusinessDetailScreen extends StatelessWidget {
  const BusinessDetailScreen({super.key, required this.business});

  final BusinessModel business;

  @override
  Widget build(BuildContext context) {
    final businessContext = context.watch<BusinessContextController>();
    final alreadyMember = businessContext.memberships.any(
      (membership) => membership.businessId == business.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pet shop')),
      body: SafeArea(
        child: AppPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: business.name,
                subtitle: business.description?.isNotEmpty ?? false
                    ? business.description
                    : null,
                trailing: StatusBadge(label: business.status.label),
              ),
              if (business.address != null) ...[
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  text: _formatAddress(business.address!),
                ),
              ],
              if (business.phone?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.phone_outlined, text: business.phone!),
              ],
              if (business.cnpjMasked != null) ...[
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.badge_outlined, text: business.cnpjMasked!),
              ],
              const SizedBox(height: 20),
              AppButton(
                key: const Key('business_detail_join_button'),
                label: alreadyMember
                    ? 'Voce ja faz parte deste pet shop'
                    : 'Entrar neste pet shop',
                icon: alreadyMember
                    ? Icons.check_circle_outline
                    : Icons.storefront_outlined,
                isLoading: businessContext.isBusy,
                onPressed: alreadyMember
                    ? null
                    : () => _join(context, businessContext),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAddress(PostalAddress address) {
    final lines = <String>[
      if (address.street.isNotEmpty || address.number.isNotEmpty)
        '${address.street.isNotEmpty ? address.street : ''}'
        '${address.number.isNotEmpty ? ', ${address.number}' : ''}'.trim(),
      if (address.complement?.isNotEmpty ?? false) address.complement!,
      if (address.neighborhood.isNotEmpty) address.neighborhood,
      if (address.city.isNotEmpty || address.state.isNotEmpty)
        [
          address.city,
          address.state,
        ].where((part) => part.isNotEmpty).join(' - '),
      if (address.postalCode.isNotEmpty) 'CEP ${address.postalCode}',
    ];
    return lines.where((line) => line.isNotEmpty).join('\n');
  }

  Future<void> _join(
    BuildContext context,
    BusinessContextController controller,
  ) async {
    try {
      await controller.joinBusiness(business.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voce entrou em ${business.name}.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      final message =
          controller.errorMessage ?? 'Nao foi possivel entrar no pet shop.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
