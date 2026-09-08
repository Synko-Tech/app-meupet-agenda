import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_brand_colors.dart';
import '../../app/formatters.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/app_user.dart';
import '../../models/appointment_model.dart';
import '../../models/package_model.dart';
import '../../models/service_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/service_repository.dart';
import '../../services/business_hours.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/info_banner.dart';
import '../../widgets/status_badge.dart';

enum _AppointmentStep { service, schedule, review }

class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key});

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  _AppointmentStep _step = _AppointmentStep.service;
  String? _selectedServiceId;
  String? _pickedTime;
  String? _submitError;
  CustomerPackageModel? _activePackage;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    final serviceRepository = context.read<ServiceRepository>();

    return StreamBuilder<List<ServiceModel>>(
      stream: businessId == null
          ? const Stream<List<ServiceModel>>.empty()
          : serviceRepository.activeServicesStream(businessId),
      builder: (context, serviceSnapshot) {
        final services = serviceSnapshot.data ?? const <ServiceModel>[];
        if (serviceSnapshot.connectionState == ConnectionState.waiting) {
          return _page(
            profile: profile,
            content: const Center(child: CircularProgressIndicator()),
            services: const [],
            selectedService: ServiceModel.empty(),
          );
        }
        if (serviceSnapshot.hasError) {
          return _page(
            profile: profile,
            content: const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Nao foi possivel carregar os servicos',
              message:
                  'Verifique sua conexao e as permissoes do Firebase antes de tentar novamente.',
            ),
            services: const [],
            selectedService: ServiceModel.empty(),
          );
        }
        if (services.isEmpty) {
          return _page(
            profile: profile,
            content: const EmptyState(
              icon: Icons.design_services_outlined,
              title: 'Nenhum servico cadastrado',
              message:
                  'Cadastre servicos no painel administrativo para liberar a agenda.',
            ),
            services: const [],
            selectedService: ServiceModel.empty(),
          );
        }

        final selectedServiceId = _validOrFirst(
          _selectedServiceId,
          services.map((e) => e.id),
        );
        final selectedService = services.firstWhere(
          (service) => service.id == selectedServiceId,
        );

        return _page(
          profile: profile,
          content: _stepContent(
            profile: profile,
            services: services,
            selectedService: selectedService,
          ),
          services: services,
          selectedService: selectedService,
        );
      },
    );
  }

  Widget _page({
    required AppUser profile,
    required Widget content,
    required List<ServiceModel> services,
    required ServiceModel selectedService,
  }) {
    final controller = context.watch<AppointmentController>();
    final canContinue = switch (_step) {
      _AppointmentStep.service => services.isNotEmpty,
      _AppointmentStep.schedule => _pickedTime != null,
      _AppointmentStep.review => _pickedTime != null,
    };
    final isReview = _step == _AppointmentStep.review;

    return Column(
      children: [
        Expanded(
          child: AppPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(profile: profile),
                const SizedBox(height: 14),
                _StepIndicator(step: _step),
                const SizedBox(height: 18),
                content,
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                if (_step != _AppointmentStep.service) ...[
                  AppButton(
                    key: const Key('appointment_back_button'),
                    label: 'Voltar',
                    icon: Icons.arrow_back,
                    variant: AppButtonVariant.tonal,
                    expand: false,
                    onPressed: () => _goToStep(_previousStep),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppButton(
                    key: Key(
                      isReview
                          ? 'appointment_confirm_button'
                          : 'appointment_continue_button',
                    ),
                    label: isReview ? 'Confirmar agendamento' : 'Continuar',
                    icon: isReview
                        ? Icons.event_available
                        : Icons.arrow_forward,
                    isLoading: controller.isBusy,
                    onPressed: canContinue
                        ? () {
                            if (isReview) {
                              _confirm(service: selectedService);
                              return;
                            }
                            _onContinue(service: selectedService);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _AppointmentStep get _previousStep {
    return switch (_step) {
      _AppointmentStep.service => _AppointmentStep.service,
      _AppointmentStep.schedule => _AppointmentStep.service,
      _AppointmentStep.review => _AppointmentStep.schedule,
    };
  }

  void _goToStep(_AppointmentStep step) {
    setState(() {
      _step = step;
      _submitError = null;
    });
  }

  void _selectService(String? id) {
    setState(() {
      _selectedServiceId = id;
      _pickedTime = null;
      _submitError = null;
    });
  }

  void _pickTime(String time) {
    final controller = context.read<AppointmentController>();
    setState(() => _pickedTime = time);
    controller.selectTime(time);
  }

  void _onContinue({required ServiceModel service}) {
    // Usa os valores efetivos (fallback incluso) computados no build; o
    // _selectedServiceId cru pode estar null quando nenhum card foi tocado.
    if (_step == _AppointmentStep.service) {
      _selectedServiceId = service.id;
      _goToStep(_AppointmentStep.schedule);
      return;
    }
    if (_step == _AppointmentStep.schedule && _pickedTime != null) {
      _goToStep(_AppointmentStep.review);
      return;
    }
  }

  Future<void> _confirm({required ServiceModel service}) async {
    final controller = context.read<AppointmentController>();
    try {
      await controller.createAppointment(
        service: service,
        customerPackage: _activePackage,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agendamento confirmado.')));
      setState(() {
        _step = _AppointmentStep.service;
        _selectedServiceId = null;
        _pickedTime = null;
        _submitError = null;
        _activePackage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _submitError = controller.errorMessage ?? 'Falha ao agendar.',
      );
    }
  }

  Widget _stepContent({
    required AppUser profile,
    required List<ServiceModel> services,
    required ServiceModel selectedService,
  }) {
    return switch (_step) {
      _AppointmentStep.service => _ServiceStep(
        services: services,
        selectedId: _selectedServiceId,
        onSelect: _selectService,
      ),
      _AppointmentStep.schedule => _ScheduleStep(
        profile: profile,
        service: selectedService,
        pickedTime: _pickedTime,
        onPickTime: _pickTime,
      ),
      _AppointmentStep.review => _ReviewStep(
        profile: profile,
        service: selectedService,
        date: context.watch<AppointmentController>().selectedDate,
        time:
            _pickedTime ?? context.watch<AppointmentController>().selectedTime,
        error: _submitError,
        onPackageResolved: (package) => _activePackage = package,
      ),
    };
  }

  String? _validOrFirst(String? current, Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) {
      return null;
    }
    if (current != null && list.contains(current)) {
      return current;
    }
    return list.first;
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final _AppointmentStep step;

  static const List<String> _labels = [
    'Servico',
    'Data e horario',
    'Revisao',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = step.index;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i <= index ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          _StepDot(
            index: i,
            state: i < index
                ? _StepDotState.done
                : i == index
                ? _StepDotState.current
                : _StepDotState.upcoming,
          ),
        ],
      ],
    );
  }
}

enum _StepDotState { done, current, upcoming }

class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.state});

  final int index;
  final _StepDotState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = context.brand;
    final isActive = state != _StepDotState.upcoming;

    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? scheme.primary : Colors.white,
              border: Border.all(
                color: isActive ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: state == _StepDotState.done
                ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isActive
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            _labelsFor(index),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: state == _StepDotState.current
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: state == _StepDotState.current
                  ? scheme.primary
                  : brand.muted,
            ),
          ),
        ],
      ),
    );
  }

  String _labelsFor(int index) {
    return _StepIndicator._labels[index];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agendar atendimento',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              const Text('Escolha servico, data e horario'),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _ServiceStep extends StatelessWidget {
  const _ServiceStep({
    required this.services,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ServiceModel> services;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Servico', subtitle: 'O que vamos fazer?'),
        for (final service in services) ...[
          _SelectableOption(
            key: ValueKey('appointment_service_card_${service.id}'),
            title: service.name,
            subtitle: '${service.durationMinutes} min',
            selected: service.id == selectedId,
            onTap: () => onSelect(service.id),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SelectableOption extends StatelessWidget {
  const _SelectableOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.interactive,
      onTap: onTap,
      trailing: selected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : Icon(Icons.circle_outlined, color: scheme.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: context.brand.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({
    required this.profile,
    required this.service,
    required this.pickedTime,
    required this.onPickTime,
  });

  final AppUser profile;
  final ServiceModel service;
  final String? pickedTime;
  final ValueChanged<String> onPickTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Data',
          subtitle: 'Escolha o dia do atendimento',
        ),
        _DateSelector(),
        if (profile.role != UserRole.admin) ...[
          const SizedBox(height: 14),
          const _BusinessHoursCard(),
        ],
        const SizedBox(height: 14),
        const SectionHeader(
          title: 'Horario',
          subtitle: 'Escolha um horario livre',
        ),
        _TimeGrid(
          service: service,
          pickedTime: pickedTime,
          onPickTime: onPickTime,
        ),
      ],
    );
  }
}

class _DateSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppointmentController>();
    final today = DateTime.now();
    final dates = List<DateTime>.generate(
      5,
      (index) => DateTime(today.year, today.month, today.day + index),
    );

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = _sameDay(controller.selectedDate, date);
          return ChoiceChip(
            key: ValueKey('appointment_day_chip_$index'),
            selected: isSelected,
            onSelected: (_) => controller.selectDate(date),
            label: SizedBox(
              width: 52,
              height: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text(weekdayLabel(date)), Text(date.day.toString())],
              ),
            ),
            selectedColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: dates.length,
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _BusinessHoursCard extends StatelessWidget {
  const _BusinessHoursCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Horario de funcionamento',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Segunda a Sexta: 08h as 18h'),
                const Text('Banho e tosa: 08h as 16h'),
                const Text('Sabado: 08h as 12h'),
                const Text('Banho e tosa aos sabados: 08h as 10h'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.service,
    required this.pickedTime,
    required this.onPickTime,
  });

  final ServiceModel service;
  final String? pickedTime;
  final ValueChanged<String> onPickTime;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppointmentController>();
    final repository = context.read<AppointmentRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;

    return StreamBuilder<List<AppointmentModel>>(
      stream: businessId == null
          ? const Stream<List<AppointmentModel>>.empty()
          : repository.appointmentsForDayStream(
              businessId,
              controller.selectedDate,
            ),
      builder: (context, snapshot) {
        final occupiedTimes = (snapshot.data ?? const <AppointmentModel>[])
            .where(
              (appointment) =>
                  appointment.status == AppointmentStatus.scheduled ||
                  appointment.status == AppointmentStatus.confirmed,
            )
            .map((appointment) => formatTime(appointment.startAt))
            .toSet();
        final availableTimes = AppointmentController.availableTimes
            .where(BusinessHours.shouldShowInSchedule)
            .toList();

        final slots = availableTimes.map((time) {
          final minutes = BusinessHours.minutesFromTime(time);
          final slotAt = DateTime(
            controller.selectedDate.year,
            controller.selectedDate.month,
            controller.selectedDate.day,
            minutes ~/ 60,
            minutes % 60,
          );
          final disabled =
              slotAt.isBefore(DateTime.now()) ||
              occupiedTimes.contains(time) ||
              !BusinessHours.isInsideBookingHours(
                time: time,
                serviceName: service.name,
                date: controller.selectedDate,
              );
          return _TimeSlot(
            time: time,
            isSelected: pickedTime == time,
            isDisabled: disabled,
          );
        }).toList();

        return _CompactTimeGrid(slots: slots, onSelected: onPickTime);
      },
    );
  }
}

