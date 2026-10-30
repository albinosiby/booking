import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../bookings/models/booking_models.dart' show bookingMoney;
import '../cubit/expired_members_cubit.dart';
import '../repositories/admission_repository.dart';

class ExpiredMembersSection extends StatefulWidget {
  const ExpiredMembersSection({
    super.key,
    required this.repository,
    required this.canRenew,
    required this.canCollect,
    required this.showAmounts,
    required this.currency,
  });
  final MembershipActions repository;
  final bool canRenew, canCollect, showAmounts;
  final String currency;
  @override
  State<ExpiredMembersSection> createState() => _ExpiredMembersSectionState();
}

class _ExpiredMembersSectionState extends State<ExpiredMembersSection>
    with WidgetsBindingObserver {
  late final cubit = ExpiredMembersCubit(widget.repository)..load();
  Timer? timer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (foreground) cubit.load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) cubit.load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    cubit.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (mounted) cubit.load();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ExpiredMembersCubit, ExpiredMembersState>(
    bloc: cubit,
    builder: (context, state) {
      if (!state.loading && state.error == null && state.items.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Expired members · action needed',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh expired members',
                    onPressed: state.loading ? null : () => cubit.load(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const Text(
                'Renew a plan, collect outstanding fees, or open membership details to delete it while keeping history and dues.',
              ),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (state.error != null) AppErrorWidget(message: state.error!),
              for (final admission in state.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admission.customer.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${admission.planName} · ${admission.kind == 'coaching' ? 'Coaching' : 'Plan'} · ${admission.businessName}',
                      ),
                      Text('Expired ${admission.expiry}'),
                      if (widget.showAmounts)
                        Text(
                          '${widget.canRenew && widget.canCollect && admission.canRenew ? 'Previous plan due' : 'Amount due'}: ${bookingMoney(admission.balance, widget.currency)}',
                        ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (widget.canRenew && admission.canRenew)
                            FilledButton.icon(
                              onPressed: () => open(
                                '/admissions/new?renewal_id=${admission.id}${widget.canCollect ? '&collect=true' : ''}',
                              ),
                              icon: const Icon(Icons.autorenew),
                              label: Text(
                                widget.canCollect ? 'Renew & collect' : 'Renew',
                              ),
                            ),
                          if (widget.canCollect &&
                              admission.balance > 0 &&
                              !(widget.canRenew && admission.canRenew))
                            OutlinedButton.icon(
                              onPressed: () => open(
                                '/admissions/${admission.id}?collect=true',
                              ),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Collect amount'),
                            ),
                          TextButton(
                            onPressed: () =>
                                open('/admissions/${admission.id}'),
                            child: const Text('View membership'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (state.next != null)
                OutlinedButton(
                  onPressed: state.loading
                      ? null
                      : () => cubit.load(more: true),
                  child: const Text('Load more expired members'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
