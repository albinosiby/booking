import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../../utils/helpers/subscription_labels.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/models/slot_holder.dart' show weekdayNames;
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/subscriptions_cubit.dart';
import '../models/admission_models.dart';
import '../repositories/admission_repository.dart';
import '../widgets/admission_cards.dart';

/// Profile → Subscriptions: everyone on a monthly subscription.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final cubit = SubscriptionsCubit(getIt<AdmissionRepository>())..load();
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (mounted) cubit.load();
  }

  static const filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('upcoming', 'Upcoming'),
    ('cancelled', 'Stopped'),
    ('expired', 'Ended'),
  ];

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SubscriptionsCubit, SubscriptionsState>(
    bloc: cubit,
    builder: (context, s) => AppPage(
      title: 'Subscriptions',
      back: true,
      scrollId: 'subscriptions',
      actions: [
        IconButton(
          tooltip: 'Refresh subscriptions',
          onPressed: s.loading ? null : () => cubit.load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('subscription-add'),
        // New subscriptions are added from New booking → Subscription.
        onPressed: () => open('/booking/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add subscription'),
      ),
      children: [
        TextField(
          key: const ValueKey('subscription-search'),
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search name, phone or admission no.',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                search.clear();
                cubit.load(query: '');
              },
              icon: const Icon(Icons.close),
            ),
          ),
          onSubmitted: (v) => cubit.load(query: v.trim()),
        ),
        SizedBox(height: 12.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final (status, label) in filters)
              ChoiceChip(
                key: ValueKey('subscription-filter-${status ?? 'all'}'),
                label: Text(label),
                selected: s.status == status,
                onSelected: (_) =>
                    cubit.load(status: status, clearStatus: status == null),
              ),
          ],
        ),
        SizedBox(height: 12.h),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: () => cubit.load()),
        if (s.loading && s.items.isEmpty)
          const AppLoadingState(initial: true, label: 'Loading subscriptions…'),
        if (!s.loading && s.error == null && s.items.isEmpty)
          const AppEmptyState(
            title: 'No subscriptions',
            message:
                'Add one from New booking → Subscription: choose the activation date, months, days, time slot and monthly fee.',
            icon: Icons.event_repeat_outlined,
          ),
        for (final a in s.items)
          _SubscriptionTile(
            key: ValueKey('subscription-${a.id}'),
            admission: a,
            onTap: () => open('/admissions/${a.id}'),
          ),
        if (s.next != null)
          OutlinedButton(
            onPressed: s.loading ? null : () => cubit.load(more: true),
            child: const Text('Load more'),
          ),
        SizedBox(height: 72.h),
      ],
    ),
  );
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    super.key,
    required this.admission,
    required this.onTap,
  });
  final Admission admission;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = admission, theme = Theme.of(context);
    final sub = a.subscription;
    final currency =
        context.read<WorkspaceCubit>().state.data.organization?.currency ??
        'INR';
    final status = a.status == 'cancelled' ? 'stopped' : a.status;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.customer.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                AdmissionTag(
                  admissionStatusLabel(status),
                  color: admissionStatusColor(context, a.status),
                ),
              ],
            ),
            Text(a.customer.phone),
            Text(
              '${a.poolName.isEmpty ? a.businessName : a.poolName} · ${weekdayNames(a.weekdays)} · ${TimeFormat.display(a.time)} · ${hoursLabel(a.duration)}',
            ),
            if (sub != null)
              Text(
                '${bookingMoney(sub.monthly, currency)}${sub.months == null ? '' : ' / month'} · ${sub.periodLabel} · ${a.start} to ${a.expiry}',
                style: theme.textTheme.bodySmall,
              ),
            if (a.owedNow > 0)
              Text(
                '${bookingMoney(a.owedNow, currency)} due now',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (a.nextDueOn != null && a.nextDue != null)
              Text(
                'Next ${bookingMoney(a.nextDue!, currency)} on ${a.nextDueOn}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
