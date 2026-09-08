import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../controllers/package_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/package_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/package_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final packageRepository = context.read<PackageRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meus pacotes',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('Saldo e historico de uso'),
                ],
              ),
            ),
            const StatusBadge(label: 'Online'),
          ],
        ),
        const SizedBox(height: 18),
        StreamBuilder<List<CustomerPackageModel>>(
          stream: businessId == null
              ? const Stream<List<CustomerPackageModel>>.empty()
              : packageRepository.customerPackagesStream(businessId, profile.id),
          builder: (context, snapshot) {
            final packages = snapshot.data ?? const <CustomerPackageModel>[];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (packages.isEmpty) {
              return const EmptyState(
                icon: Icons.card_membership_outlined,
                title: 'Nenhum pacote comprado',
                message:
                    'Compre um pacote para acompanhar creditos e validade.',
              );
            }

            return Column(
              children: packages
                  .map(
                    (package) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CustomerPackageCard(package: package),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        _UsageHistory(clientId: profile.id),
        const SizedBox(height: 18),
        Text('Comprar pacote', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        StreamBuilder<List<BusinessPackageModel>>(
          stream: businessId == null
              ? const Stream<List<BusinessPackageModel>>.empty()
              : packageRepository.activePackagesStream(businessId),
          builder: (context, snapshot) {
            final packages = snapshot.data ?? const <BusinessPackageModel>[];
            if (packages.isEmpty) {
              return const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Catalogo vazio',
                message: 'O administrador ainda nao cadastrou pacotes ativos.',
              );
            }
            return Column(
              children: packages
                  .map(
                    (package) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BusinessPackageCard(package: package),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _CustomerPackageCard extends StatelessWidget {
  const _CustomerPackageCard({required this.package});

  final CustomerPackageModel package;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  package.packageName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: package.status.label,
                variant: package.canUse
                    ? StatusBadgeVariant.success
                    : StatusBadgeVariant.warning,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Valido ate ${formatDate(package.validUntil)}'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: package.usageProgress,
              minHeight: 10,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('${package.remainingCredits} disponiveis')),
              Text('${package.usedCredits} usados de ${package.totalCredits}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageHistory extends StatelessWidget {
  const _UsageHistory({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppointmentRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    return StreamBuilder<List<AppointmentModel>>(
      stream: businessId == null
          ? const Stream<List<AppointmentModel>>.empty()
          : repository.customerAppointmentsStream(businessId, clientId),
      builder: (context, snapshot) {
        final usages = (snapshot.data ?? const <AppointmentModel>[])
            .where(
              (appointment) =>
                  appointment.customerPackageId != null &&
                  appointment.customerPackageId!.isNotEmpty,
            )
            .take(4)
            .toList();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ultimas utilizacoes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (usages.isEmpty)
                const Text('Nenhum credito utilizado ainda.')
              else
                ...usages.map(
                  (appointment) => Text(
                    '${formatShortDate(appointment.startAt)} - '
                    '${appointment.serviceName}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessPackageCard extends StatelessWidget {
  const _BusinessPackageCard({required this.package});

  final BusinessPackageModel package;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    final controller = context.watch<PackageController>();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(package.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${package.totalCredits} creditos para ${package.serviceName}. '
            'Validade de ${package.validityDays} dias.',
          ),
          const SizedBox(height: 8),
          Text(
            formatCurrency(package.price),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AppButton(
            key: const Key('packages_buy_button'),
            label: 'Comprar novo pacote',
            icon: Icons.shopping_bag_outlined,
            isLoading: controller.isBusy,
            onPressed: profile == null
                ? null
                : () => _buy(context, controller, package),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(
    BuildContext context,
    PackageController controller,
    BusinessPackageModel package,
  ) async {
    try {
      await controller.checkoutWithMercadoPago(package);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conclua o pagamento no Mercado Pago para ativar o pacote.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Falha ao comprar pacote.'),
        ),
      );
    }
  }
}
