import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/service_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/service_repository.dart';
import '../../services/access_control.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({super.key});

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _serviceId;
  String _clientFilter = '';
  bool _filtersExpanded = false;
  int _retryTick = 0;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (!AccessControl.canAccessAdminCalendar(profile)) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          EmptyState(
            icon: Icons.lock_outline,
            title: 'Calendario restrito',
            message: 'Apenas super admin pode acessar a agenda administrativa.',
          ),
        ],
      );
    }

    final appointmentRepository = context.read<AppointmentRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Calendario',
            subtitle: 'Agendamentos por dia e horario',
          ),
          StreamBuilder<List<AppointmentModel>>(
            key: ValueKey('calendar_day_$_retryTick'),
            stream: businessId == null
                ? const Stream<List<AppointmentModel>>.empty()
                : appointmentRepository.appointmentsForDayStream(
                    businessId,
                    _selectedDate,
                  ),
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <AppointmentModel>[];
              final filtered = _filter(all);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final tablet = constraints.maxWidth >= 600;
                  final filters = _Filters(
                    serviceId: _serviceId,
                    clientFilter: _clientFilter,
                    onServiceChanged: (id) => setState(() => _serviceId = id),
                    onClientChanged: (value) =>
                        setState(() => _clientFilter = value),
                  );
                  final list = _AppointmentsList(
                    snapshot: snapshot,
                    all: all,
                    filtered: filtered,
                    onRetry: () => setState(() => _retryTick++),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CalendarHeader(
                        selectedDate: _selectedDate,
                        resultCount: filtered.length,
                        onToday: () =>
                            setState(() => _selectedDate = DateTime.now()),
                        onPick: _pickDate,
                      ),
                      const SizedBox(height: 12),
                      if (tablet)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 250, child: filters),
                            const SizedBox(width: 14),
                            Expanded(child: list),
                          ],
                        )
                      else ...[
                        _FiltersToggle(
                          expanded: _filtersExpanded,
                          onToggle: () => setState(
                            () => _filtersExpanded = !_filtersExpanded,
                          ),
                        ),
                        if (_filtersExpanded) ...[
                          const SizedBox(height: 8),
                          filters,
                        ],
                        const SizedBox(height: 14),
                        list,
                      ],
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

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _selectedDate,
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  List<AppointmentModel> _filter(List<AppointmentModel> appointments) {
    return appointments.where((appointment) {
      final serviceOk =
          _serviceId == null || appointment.serviceId == _serviceId;
      final clientOk =
          _clientFilter.trim().isEmpty ||
          appointment.clientName.toLowerCase().contains(
            _clientFilter.trim().toLowerCase(),
          );
      return serviceOk && clientOk;
    }).toList();
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.selectedDate,
    required this.resultCount,
    required this.onToday,
    required this.onPick,
  });

  final DateTime selectedDate;
  final int resultCount;
  final VoidCallback onToday;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDate(selectedDate),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(weekdayLabel(selectedDate)),
                const SizedBox(height: 2),
                Text(
                  '$resultCount ${resultCount == 1 ? 'atendimento' : 'atendimentos'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onToday, child: const Text('Hoje')),
          TextButton(onPressed: onPick, child: const Text('Alterar')),
        ],
      ),
    );
  }
}

class _FiltersToggle extends StatelessWidget {
  const _FiltersToggle({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onToggle,
        child: Row(
          children: [
            Icon(
              Icons.filter_list,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Filtros',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.serviceId,
    required this.clientFilter,
    required this.onServiceChanged,
    required this.onClientChanged,
  });

  final String? serviceId;
  final String clientFilter;
  final ValueChanged<String?> onServiceChanged;
  final ValueChanged<String> onClientChanged;

  @override
  Widget build(BuildContext context) {
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    final serviceRepository = context.read<ServiceRepository>();
    return AppCard(
      child: Column(
        children: [
          StreamBuilder<List<ServiceModel>>(
            stream: businessId == null
                ? const Stream<List<ServiceModel>>.empty()
                : serviceRepository.allServicesStream(businessId),
            builder: (context, snapshot) {
              final services = snapshot.data ?? const <ServiceModel>[];
              final selectedInList = services.any(
                (service) => service.id == serviceId,
              );
              final effectiveValue = serviceId == null || selectedInList
                  ? serviceId
                  : null;
              return DropdownButtonFormField<String?>(
                key: ValueKey(
                  'calendar_service_filter-${effectiveValue ?? ''}',
                ),
                initialValue: effectiveValue,
                decoration: const InputDecoration(labelText: 'Servico'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  ...services.map(
                    (service) => DropdownMenuItem<String?>(
                      value: service.id,
                      child: Text(service.name),
                    ),
                  ),
                ],
                onChanged: onServiceChanged,
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Cliente',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onClientChanged,
          ),
        ],
      ),
    );
  }
}

class _AppointmentsList extends StatelessWidget {
  const _AppointmentsList({
    required this.snapshot,
    required this.all,
    required this.filtered,
    required this.onRetry,
  });

  final AsyncSnapshot<List<AppointmentModel>> snapshot;
  final List<AppointmentModel> all;
  final List<AppointmentModel> filtered;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const AppSkeletonList(count: 4);
    }

    if (snapshot.hasError) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Nao foi possivel carregar os agendamentos',
        message: 'Verifique sua conexao e tente novamente.',
        action: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Tentar novamente'),
        ),
      );
    }

    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'Nenhum agendamento neste dia',
        message: 'Os horarios ocupados aparecerao nesta area.',
      );
    }

    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Nenhum agendamento encontrado para os filtros',
        message: 'Ajuste os filtros para ampliar a busca.',
      );
    }

    return Column(
      children: filtered
          .map(
            (appointment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalendarAppointmentCard(appointment: appointment),
            ),
          )
          .toList(),
    );
  }
}

class _CalendarAppointmentCard extends StatelessWidget {
  const _CalendarAppointmentCard({required this.appointment});

  final AppointmentModel appointment;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatTime(appointment.startAt),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
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
                Text(appointment.clientName),
              ],
            ),
          ),
          StatusBadge(
            label: appointment.status.label,
            variant: appointment.status == AppointmentStatus.canceled
                ? StatusBadgeVariant.danger
                : StatusBadgeVariant.success,
          ),
        ],
      ),
    );
  }
}