class _TimeSlot {
  const _TimeSlot({
    required this.time,
    required this.isSelected,
    required this.isDisabled,
  });

  final String time;
  final bool isSelected;
  final bool isDisabled;
}

class _CompactTimeGrid extends StatelessWidget {
  const _CompactTimeGrid({required this.slots, required this.onSelected});

  final List<_TimeSlot> slots;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final morning = _slotsForPeriod(0, 12 * 60);
    final afternoon = _slotsForPeriod(12 * 60, 18 * 60);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.access_time,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Horarios disponiveis',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (morning.isNotEmpty)
            _TimePeriodSection(
              title: 'Manha',
              slots: morning,
              onSelected: onSelected,
            ),
          if (afternoon.isNotEmpty)
            _TimePeriodSection(
              title: 'Tarde',
              slots: afternoon,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }

  List<_TimeSlot> _slotsForPeriod(int startMinutes, int endMinutes) {
    return slots.where((slot) {
      final minutes = BusinessHours.minutesFromTime(slot.time);
      return minutes >= startMinutes && minutes < endMinutes;
    }).toList();
  }
}

class _TimePeriodSection extends StatelessWidget {
  const _TimePeriodSection({
    required this.title,
    required this.slots,
    required this.onSelected,
  });

  final String title;
  final List<_TimeSlot> slots;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.brand.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 420
                  ? 5
                  : constraints.maxWidth >= 330
                  ? 4
                  : 3;
              const spacing = 8.0;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * spacing) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: slots
                    .map(
                      (slot) => SizedBox(
                        width: itemWidth,
                        height: 48,
                        child: OutlinedButton(
                          key: ValueKey('appointment_slot_${slot.time}'),
                          onPressed: slot.isDisabled
                              ? null
                              : () => onSelected(slot.time),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: slot.isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                            foregroundColor: slot.isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            disabledForegroundColor: context.brand.muted
                                .withValues(alpha: 0.45),
                            disabledBackgroundColor: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.45),
                            side: BorderSide(
                              color: slot.isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            slot.time,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.profile,
    required this.service,
    required this.date,
    required this.time,
    required this.error,
    required this.onPackageResolved,
  });

  final AppUser profile;
  final ServiceModel service;
  final DateTime date;
  final String time;
  final String? error;
  final ValueChanged<CustomerPackageModel?> onPackageResolved;

  @override
  Widget build(BuildContext context) {
    final package = _PackageBlock(
      profile: profile,
      service: service,
      onResolved: onPackageResolved,
    );
    final summary = _SummaryCard(
      service: service,
      date: date,
      time: time,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Revisao', subtitle: 'Confira os dados'),
        if (error != null) ...[
          InfoBanner(variant: InfoBannerVariant.danger, message: error!),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 560;
            if (sideBySide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 12),
                  Expanded(child: package),
                ],
              );
            }
            return Column(
              children: [summary, const SizedBox(height: 12), package],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.service,
    required this.date,
    required this.time,
  });

  final ServiceModel service;
  final DateTime date;
  final String time;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            label: 'Servico',
            value: '${service.name} · ${service.durationMinutes} min',
          ),
          const Divider(height: 18),
          _SummaryRow(
            label: 'Data',
            value: '${weekdayLabel(date)}, ${formatDate(date)}',
          ),
          const Divider(height: 18),
          _SummaryRow(label: 'Horario', value: time),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: context.brand.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PackageBlock extends StatefulWidget {
  const _PackageBlock({
    required this.profile,
    required this.service,
    required this.onResolved,
  });

  final AppUser profile;
  final ServiceModel service;
  final ValueChanged<CustomerPackageModel?> onResolved;

  @override
  State<_PackageBlock> createState() => _PackageBlockState();
}

