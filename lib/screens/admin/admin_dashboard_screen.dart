import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/admin_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/package_model.dart';
import '../../models/service_model.dart';
import '../../repositories/appointment_repository.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/service_repository.dart';
import '../../services/access_control.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

enum _DateRange {
  today('Hoje'),
  sevenDays('7 dias'),
  thirtyDays('30 dias');

  const _DateRange(this.label);

  final String label;

  DateTime get start {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _DateRange.today => today,
      _DateRange.sevenDays => today.subtract(const Duration(days: 7)),
      _DateRange.thirtyDays => today.subtract(const Duration(days: 30)),
    };
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.onOpenAgenda});

  final VoidCallback? onOpenAgenda;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _DateRange _dateRange = _DateRange.today;

  void _clearFilters() {
    setState(() {
      _dateRange = _DateRange.today;
    });
  }

  bool _inRange(AppointmentModel appointment) {
    final now = DateTime.now();
    return !appointment.startAt.isBefore(_dateRange.start) &&
        !appointment.startAt.isAfter(now);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!AccessControl.canAccessAdminPanel(profile)) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          EmptyState(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Acesso administrativo',
            message:
                'Este painel e voltado para administradores e colaboradores.',
          ),
        ],
      );
    }

    final repository = context.read<AppointmentRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;

    return AppPage(
      child: StreamBuilder<List<AppointmentModel>>(
        stream: businessId == null
            ? const Stream<List<AppointmentModel>>.empty()
            : repository.allAppointmentsStream(businessId),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <AppointmentModel>[];
          final filtered = all.where(_inRange).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Painel admin',
                subtitle: 'Resumo do estabelecimento',
                trailing: _AvatarBadge(name: profile.name),
              ),
              _DashboardFilters(
                dateRange: _dateRange,
                onRangeChanged: (range) => setState(() => _dateRange = range),
                onClear: _clearFilters,
              ),
              const SizedBox(height: 16),
              _DashboardMetrics(
                appointments: filtered,
                packages: context.read<PackageRepository>(),
              ),
              const SizedBox(height: 16),
              _WeeklyChart(appointments: filtered),
              const SizedBox(height: 16),
              _FilteredAgendaCard(appointments: filtered),
              const SizedBox(height: 12),
              AppButton(
                label: 'Novo agendamento',
                icon: Icons.add_task_outlined,
                onPressed: widget.onOpenAgenda,
              ),
              const SizedBox(height: 24),
              if (AccessControl.canManageCatalog(profile)) ...[
                const _ManagementActions(),
                const SizedBox(height: 18),
                const _ServicesAdminList(),
                const SizedBox(height: 18),
                const _PackagesAdminList(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _DashboardFilters extends StatelessWidget {
  const _DashboardFilters({
    required this.dateRange,
    required this.onRangeChanged,
    required this.onClear,
  });

  final _DateRange dateRange;
  final ValueChanged<_DateRange> onRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final range in _DateRange.values)
                ChoiceChip(
                  label: Text(range.label),
                  selected: dateRange == range,
                  onSelected: (_) => onRangeChanged(range),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('dashboard_clear_filters'),
              onPressed: dateRange == _DateRange.today ? null : onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Limpar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({required this.appointments, required this.packages});

  final List<AppointmentModel> appointments;
  final PackageRepository packages;

  @override
  Widget build(BuildContext context) {
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    final active = appointments.where(
      (appointment) => appointment.status != AppointmentStatus.canceled,
    );
    final usedCredits = appointments
        .where(
          (appointment) =>
              appointment.customerPackageId != null &&
              appointment.customerPackageId!.isNotEmpty,
        )
        .length;
    final clientsServed = active
        .map((appointment) => appointment.clientId)
        .toSet()
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * 10) / crossAxisCount;
        final cardHeight = cardWidth < 160 ? 110.0 : 96.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _MetricCard(
                value: '${active.length}',
                label: 'Atendimentos',
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: StreamBuilder<List<BusinessPackageModel>>(
                stream: businessId == null
                    ? const Stream<List<BusinessPackageModel>>.empty()
                    : packages.activePackagesStream(businessId),
                builder: (context, snapshot) => _MetricCard(
                  value: '${snapshot.data?.length ?? 0}',
                  label: 'Pacotes ativos',
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _MetricCard(
                value: '$usedCredits',
                label: 'Creditos usados',
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _MetricCard(
                value: '$clientsServed',
                label: 'Clientes atendidos',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: Theme.of(context).textTheme.titleLarge),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.appointments});

  final List<AppointmentModel> appointments;

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.filled(7, 0);
    for (final appointment in appointments) {
      counts[appointment.startAt.weekday - 1]++;
    }
    final maxCount = counts.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atendimentos por dia da semana',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxCount + 1).toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index > 6) {
                          return const SizedBox.shrink();
                        }
                        const labels = [
                          'Seg',
                          'Ter',
                          'Qua',
                          'Qui',
                          'Sex',
                          'Sab',
                          'Dom',
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[index],
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < 7; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: counts[i].toDouble(),
                          color: scheme.primary,
                          width: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredAgendaCard extends StatelessWidget {
  const _FilteredAgendaCard({required this.appointments});

  final List<AppointmentModel> appointments;

  @override
  Widget build(BuildContext context) {
    final sorted = [...appointments]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agenda do periodo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            const Text('Nenhum atendimento neste periodo.')
          else
            ...sorted
                .take(10)
                .map(
                  (appointment) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTime(appointment.startAt),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.serviceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(appointment.clientName),
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: appointment.status.label,
                          variant: _appointmentStatusVariant(
                            appointment.status,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ManagementActions extends StatelessWidget {
  const _ManagementActions();

  @override
  Widget build(BuildContext context) {
    // Gestao de catalogo (servicos/pacotes) e exclusiva de admin/owner:
    // firestore.rules exige isBusinessManager para write em services/packages.
    // Esconder os botoes para colaboradores evita acoes que o backend rejeita.
    final profile = context.watch<AuthController>().profile;
    if (!AccessControl.canManageCatalog(profile)) {
      return const SizedBox.shrink();
    }
    final serviceRepository = context.read<ServiceRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: 'Servico',
            icon: Icons.add_business_outlined,
            isSecondary: true,
            onPressed: () => _showServiceSheet(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<List<ServiceModel>>(
            stream: businessId == null
                ? const Stream<List<ServiceModel>>.empty()
                : serviceRepository.activeServicesStream(businessId),
            builder: (context, snapshot) {
              return AppButton(
                label: 'Pacote',
                icon: Icons.add_card_outlined,
                isSecondary: true,
                onPressed: (snapshot.data ?? const <ServiceModel>[]).isEmpty
                    ? null
                    : () => _showPackageSheet(
                        context,
                        snapshot.data ?? const <ServiceModel>[],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showServiceSheet(BuildContext context, [ServiceModel? service]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceForm(service: service),
    );
  }

  void _showPackageSheet(
    BuildContext context,
    List<ServiceModel> services, [
    BusinessPackageModel? package,
  ]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PackageForm(services: services, package: package),
    );
  }
}

class _ServicesAdminList extends StatelessWidget {
  const _ServicesAdminList();

  Future<void> _toggleService(
    BuildContext context,
    AdminController admin,
    ServiceModel service,
    bool value,
  ) async {
    try {
      await admin.setServiceActive(service.id, value);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(admin.errorMessage ?? 'Falha ao alterar o servico.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ServiceRepository>();
    final admin = context.read<AdminController>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;

    return StreamBuilder<List<ServiceModel>>(
      stream: businessId == null
          ? const Stream<List<ServiceModel>>.empty()
          : repository.allServicesStream(businessId),
      builder: (context, snapshot) {
        final services = snapshot.data ?? const <ServiceModel>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Servicos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (services.isEmpty)
              const EmptyState(
                icon: Icons.design_services_outlined,
                title: 'Nenhum servico',
                message: 'Use o botao acima para cadastrar o primeiro servico.',
              )
            else
              ...services.map(
                (service) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${service.durationMinutes} min - '
                                '${formatCurrency(service.price)}',
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: service.isActive,
                          onChanged: admin.isBusy
                              ? null
                              : (value) => _toggleService(
                                  context,
                                  admin,
                                  service,
                                  value,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PackagesAdminList extends StatelessWidget {
  const _PackagesAdminList();

  @override
  Widget build(BuildContext context) {
    final packageRepository = context.read<PackageRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    return StreamBuilder<List<BusinessPackageModel>>(
      stream: businessId == null
          ? const Stream<List<BusinessPackageModel>>.empty()
          : packageRepository.allPackagesStream(businessId),
      builder: (context, snapshot) {
        final packages = snapshot.data ?? const <BusinessPackageModel>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pacotes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (packages.isEmpty)
              const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Nenhum pacote',
                message: 'Cadastre pacotes vinculados aos servicos.',
              )
            else
              ...packages.map(
                (package) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                package.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${package.totalCredits} creditos - '
                                '${formatCurrency(package.price)}',
                              ),
                              Text(package.serviceName),
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: package.isActive ? 'Ativo' : 'Inativo',
                          variant: package.isActive
                              ? StatusBadgeVariant.success
                              : StatusBadgeVariant.warning,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ServiceForm extends StatefulWidget {
  const _ServiceForm({this.service});

  final ServiceModel? service;

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _durationController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _nameController = TextEditingController(text: service?.name ?? '');
    _descriptionController = TextEditingController(
      text: service?.description ?? '',
    );
    _durationController = TextEditingController(
      text: (service?.durationMinutes ?? 60).toString(),
    );
    _priceController = TextEditingController(
      text: (service?.price ?? 80).toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final admin = context.watch<AdminController>();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Servico', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Nome',
              controller: _nameController,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Descricao',
              controller: _descriptionController,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Duracao em minutos',
              controller: _durationController,
              keyboardType: TextInputType.number,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Valor',
              controller: _priceController,
              keyboardType: TextInputType.number,
              validator: _required,
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Salvar servico',
              icon: Icons.save_outlined,
              isLoading: admin.isBusy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obrigatorio';
    }
    return null;
  }

  double _parsePrice(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return 0;
    }
    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');
    if (lastComma == -1 && lastDot == -1) {
      return double.tryParse(text) ?? 0;
    }
    // O ultimo separador e o decimal: "1.234,56" -> 1234.56 (convencao BR),
    // "80.50" -> 80.50 (ponto decimal colado de teclado/import).
    final decimalIsComma = lastComma > lastDot;
    final normalized = decimalIsComma
        ? text.replaceAll('.', '').replaceAll(',', '.')
        : text.replaceAll(',', '');
    return double.tryParse(normalized) ?? 0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final service = widget.service;
    final admin = context.read<AdminController>();
    try {
      await admin.saveService(
        ServiceModel(
          id: service?.id ?? '',
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          durationMinutes: int.tryParse(_durationController.text) ?? 60,
          price: _parsePrice(_priceController.text),
          isActive: service?.isActive ?? true,
        ),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(admin.errorMessage ?? 'Falha ao salvar servico.'),
        ),
      );
    }
  }
}

class _PackageForm extends StatefulWidget {
  const _PackageForm({required this.services, this.package});

  final List<ServiceModel> services;
  final BusinessPackageModel? package;

  @override
  State<_PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends State<_PackageForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _creditsController;
  late final TextEditingController _priceController;
  late final TextEditingController _validityController;
  late ServiceModel _selectedService;

  @override
  void initState() {
    super.initState();
    final package = widget.package;
    _selectedService = widget.services.firstWhere(
      (service) => service.id == package?.serviceId,
      orElse: () => widget.services.first,
    );
    _nameController = TextEditingController(text: package?.name ?? '');
    _creditsController = TextEditingController(
      text: (package?.totalCredits ?? 10).toString(),
    );
    _priceController = TextEditingController(
      text: (package?.price ?? 240).toStringAsFixed(2).replaceAll('.', ','),
    );
    _validityController = TextEditingController(
      text: (package?.validityDays ?? 90).toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _creditsController.dispose();
    _priceController.dispose();
    _validityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final admin = context.watch<AdminController>();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pacote', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            if (widget.services.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Cadastre um servico antes de criar pacotes.'),
              )
            else
              DropdownButtonFormField<ServiceModel>(
                key: ValueKey(_selectedService.id),
                initialValue:
                    widget.services.any(
                      (service) => service.id == _selectedService.id,
                    )
                    ? _selectedService
                    : widget.services.first,
                decoration: const InputDecoration(labelText: 'Servico'),
                items: widget.services
                    .map(
                      (service) => DropdownMenuItem<ServiceModel>(
                        value: service,
                        child: Text(service.name),
                      ),
                    )
                    .toList(),
                onChanged: (service) {
                  if (service != null) {
                    setState(() => _selectedService = service);
                  }
                },
              ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Nome do pacote',
              controller: _nameController,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Quantidade de creditos',
              controller: _creditsController,
              keyboardType: TextInputType.number,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Valor',
              controller: _priceController,
              keyboardType: TextInputType.number,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Validade em dias',
              controller: _validityController,
              keyboardType: TextInputType.number,
              validator: _required,
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Salvar pacote',
              icon: Icons.save_outlined,
              isLoading: admin.isBusy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obrigatorio';
    }
    return null;
  }

  double _parsePrice(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return 0;
    }
    final lastComma = text.lastIndexOf(',');
    final lastDot = text.lastIndexOf('.');
    if (lastComma == -1 && lastDot == -1) {
      return double.tryParse(text) ?? 0;
    }
    // O ultimo separador e o decimal: "1.234,56" -> 1234.56 (convencao BR),
    // "80.50" -> 80.50 (ponto decimal colado de teclado/import).
    final decimalIsComma = lastComma > lastDot;
    final normalized = decimalIsComma
        ? text.replaceAll('.', '').replaceAll(',', '.')
        : text.replaceAll(',', '');
    return double.tryParse(normalized) ?? 0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final package = widget.package;
    final admin = context.read<AdminController>();
    try {
      await admin.savePackage(
        BusinessPackageModel(
          id: package?.id ?? '',
          serviceId: _selectedService.id,
          serviceName: _selectedService.name,
          name: _nameController.text.trim(),
          totalCredits: int.tryParse(_creditsController.text) ?? 1,
          price: _parsePrice(_priceController.text),
          validityDays: int.tryParse(_validityController.text) ?? 90,
          isActive: package?.isActive ?? true,
        ),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(admin.errorMessage ?? 'Falha ao salvar pacote.'),
        ),
      );
    }
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
