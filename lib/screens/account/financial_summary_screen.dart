import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/payment_model.dart';
import '../../repositories/payment_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

/// Monthly financial summary for admin/super admin: month selector, KPI grid
/// (received, transactions, pending, canceled), breakdown by payment type and
/// the month's payment list. Read-only — status changes come exclusively from
/// the Mercado Pago webhook.
class FinancialSummaryScreen extends StatelessWidget {
  const FinancialSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!profile.isStaff) {
      return AppPage(
        child: Column(
          children: const [
            EmptyState(
              icon: Icons.analytics_outlined,
              title: 'Acesso restrito',
              message: 'O resumo financeiro e voltado para administradores.',
            ),
          ],
        ),
      );
    }

    return const _FinancialSummaryBody();
  }
}

class _FinancialSummaryBody extends StatefulWidget {
  const _FinancialSummaryBody();

  @override
  State<_FinancialSummaryBody> createState() => _FinancialSummaryBodyState();
}

class _FinancialSummaryBodyState extends State<_FinancialSummaryBody> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime get _nextMonthStart => DateTime(_month.year, _month.month + 1, 1);

  DateTime get _endExclusive =>
      DateTime(_month.year, _month.month + 1, 1);

  bool get _canGoNext => _nextMonthStart.isBefore(
    DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
  );

  void _previousMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
    });
  }

  void _nextMonth() {
    if (!_canGoNext) {
      return;
    }
    setState(() => _month = _nextMonthStart);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PaymentRepository>();
    final businessId = context.watch<BusinessContextController>().activeBusinessId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Resumo financeiro',
              subtitle: 'Consolidado mensal do estabelecimento',
              trailing: _MonthSelector(
                month: _month,
                onPrevious: _previousMonth,
                onNext: _nextMonth,
                canGoNext: _canGoNext,
              ),
            ),
            StreamBuilder<List<PaymentModel>>(
              stream: businessId == null
                  ? const Stream<List<PaymentModel>>.empty()
                  : repository.allPaymentsStream(
                      businessId,
                      start: _month,
                      endExclusive: _endExclusive,
                    ),
              builder: (context, snapshot) =>
                  AsyncStateView<List<PaymentModel>>(
                    snapshot: snapshot,
                    isEmpty: (data) => data.isEmpty,
                    emptyTitle: 'Nenhum pagamento neste mes',
                    emptyMessage:
                        'Registros financeiros do mes aparecerao aqui.',
                    emptyIcon: Icons.receipt_long_outlined,
                    builder: (context, payments) {
                      final summary = _MonthSummary.fromPayments(payments);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _KpiGrid(summary: summary),
                          const SizedBox(height: 14),
                          _TypeBreakdown(summary: summary),
                          const SizedBox(height: 20),
                          const SectionHeader(title: 'Pagamentos do mes'),
                          for (final payment in payments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PaymentRow(payment: payment),
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.canGoNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('month_previous_button'),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onPrevious,
        ),
        SizedBox(
          width: 110,
          child: Text(
            _monthLabel(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const Key('month_next_button'),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Proximo mes',
          onPressed: canGoNext ? onNext : null,
        ),
      ],
    );
  }
}

String _monthLabel(DateTime month) {
  const months = [
    'janeiro',
    'fevereiro',
    'marco',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];
  return '${months[month.month - 1]} ${month.year}';
}

class _MonthSummary {
  const _MonthSummary({
    required this.received,
    required this.transactions,
    required this.pending,
    required this.canceled,
    required this.appointmentCount,
    required this.appointmentTotal,
    required this.packageCount,
    required this.packageTotal,
  });

  final double received;
  final int transactions;
  final double pending;
  final double canceled;
  final int appointmentCount;
  final double appointmentTotal;
  final int packageCount;
  final double packageTotal;

  factory _MonthSummary.fromPayments(List<PaymentModel> payments) {
    var received = 0.0;
    var pending = 0.0;
    var canceled = 0.0;
    var appointmentCount = 0;
    var appointmentTotal = 0.0;
    var packageCount = 0;
    var packageTotal = 0.0;

    for (final payment in payments) {
      switch (payment.status) {
        case PaymentStatus.paid:
          received += payment.amount;
        case PaymentStatus.pending || PaymentStatus.underReview:
          pending += payment.amount;
        case PaymentStatus.canceled || PaymentStatus.refunded:
          canceled += payment.amount;
      }
      switch (payment.type) {
        case PaymentType.appointment:
          appointmentCount++;
          appointmentTotal += payment.amount;
        case PaymentType.package:
          packageCount++;
          packageTotal += payment.amount;
        case PaymentType.other:
          break;
      }
    }

    return _MonthSummary(
      received: received,
      transactions: payments.length,
      pending: pending,
      canceled: canceled,
      appointmentCount: appointmentCount,
      appointmentTotal: appointmentTotal,
      packageCount: packageCount,
      packageTotal: packageTotal,
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final _MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final kpis = [
      (label: 'Recebido', value: formatCurrency(summary.received), icon: Icons.attach_money_outlined),
      (label: 'Transacoes', value: '${summary.transactions}', icon: Icons.swap_horiz_outlined),
      (label: 'Pendente', value: formatCurrency(summary.pending), icon: Icons.hourglass_top_outlined),
      (label: 'Cancelado', value: formatCurrency(summary.canceled), icon: Icons.cancel_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 500
            ? 2
            : 2;
        final cardWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * 10) / crossAxisCount;
        final cardHeight = cardWidth < 160 ? 96.0 : 84.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kpi in kpis)
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _KpiCard(
                  label: kpi.label,
                  value: kpi.value,
                  icon: kpi.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBreakdown extends StatelessWidget {
  const _TypeBreakdown({required this.summary});

  final _MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (summary.appointmentCount > 0)
        (
          label: 'Agendamentos',
          value: '${summary.appointmentCount} · '
              '${formatCurrency(summary.appointmentTotal)}',
        ),
      if (summary.packageCount > 0)
        (
          label: 'Pacotes',
          value: '${summary.packageCount} · '
              '${formatCurrency(summary.packageTotal)}',
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por tipo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text('Sem movimentacoes neste mes.')
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(row.value),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final PaymentModel payment;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${payment.type.label} - ${payment.clientName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                formatCurrency(payment.amount),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  payment.paidAt == null
                      ? '${payment.method.label} · Aguardando pagamento'
                      : '${payment.method.label} · ${formatDate(payment.paidAt!)}',
                ),
              ),
              StatusBadge(
                label: payment.status.label,
                variant: _paymentStatusVariant(payment.status),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

StatusBadgeVariant _paymentStatusVariant(PaymentStatus status) {
  return switch (status) {
    PaymentStatus.paid => StatusBadgeVariant.success,
    PaymentStatus.pending => StatusBadgeVariant.warning,
    PaymentStatus.canceled => StatusBadgeVariant.danger,
    PaymentStatus.refunded => StatusBadgeVariant.info,
    PaymentStatus.underReview => StatusBadgeVariant.info,
  };
}
