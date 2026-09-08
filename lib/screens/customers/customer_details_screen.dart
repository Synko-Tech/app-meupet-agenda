import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/admin_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/app_user.dart';
import '../../models/appointment_model.dart';
import '../../models/package_model.dart';
import '../../models/payment_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/payment_repository.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/confirmation_sheet.dart';
import '../../widgets/status_badge.dart';

/// Client profile with appointment, package and payment history, plus the
/// only admin action of this delivery: activate/deactivate the account.
class CustomerDetailsScreen extends StatelessWidget {
  const CustomerDetailsScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final userRepository = context.read<UserRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cliente')),
      body: StreamBuilder<AppUser?>(
        stream: userRepository.profileStream(clientId),
        builder: (context, snapshot) {
          return AsyncStateView<AppUser?>(
            snapshot: snapshot,
            isEmpty: (user) => user == null,
            emptyTitle: 'Cliente nao encontrado',
            emptyMessage: 'O perfil deste cliente nao esta disponivel.',
            builder: (context, user) {
              final client = user!;
              return AppPage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageHeader(
                      title: client.name,
                      subtitle: client.email,
                      trailing: StatusBadge(
                        label: client.isActive ? 'Ativo' : 'Inativo',
                        variant: client.isActive
                            ? StatusBadgeVariant.success
                            : StatusBadgeVariant.warning,
                      ),
                    ),
                    _ProfileCard(client: client),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Agendamentos',
                      subtitle: 'Historico de horarios do cliente',
                    ),
                    _AppointmentsSection(clientId: clientId),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Pacotes',
                      subtitle: 'Creditos comprados e restantes',
                    ),
                    _PackagesSection(clientId: clientId),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Pagamentos',
                      subtitle: 'Transacoes registradas',
                    ),
                    _PaymentsSection(clientId: clientId),
                    const SizedBox(height: 24),
                    _ActivateAction(client: client),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.client});

  final AppUser client;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileRow(label: 'Nome', value: client.name),
          _ProfileRow(label: 'E-mail', value: client.email),
          if (client.phone != null && client.phone!.isNotEmpty)
            _ProfileRow(label: 'Telefone', value: client.phone!),
          _ProfileRow(
            label: 'Status',
            value: client.isActive ? 'Ativo' : 'Inativo',
          ),
          if (client.createdAt != null)
            _ProfileRow(
              label: 'Cadastro',
              value: formatDate(client.createdAt!),
            ),
          if (client.updatedAt != null)
            _ProfileRow(
              label: 'Atualizacao',
              value: formatDate(client.updatedAt!),
            ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsSection extends StatelessWidget {
  const _AppointmentsSection({required this.clientId});

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
        return AsyncStateView<List<AppointmentModel>>(
          snapshot: snapshot,
          emptyTitle: 'Sem agendamentos',
          emptyMessage: 'Nenhum horario registrado para este cliente.',
          emptyIcon: Icons.event_busy_outlined,
          builder: (context, appointments) {
            return Column(
              children: [
                for (final appointment in appointments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.serviceName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${formatDate(appointment.startAt)} '
                            '${formatTime(appointment.startAt)}',
                          ),
                          StatusBadge(
                            label: appointment.status.label,
                            variant: _appointmentVariant(appointment.status),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PackagesSection extends StatelessWidget {
  const _PackagesSection({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PackageRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    return StreamBuilder<List<CustomerPackageModel>>(
      stream: businessId == null
          ? const Stream<List<CustomerPackageModel>>.empty()
          : repository.customerPackagesStream(businessId, clientId),
      builder: (context, snapshot) {
        return AsyncStateView<List<CustomerPackageModel>>(
          snapshot: snapshot,
          emptyTitle: 'Sem pacotes',
          emptyMessage: 'Nenhum pacote comprado por este cliente.',
          emptyIcon: Icons.card_membership_outlined,
          builder: (context, packages) {
            return Column(
              children: [
                for (final item in packages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.packageName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(item.serviceName),
                          Text(
                            '${item.usedCredits}/${item.totalCredits} creditos usados',
                          ),
                          Text('Validade: ${formatDate(item.validUntil)}'),
                          StatusBadge(
                            label: item.status.label,
                            variant: item.status == CustomerPackageStatus.active
                                ? StatusBadgeVariant.success
                                : StatusBadgeVariant.warning,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PaymentRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    return StreamBuilder<List<PaymentModel>>(
      stream: businessId == null
          ? const Stream<List<PaymentModel>>.empty()
          : repository.customerPaymentsStream(businessId, clientId),
      builder: (context, snapshot) {
        return AsyncStateView<List<PaymentModel>>(
          snapshot: snapshot,
          emptyTitle: 'Sem pagamentos',
          emptyMessage: 'Nenhuma transacao registrada para este cliente.',
          emptyIcon: Icons.payments_outlined,
          builder: (context, payments) {
            return Column(
              children: [
                for (final payment in payments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${payment.type.label} - '
                            '${formatCurrency(payment.amount)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(payment.method.label),
                          Text(
                            payment.paidAt != null
                                ? formatDate(payment.paidAt!)
                                : 'Aguardando pagamento',
                          ),
                          StatusBadge(
                            label: payment.status.label,
                            variant: _paymentVariant(payment.status),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ActivateAction extends StatelessWidget {
  const _ActivateAction({required this.client});

  final AppUser client;

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminController>();
    final activating = !client.isActive;
    return AppButton(
      key: const ValueKey('customer-toggle-active'),
      label: activating ? 'Ativar cliente' : 'Inativar cliente',
      icon: activating ? Icons.check_circle_outline : Icons.block_outlined,
      isSecondary: !activating,
      onPressed: admin.isBusy
          ? null
          : () => _confirmAndToggle(context, admin, activating),
    );
  }

  Future<void> _confirmAndToggle(
    BuildContext context,
    AdminController admin,
    bool activating,
  ) async {
    final confirmed = await showConfirmationSheet(
      context: context,
      title: activating ? 'Ativar cliente' : 'Inativar cliente',
      items: [
        ConfirmationItem(label: 'Cliente', value: client.name),
        ConfirmationItem(
          label: 'Acao',
          value: activating ? 'Ativar conta' : 'Inativar conta',
        ),
      ],
      confirmLabel: activating ? 'Ativar' : 'Inativar',
      destructive: !activating,
      confirmIcon: activating
          ? Icons.check_circle_outline
          : Icons.block_outlined,
      onConfirm: () =>
          admin.setUserActive(userId: client.id, isActive: activating),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          activating
              ? 'Cliente ativado com sucesso.'
              : 'Cliente inativado com sucesso.',
        ),
      ),
    );
  }
}

StatusBadgeVariant _appointmentVariant(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.canceled => StatusBadgeVariant.danger,
    AppointmentStatus.completed => StatusBadgeVariant.info,
    AppointmentStatus.confirmed => StatusBadgeVariant.success,
    _ => StatusBadgeVariant.warning,
  };
}

StatusBadgeVariant _paymentVariant(PaymentStatus status) {
  return switch (status) {
    PaymentStatus.paid => StatusBadgeVariant.success,
    PaymentStatus.canceled => StatusBadgeVariant.danger,
    PaymentStatus.refunded => StatusBadgeVariant.info,
    PaymentStatus.underReview => StatusBadgeVariant.warning,
    _ => StatusBadgeVariant.warning,
  };
}
