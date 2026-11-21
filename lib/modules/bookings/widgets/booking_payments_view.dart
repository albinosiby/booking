import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../workspace/widgets/workspace_business_order.dart';
import '../cubit/booking_list_cubit.dart';
import '../models/booking_list_model.dart';
import '../models/booking_models.dart';
import 'booking_widgets.dart';

/// Payments fill the page's bounded width without changing shared card sizing.
class BookingPaymentsView extends StatelessWidget {
  const BookingPaymentsView({
    super.key,
    required this.state,
    required this.cubit,
    this.back = false,
  });
  final BookingListModel state;
  final BookingListCubit cubit;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final s = state, currency = s.catalog.currency;
    return AppPage(
      title: 'Payments',
      back: back,
      compactHeader: true,
      subtitle: s.dueView
          ? 'Current outstanding balances and refunds.'
          : 'Manually recorded collections and refunds.',
      scrollId: 'booking-list-payments',
      maxWidth: 900,
      onRefresh: () => cubit.load(),
      children: [
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.loading) AppLoadingState(initial: !s.hasLoaded),
              if (s.error != null) ...[
                AppErrorWidget(message: s.error!, onRetry: cubit.load),
                const SizedBox(height: 16),
              ],
              AppPicker(
                label: 'Business filter',
                value: s.businessId ?? 'all',
                items: [
                  const PickerItem('all', 'All assigned businesses'),
                  ...orderedWorkspaceBusinesses(
                    context,
                    s.catalog.filters,
                    (b) => b.id,
                  ).map((b) => PickerItem(b.id, b.name)),
                ],
                onChanged: (v) => cubit.business(v == 'all' ? null : v),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ViewButton(
                    key: const ValueKey('payments-view-collections'),
                    label: 'Collections',
                    selected: !s.dueView,
                    onPressed: () => cubit.dueView(false),
                  ),
                  _ViewButton(
                    key: const ValueKey('payments-view-balances'),
                    label: 'Balances & refunds',
                    selected: s.dueView,
                    onPressed: () => cubit.dueView(true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BookingDateButton(date: s.date, onChanged: cubit.date),
                  if (s.date != null)
                    TextButton(
                      onPressed: () => cubit.date(null),
                      child: const Text('All dates'),
                    ),
                  TextButton.icon(
                    onPressed: s.loading ? null : cubit.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (s.dueView) ...[
                if (s.hasLoaded) ...[
                  AppCard(
                    key: const ValueKey('payments-balance-summary'),
                    child: _MetricPair(
                      first: _Metric(
                        label: 'Outstanding',
                        amount: s.balanceTotal,
                        currency: currency,
                      ),
                      second: _Metric(
                        label: 'Refunds due',
                        amount: s.refundTotal,
                        currency: currency,
                        refund: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final b in s.outstanding)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BalanceCard(
                      booking: b,
                      currency: currency,
                      onTap: s.catalog.canView
                          ? () => context.push('/booking/${b.id}')
                          : null,
                    ),
                  ),
                if (!s.loading && s.outstanding.isEmpty && s.error == null)
                  const AppEmptyState(
                    title: 'No balances due',
                    message:
                        'Try All dates to see balances for future or past bookings.',
                  ),
              ] else ...[
                if (s.totals.isNotEmpty) ...[
                  _CollectionSummary(state: s),
                  const SizedBox(height: 16),
                ],
                for (final e in s.collections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CollectionCard(
                      entry: e,
                      currency: currency,
                      onTap: s.catalog.canView
                          ? () => context.push('/booking/${e.bookingId}')
                          : null,
                    ),
                  ),
                if (!s.loading && s.collections.isEmpty && s.error == null)
                  const AppEmptyState(
                    title: 'No recorded payments',
                    message:
                        'Collections recorded against bookings appear here.',
                  ),
              ],
              if (s.next != null)
                AppButton(
                  label: 'Load more',
                  secondary: true,
                  busy: s.loadingMore,
                  onPressed: s.loadingMore
                      ? null
                      : () => cubit.load(more: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? colors.secondaryContainer
              : colors.surface,
          foregroundColor: selected
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? Colors.transparent : colors.outline,
            ),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, softWrap: true)),
          ],
        ),
      ),
    );
  }
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.amount,
    required this.currency,
    this.refund = false,
  });
  final String label, currency;
  final int amount;
  final bool refund;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Text(
          bookingMoney(amount, currency),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: refund && amount > 0 ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _BookingIdentity extends StatelessWidget {
  const _BookingIdentity({
    required this.customer,
    required this.reference,
    required this.canOpen,
  });
  final String customer, reference;
  final bool canOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                reference,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (canOpen) ...[
          const SizedBox(width: 12),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    required this.currency,
    this.refund = false,
  });
  final String label, currency;
  final int amount;
  final bool refund;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          bookingMoney(amount, currency),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: refund ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.booking,
    required this.currency,
    this.onTap,
  });
  final BookingOutstanding booking;
  final String currency;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('payment-balance-${booking.id}'),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BookingIdentity(
          customer: booking.customer,
          reference: booking.reference,
          canOpen: onTap != null,
        ),
        const SizedBox(height: 12),
        Text('${booking.business} · ${booking.space}'),
        const SizedBox(height: 4),
        Text(
          bookingLocal(booking.localStart),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 24),
        if (booking.balance > 0)
          _AmountLine(
            label: 'Balance due',
            amount: booking.balance,
            currency: currency,
          ),
        if (booking.balance > 0 && booking.refund > 0)
          const SizedBox(height: 8),
        if (booking.refund > 0)
          _AmountLine(
            label: 'Refund due',
            amount: booking.refund,
            currency: currency,
            refund: true,
          ),
      ],
    ),
  );
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.state});
  final BookingListModel state;
  @override
  Widget build(BuildContext context) => AppCard(
    key: const ValueKey('payments-collection-summary'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Totals for selected filters',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _MetricPair(
          first: _Metric(
            label: 'Cash received (net)',
            amount: state.cashReceivedNet,
            currency: state.catalog.currency,
          ),
          second: _Metric(
            label: 'Bank / digital (net)',
            amount: state.bankReceivedNet,
            currency: state.catalog.currency,
          ),
        ),
        const Divider(height: 24),
        for (final t in state.totals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _AmountLine(
              label: '${paymentLabel(t.kind)} · ${paymentLabel(t.method)}',
              amount: t.total,
              currency: state.catalog.currency,
              refund: t.kind == 'refund',
            ),
          ),
      ],
    ),
  );
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.entry,
    required this.currency,
    this.onTap,
  });
  final CollectionEntry entry;
  final String currency;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('payment-collection-${entry.payment.id}'),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BookingIdentity(
          customer: entry.customer,
          reference: entry.reference,
          canOpen: onTap != null,
        ),
        const SizedBox(height: 12),
        Text(
          bookingLocal(entry.payment.localReceived),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Recorded by ${entry.payment.collector}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 24),
        _AmountLine(
          label:
              '${paymentLabel(entry.payment.kind)} · ${paymentLabel(entry.payment.method)}',
          amount: entry.payment.amount,
          currency: currency,
          refund: entry.payment.kind == 'refund',
        ),
      ],
    ),
  );
}
