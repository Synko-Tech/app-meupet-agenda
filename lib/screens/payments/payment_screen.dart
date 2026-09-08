import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../models/app_user.dart';
import '../../models/payment_model.dart';
import '../../repositories/payment_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/status_badge.dart';

/// Payments screen. Read-only list; status changes come exclusively from the
/// Mercado Pago webhook (realtime via Firestore). Staff can filter by period;
/// clients see their own payments without the filter control.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// Active period window. Null means "all records" (after Limpar); the
  /// initial value is the current month.
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(
        now.year,
        now.month + 1,
        1,
      ).subtract(const Duration(days: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthController>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Pagamentos',
            subtitle: 'Registros financeiros do estabelecimento',
          ),
          if (profile.isStaff) ...[
            _PeriodFilter(
              range: _range,
              onChanged: (range) => setState(() => _range = range),
              onClear: () => setState(() => _range = null),
            ),
            const SizedBox(height: 14),
          ],
          _PaymentsList(profile: profile, range: _range),
        ],
      ),
    );
  }
}

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({
    required this.range,
    required this.onChanged,
    required this.onClear,
  });

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active =
        range ?? DateTimeRange(start: DateTime(2020), end: DateTime.now());
    final label = range == null
        ? 'Todos os periodos'
        : '${formatDate(active.start)} - ${formatDate(active.end)}';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.date_range_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: const Key('payment_period_change_button'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: range == null ? null : active,
              );
              if (picked != null) {
                onChanged(picked);
              }
            },
            child: const Text('Alterar'),
          ),
          TextButton(
            key: const Key('payment_period_clear_button'),
            onPressed: range == null ? null : onClear,
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }
}

class _PaymentsList extends StatelessWidget {
  const _PaymentsList({required this.profile, required this.range});

  final AppUser profile;
  final DateTimeRange? range;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PaymentRepository>();
    final businessId = context
        .watch<BusinessContextController>()
        .activeBusinessId;
    final start = range?.start;
    final endExclusive = range?.end.add(const Duration(days: 1));
    final stream = businessId == null
        ? const Stream<List<PaymentModel>>.empty()
        : profile.isStaff
        ? repository.allPaymentsStream(
            businessId,
            start: start,
            endExclusive: endExclusive,
          )
        : repository.customerPaymentsStream(
            businessId,
            profile.id,
            start: start,
            endExclusive: endExclusive,
          );

    return StreamBuilder<List<PaymentModel>>(
      stream: stream,
      builder: (context, snapshot) => AsyncStateView<List<PaymentModel>>(
        snapshot: snapshot,
        isEmpty: (data) => data.isEmpty,
        emptyTitle: 'Nenhum pagamento neste periodo',
        emptyMessage:
            'Nenhum registro financeiro neste intervalo. Ajuste o filtro para ver outros periodos.',
        emptyIcon: Icons.receipt_long_outlined,
        builder: (context, payments) => Column(
          children: payments
              .map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
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
                  ),
                ),
              )
              .toList(),
        ),
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
