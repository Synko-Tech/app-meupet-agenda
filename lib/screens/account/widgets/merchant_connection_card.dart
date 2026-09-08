import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/formatters.dart';
import '../../../controllers/merchant_connection_controller.dart';
import '../../../models/app_user.dart';
import '../../../models/business_membership.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/status_badge.dart';

/// Card "Recebimentos" do Perfil: mostra o estado da conta Mercado Pago da
/// loja ativa e permite ao owner conectar/reconectar/desconectar via OAuth.
///
/// Admins/collaborators veem apenas o estado (sem botoes ou identificadores
/// financeiros); o owner vê o fluxo completo.
class MerchantConnectionCard extends StatelessWidget {
  const MerchantConnectionCard({
    super.key,
    required this.profile,
    required this.role,
  });

  final AppUser profile;
  final BusinessRole role;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MerchantConnectionController>();
    final summary = controller.summary;
    final isOwner = role == BusinessRole.owner;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                summary.isConnected
                    ? Icons.account_balance_wallet_outlined
                    : Icons.wallet_giftcard_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recebimentos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: summary.isConnected
                    ? 'Mercado Pago conectado'
                    : 'Nao conectado',
                variant: summary.isConnected
                    ? StatusBadgeVariant.success
                    : StatusBadgeVariant.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!summary.isConnected) ...[
            const Text(
              'Conecte sua conta Mercado Pago para receber vendas desta loja.',
            ),
            if (isOwner) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Conectar Mercado Pago',
                icon: Icons.link_outlined,
                isLoading: controller.isBusy,
                onPressed: () => _connect(context, controller),
              ),
            ],
          ] else ...[
            if (isOwner) ...[
              _InfoRow(
                label: 'Conta',
                value: _maskedCollector(summary.collectorId),
              ),
              _InfoRow(
                label: 'Ambiente',
                value: summary.liveMode == true ? 'Producao' : 'Testes',
              ),
            ],
            if (summary.connectedAt != null)
              _InfoRow(
                label: 'Conectado em',
                value: formatDate(summary.connectedAt!),
              ),
            if (summary.needsRefresh && isOwner) ...[
              const SizedBox(height: 8),
              const Text(
                'A conexao esta proxima de expirar. Renove para continuar '
                'recebendo pagamentos.',
                style: TextStyle(color: Colors.orange),
              ),
            ],
            if (isOwner) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Reconectar',
                      icon: Icons.refresh_outlined,
                      isSecondary: true,
                      isLoading: controller.isBusy,
                      onPressed: () => _connect(context, controller),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Desconectar',
                      icon: Icons.link_off_outlined,
                      variant: AppButtonVariant.destructive,
                      isLoading: controller.isBusy,
                      onPressed: () => _disconnect(context, controller),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _maskedCollector(String? collectorId) {
    final id = collectorId ?? '';
    if (id.isEmpty) {
      return 'Nao informado';
    }
    if (id.length <= 4) {
      return 'Conta •••• $id';
    }
    return 'Conta •••• ${id.substring(id.length - 4)}';
  }

  Future<void> _connect(
    BuildContext context,
    MerchantConnectionController controller,
  ) async {
    try {
      await controller.connect();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorize sua conta na pagina do Mercado Pago que abriu.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Falha ao conectar.'),
        ),
      );
    }
  }

  Future<void> _disconnect(
    BuildContext context,
    MerchantConnectionController controller,
  ) async {
    try {
      await controller.disconnect();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta Mercado Pago desconectada.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Falha ao desconectar.'),
        ),
      );
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
