import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/app_user.dart';
import '../../models/appointment_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/confirmation_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

/// Dedicated appointment history screen. Clients see their own appointments;
/// staff (admin/super admin) see every appointment of the establishment.
class AppointmentHistoryScreen extends StatelessWidget {
  const AppointmentHistoryScreen({super.key, required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Historico de agendamentos',
            subtitle: 'Acompanhe os atendimentos do estabelecimento',
          ),
          _AppointmentHistoryList(profile: profile),
        ],
      ),
    );
  }
}

enum _AppointmentFilter { all, upcoming, completed, canceled }

extension on _AppointmentFilter {
  String get label => switch (this) {
    _AppointmentFilter.all => 'Todos',
    _AppointmentFilter.upcoming => 'Agendados',
    _AppointmentFilter.completed => 'Concluidos',
    _AppointmentFilter.canceled => 'Cancelados',
  };
}

class _AppointmentHistoryList extends StatefulWidget {
  const _AppointmentHistoryList({required this.profile});

  final AppUser profile;

  @override
  State<_AppointmentHistoryList> createState() => _AppointmentHistoryListState();
}

class _AppointmentHistoryListState extends State<_AppointmentHistoryList> {
  _AppointmentFilter _filter = _AppointmentFilter.all;
  bool _showAll = false;

  List<AppointmentModel> _applyFilter(List<AppointmentModel> appointments) {
    return switch (_filter) {
      _AppointmentFilter.all => appointments,
      _AppointmentFilter.upcoming =>
        appointments
            .where(
              (appointment) =>
                  appointment.status == AppointmentStatus.scheduled ||
                  appointment.status == AppointmentStatus.confirmed,
            )
            .toList(),
      _AppointmentFilter.completed =>
        appointments
            .where(
              (appointment) =>
                  appointment.status == AppointmentStatus.completed,
            )
            .toList(),
      _AppointmentFilter.canceled =>
        appointments
            .where(
              (appointment) => appointment.status == AppointmentStatus.canceled,
            )
            .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppointmentRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    final stream = businessId == null
        ? const Stream<List<AppointmentModel>>.empty()
        : widget.profile.isStaff
        ? repository.allAppointmentsStream(businessId)
        : repository.customerAppointmentsStream(businessId, widget.profile.id);

    return StreamBuilder<List<AppointmentModel>>(
      stream: stream,
      builder: (context, snapshot) => AsyncStateView<List<AppointmentModel>>(
        snapshot: snapshot,
        isEmpty: (data) => data.isEmpty,
        emptyTitle: 'Sem agendamentos ainda',
        emptyMessage: 'Quando um servico for agendado, ele aparecera aqui.',
        emptyIcon: Icons.history_outlined,
        builder: (context, appointments) {
          final filtered = _applyFilter(appointments);
          final visible = _showAll ? filtered : filtered.take(6).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in _AppointmentFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) {
                        setState(() {
                          _filter = filter;
                          _showAll = false;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Nada neste filtro',
                  message: 'Tente outro filtro para encontrar agendamentos.',
                )
              else ...[
                for (final appointment in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AppointmentCard(
                      appointment: appointment,
                      canCancel: widget.profile.isStaff,
                    ),
                  ),
                if (filtered.length > 6)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Ver menos' : 'Ver todos'),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.canCancel});

  final AppointmentModel appointment;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final cancelable =
        canCancel &&
        appointment.status != AppointmentStatus.canceled &&
        appointment.status != AppointmentStatus.completed &&
        appointment.startAt.isAfter(DateTime.now());

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.event_note_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.serviceName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDate(appointment.startAt)} as '
                  '${formatTime(appointment.startAt)}',
                ),
                Text(
                  appointment.clientName.isEmpty
                      ? 'Cliente'
                      : appointment.clientName,
                ),
                if (appointment.customerPackageId?.isNotEmpty == true)
                  const Text('Valor: incluso no pacote'),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(
                label: appointment.status.label,
                variant: _appointmentStatusVariant(appointment.status),
              ),
              if (cancelable)
                TextButton(
                  onPressed: () => _cancel(context),
                  child: const Text('Cancelar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final controller = context.read<AppointmentController>();
    final confirmed = await showConfirmationSheet(
      context: context,
      title: 'Cancelar agendamento?',
      items: [
        ConfirmationItem(label: 'Servico', value: appointment.serviceName),
        ConfirmationItem(
          label: 'Data e horario',
          value:
              '${formatDate(appointment.startAt)} as '
              '${formatTime(appointment.startAt)}',
        ),
        if (appointment.customerPackageId?.isNotEmpty == true)
          const ConfirmationItem(
            label: 'Credito do pacote',
            value: 'Devolvido apos o cancelamento',
          ),
      ],
      confirmLabel: 'Cancelar agendamento',
      confirmIcon: Icons.event_busy_outlined,
      destructive: true,
      onConfirm: () => controller.cancelAppointment(appointment),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Agendamento cancelado.')));
  }
}

StatusBadgeVariant _appointmentStatusVariant(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.canceled => StatusBadgeVariant.danger,
    AppointmentStatus.completed => StatusBadgeVariant.success,
    AppointmentStatus.confirmed => StatusBadgeVariant.success,
    AppointmentStatus.scheduled => StatusBadgeVariant.warning,
  };
}
