import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/booking_models.dart';
import '../models/booking_list_model.dart';
import '../cubit/booking_list_cubit.dart';
import '../widgets/booking_widgets.dart';
import '../widgets/booking_agenda_view.dart';

class BookingListScreen extends StatefulWidget {
  const BookingListScreen({
    super.key,
    this.mode = BookingListMode.bookings,
    this.initialBusinessId,
  });
  final BookingListMode mode;
  final String? initialBusinessId;
  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  late final cubit = getIt<BookingListCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.mode,
  );
  @override
  void initState() {
    super.initState();
    if (widget.initialBusinessId != null) {
      cubit.business(widget.initialBusinessId);
    } else {
      cubit.load();
    }
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BookingListCubit, BookingListModel>(
    bloc: cubit,
    builder: (context, s) {
      final calendar = widget.mode == BookingListMode.calendar,
          payments = widget.mode == BookingListMode.payments;
      if (!payments) {
        return BookingAgendaView(
          state: s,
          cubit: cubit,
          calendar: calendar,
          back: widget.initialBusinessId != null,
        );
      }
      return AppPage(
        title: 'Payments',
        subtitle: 'Manually recorded collections and refunds.',
        scrollId: 'booking-list-payments',
        maxWidth: 900,
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
            children: [
              ChoiceChip(
                label: const Text('Collections'),
                selected: !s.dueView,
                onSelected: (_) => cubit.dueView(false),
              ),
              ChoiceChip(
                label: const Text('Balances & refunds'),
                selected: s.dueView,
                onSelected: (_) => cubit.dueView(true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              BookingDateButton(date: s.date, onChanged: cubit.date),
              TextButton(
                onPressed: () => cubit.date(null),
                child: const Text('All dates'),
              ),
              TextButton.icon(
                onPressed: cubit.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (s.dueView) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Outstanding: ${bookingMoney(s.balanceTotal, s.catalog.currency)}',
                  ),
                  Text(
                    'Refunds due: ${bookingMoney(s.refundTotal, s.catalog.currency)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final b in s.outstanding)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  onTap: s.catalog.canView
                      ? () => context.push('/booking/${b.id}')
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b.customer} · ${b.reference}'),
                      Text('${b.business} · ${b.space}'),
                      Text(bookingLocal(b.localStart)),
                      if (b.balance > 0)
                        Text(
                          'Balance: ${bookingMoney(b.balance, s.catalog.currency)}',
                        ),
                      if (b.refund > 0)
                        Text(
                          'Refund due: ${bookingMoney(b.refund, s.catalog.currency)}',
                        ),
                    ],
                  ),
                ),
              ),
            if (!s.loading && s.outstanding.isEmpty && s.error == null)
              const AppEmptyState(
                title: 'No balances due',
                message:
                    'Try All dates to see balances for future or past bookings.',
              ),
          ] else ...[
            if (s.totals.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Totals for selected filters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final t in s.totals)
                      Text(
                        '${paymentLabel(t.kind)} · ${paymentLabel(t.method)}: ${bookingMoney(t.total, s.catalog.currency)}',
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            for (final e in s.collections)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  onTap: s.catalog.canView
                      ? () => context.push('/booking/${e.bookingId}')
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${paymentLabel(e.payment.kind)} · ${paymentLabel(e.payment.method)} · ${bookingMoney(e.payment.amount, s.catalog.currency)}',
                      ),
                      Text('${e.customer} · ${e.reference}'),
                      Text(bookingLocal(e.payment.localReceived)),
                      Text('Recorded by ${e.payment.collector}'),
                    ],
                  ),
                ),
              ),
            if (!s.loading && s.collections.isEmpty && s.error == null)
              const AppEmptyState(
                title: 'No recorded payments',
                message: 'Collections recorded against bookings appear here.',
              ),
          ],
          if (s.next != null)
            AppButton(
              label: 'Load more',
              secondary: true,
              busy: s.loadingMore,
              onPressed: s.loadingMore ? null : () => cubit.load(more: true),
            ),
        ],
      );
    },
  );
}
