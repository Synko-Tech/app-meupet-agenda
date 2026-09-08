import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/package_model.dart';
import '../../models/payment_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/payment_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/info_banner.dart';
import '../../widgets/status_badge.dart';
import '../business/business_list_screen.dart';

/// Client landing screen: next appointment, booking CTA, expiring package
/// balance and pending payment alert.
class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key, this.onOpenAgenda, this.onOpenPackages});

  final VoidCallback? onOpenAgenda;
  final VoidCallback? onOpenPackages;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final firstName = profile.name.trim().isEmpty
        ? 'Bem-vindo'
        : 'Ola, ${profile.name.trim().split(' ').first}';

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(title: firstName, subtitle: 'Como podemos ajudar hoje?'),
          const SectionHeader(title: 'Proximo agendamento'),
          _NextAppointmentCard(
            profileId: profile.id,
            onOpenAgenda: onOpenAgenda,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Agendar atendimento',
            icon: Icons.add_task_outlined,
            onPressed: onOpenAgenda,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Encontrar pet shop',
            icon: Icons.storefront_outlined,
            isSecondary: true,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const BusinessListScreen(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Seus pacotes',
            action: TextButton(
              onPressed: onOpenPackages,
              child: const Text('Ver todos'),
            ),
          ),
          _UpcomingPackageCard(
            profileId: profile.id,
            onOpenPackages: onOpenPackages,
          ),
          const SizedBox(height: 24),
          _PendingPaymentsBanner(profileId: profile.id),
        ],
      ),
    );
  }
}

class _NextAppointmentCard extends StatefulWidget {
  const _NextAppointmentCard({required this.profileId, this.onOpenAgenda});

  final String profileId;
  final VoidCallback? onOpenAgenda;

  @override
  State<_NextAppointmentCard> createState() => _NextAppointmentCardState();
}

class _NextAppointmentCardState extends State<_NextAppointmentCard> {
  Key _streamKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppointmentRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    final stream = businessId == null
        ? const Stream<AppointmentModel?>.empty()
        : repository.customerAppointmentsStream(
            businessId,
            widget.profileId,
          ).map(
            (appointments) {
              final upcoming =
                  appointments
                      .where(
                        (appointment) =>
                            appointment.status != AppointmentStatus.canceled &&
                            appointment.startAt.isAfter(DateTime.now()),
                      )
                      .toList()
                    ..sort((a, b) => a.startAt.compareTo(b.startAt));
              return upcoming.isEmpty ? null : upcoming.first;
            },
          );

    return StreamBuilder<AppointmentModel?>(
      key: _streamKey,
      stream: stream,
      builder: (context, snapshot) => AsyncStateView<AppointmentModel?>(
        snapshot: snapshot,
        isEmpty: (value) => value == null,
        emptyTitle: 'Nenhum agendamento marcado',
        emptyMessage:
            'Agende o proximo atendimento do seu pet em poucos passos.',
        emptyIcon: Icons.event_available_outlined,
        emptyAction: TextButton.icon(
          onPressed: widget.onOpenAgenda,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agendar agora'),
        ),
        errorMessage:
            'Nao foi possivel carregar seus agendamentos. Verifique sua conexao.',
        onRetry: () => setState(() => _streamKey = UniqueKey()),
        builder: (context, appointment) =>
            _AppointmentHighlight(appointment: appointment!),
      ),
    );
  }
}

class _AppointmentHighlight extends StatelessWidget {
  const _AppointmentHighlight({required this.appointment});

  final AppointmentModel appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      variant: AppCardVariant.highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(appointment.serviceName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                '${formatDate(appointment.startAt)} as '
                '${formatTime(appointment.startAt)}',
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _UpcomingPackageCard extends StatefulWidget {
  const _UpcomingPackageCard({required this.profileId, this.onOpenPackages});

  final String profileId;
  final VoidCallback? onOpenPackages;

  @override
  State<_UpcomingPackageCard> createState() => _UpcomingPackageCardState();
}

class _UpcomingPackageCardState extends State<_UpcomingPackageCard> {
  Key _streamKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PackageRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    final stream = businessId == null
        ? const Stream<CustomerPackageModel?>.empty()
        : repository.customerPackagesStream(
            businessId,
            widget.profileId,
          ).map(
            (packages) {
              final usable = packages.where((package) => package.canUse).toList()
                ..sort((a, b) => a.validUntil.compareTo(b.validUntil));
              return usable.isEmpty ? null : usable.first;
            },
          );

    return StreamBuilder<CustomerPackageModel?>(
      key: _streamKey,
      stream: stream,
      builder: (context, snapshot) => AsyncStateView<CustomerPackageModel?>(
        snapshot: snapshot,
        isEmpty: (value) => value == null,
        emptyTitle: 'Sem pacotes ativos',
        emptyMessage: 'Pacotes de banho e tosa com creditos aparecem aqui.',
        emptyIcon: Icons.card_membership_outlined,
        emptyAction: TextButton.icon(
          onPressed: widget.onOpenPackages,
          icon: const Icon(Icons.shopping_bag_outlined, size: 18),
          label: const Text('Ver pacotes'),
        ),
        errorMessage:
            'Nao foi possivel carregar seus pacotes. Verifique sua conexao.',
        onRetry: () => setState(() => _streamKey = UniqueKey()),
        builder: (context, package) => _PackageBalanceCard(package: package!),
      ),
    );
  }
}

class _PackageBalanceCard extends StatelessWidget {
  const _PackageBalanceCard({required this.package});

  final CustomerPackageModel package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  package.packageName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: '${package.remainingCredits} creditos',
                icon: Icons.savings_outlined,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: package.usageProgress,
              minHeight: 10,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Valido ate ${formatDate(package.validUntil)}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PendingPaymentsBanner extends StatelessWidget {
  const _PendingPaymentsBanner({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PaymentRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;
    return StreamBuilder<List<PaymentModel>>(
      stream: businessId == null
          ? const Stream<List<PaymentModel>>.empty()
          : repository.customerPaymentsStream(businessId, profileId),
      builder: (context, snapshot) => AsyncStateView<List<PaymentModel>>(
        snapshot: snapshot,
        isEmpty: (data) =>
            data.every((payment) => payment.status != PaymentStatus.pending),
        emptyBuilder: (context) => const SizedBox.shrink(),
        errorMessage:
            'Nao foi possivel carregar seus pagamentos. Verifique sua conexao.',
        builder: (context, payments) {
          final pending = payments
              .where((payment) => payment.status == PaymentStatus.pending)
              .toList();
          final total = pending.fold<double>(
            0,
            (sum, payment) => sum + payment.amount,
          );
          return InfoBanner(
            variant: InfoBannerVariant.warning,
            icon: Icons.pending_actions_outlined,
            title: 'Pagamento pendente',
            message:
                'Voce tem ${formatCurrency(total)} aguardando confirmacao. '
                'A ativacao e feita pelo estabelecimento.',
          );
        },
      ),
    );
  }
}