class _PackageBlockState extends State<_PackageBlock> {
  /// Último pacote notificado ao pai (por id). Evita loops: o callback so
  /// dispara quando o valor resolvido realmente muda, nunca a cada rebuild.
  String? _lastResolvedId;

  void _resolve(CustomerPackageModel? package) {
    if (package?.id == _lastResolvedId) {
      return;
    }
    _lastResolvedId = package?.id;
    // Notifica apos o frame: durante o build nao podemos mutar o estado do
    // pai (setState/markNeedsBuild durante build e proibido).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onResolved(package);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final packageRepository = context.read<PackageRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    return StreamBuilder<List<CustomerPackageModel>>(
      stream: businessId == null
          ? const Stream<List<CustomerPackageModel>>.empty()
          : packageRepository.activeCustomerPackagesForServiceStream(
              businessId: businessId,
              clientId: widget.profile.id,
              serviceId: widget.service.id,
            ),
      builder: (context, snapshot) {
        final packages = (snapshot.data ?? const <CustomerPackageModel>[])
            .where((package) => package.canUse)
            .toList();
        final package = packages.isEmpty ? null : packages.first;
        _resolve(package);
        if (package == null) {
          return const EmptyState(
            icon: Icons.card_membership_outlined,
            title: 'Sem pacote ativo para este servico',
            message: 'O atendimento sera registrado sem debito de credito.',
          );
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pacote ativo encontrado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const StatusBadge(label: 'Ativo'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${package.packageName}. O atendimento pode usar 1 '
                'credito do pacote.',
              ),
              const SizedBox(height: 8),
              Text('${package.remainingCredits} creditos disponiveis'),
            ],
          ),
        );
      },
    );
  }
}
