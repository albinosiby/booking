import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../cubit/customer_cubits.dart';
import '../models/customer_models.dart';
import '../widgets/customer_desktop.dart';
import '../widgets/customer_plan_session.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final cubit = getIt<CustomerDetailCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.id,
  );
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CustomerDetailCubit, CustomerDetailModel>(
    bloc: cubit,
    builder: (context, s) => isDesktopWidth(context)
        ? desktop(context, s)
        : AppPage(
            back: true,
            title: 'Customer details',
            scrollId: 'customer-${widget.id}',
            maxWidth: 800,
            children: [
              if (s.loading) AppLoadingState(initial: s.customer == null),
              if (s.error != null)
                AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
              if (s.customer != null) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        s.customer!.phone,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.customer!.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (s.customer!.recordCount > 1) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Multiple customer records use this number. Each booking shows the name recorded for it.',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Booking history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'All accessible bookings for this phone number, newest first. Times use each venue’s timezone.',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: cubit.refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ),
                if (!s.loading && s.error == null && s.bookings.isEmpty)
                  const AppEmptyState(
                    showCard: false,
                    title: 'No bookings yet',
                    message:
                        'Bookings linked to this phone number will appear here.',
                    icon: Icons.event_note_outlined,
                  ),
                for (final b in s.bookings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      onTap: () => context.push('/booking/${b.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${b.businessName} · ${b.spaceName}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${bookingLocal(b.localStart)} → ${bookingLocal(b.localEnd)}',
                          ),
                          Text(
                            b.timezone,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(b.customer.name),
                          Text(
                            b.reference,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              BookingStatusChip(status: b.status),
                              if (!b.planSession)
                                BookingStatusChip(status: b.paymentStatus),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (b.planSession)
                            CustomerPlanSession(booking: b)
                          else
                            Text('Total: ${bookingMoney(b.total, s.currency)}'),
                          if (b.balance > 0)
                            Text(
                              'Amount due: ${bookingMoney(b.balance, s.currency)}',
                            ),
                          if (b.refundDue > 0)
                            Text(
                              'Refund due: ${bookingMoney(b.refundDue, s.currency)}',
                            ),
                        ],
                      ),
                    ),
                  ),
                if (s.next != null)
                  AppButton(
                    label: 'Load more bookings',
                    busy: s.loadingMore,
                    onPressed: s.loading || s.loadingMore
                        ? null
                        : () => cubit.load(more: true),
                  ),
              ],
            ],
          ),
  );

  // Desktop: profile and totals on the left, booking history on the right.
  Widget desktop(BuildContext context, CustomerDetailModel s) {
    final more = s.next == null
        ? null
        : Center(
            child: SizedBox(
              width: 320,
              child: AppButton(
                label: 'Load more bookings',
                busy: s.loadingMore,
                onPressed: s.loading || s.loadingMore
                    ? null
                    : () => cubit.load(more: true),
              ),
            ),
          );
    return AppPage(
      back: true,
      title: 'Customer details',
      eyebrow: 'CUSTOMER',
      scrollId: 'customer-${widget.id}',
      maxWidth: 1200,
      actions: [
        TextButton.icon(
          onPressed: cubit.refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
      children: [
        if (s.loading) AppLoadingState(initial: s.customer == null),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
        if (s.customer != null)
          AppTwoPane(
            secondaryFirst: true,
            secondaryWidth: 360,
            secondary: [CustomerProfileCard(state: s)],
            primary: [
              AppPanel(
                title: 'Booking history',
                subtitle:
                    'All accessible bookings for this phone number, newest first. Times use each venue’s timezone.',
                child: !s.loading && s.error == null && s.bookings.isEmpty
                    ? const AppCard(
                        child: AppEmptyState(
                          showCard: false,
                          title: 'No bookings yet',
                          message:
                              'Bookings linked to this phone number will appear here.',
                          icon: Icons.event_note_outlined,
                        ),
                      )
                    : AppListCard(
                        key: const ValueKey('customer-history-list'),
                        children: [
                          for (final b in s.bookings)
                            CustomerBookingRow(
                              booking: b,
                              currency: s.currency,
                            ),
                        ],
                      ),
              ),
              ?more,
            ],
          ),
      ],
    );
  }
}
