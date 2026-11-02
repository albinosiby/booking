import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/call_wallet_cubit.dart';
import '../widgets/call_wallet_card.dart';

/// Full wallet history with recharge.
class CallWalletScreen extends StatefulWidget {
  const CallWalletScreen({super.key, this.returnOrderId});

  /// Set when Cashfree's web checkout redirects back after a payment.
  final String? returnOrderId;
  @override
  State<CallWalletScreen> createState() => _CallWalletScreenState();
}

class _CallWalletScreenState extends State<CallWalletScreen> {
  late final cubit = getIt<CallWalletCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void initState() {
    super.initState();
    final order = widget.returnOrderId;
    if (order != null && order.startsWith('booking_')) {
      cubit.confirmReturn(order);
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
  Widget build(BuildContext context) =>
      BlocBuilder<CallWalletCubit, CallWalletState>(
        bloc: cubit,
        builder: (context, s) => AppPage(
          title: 'Call wallet',
          subtitle: 'Recharges and call charges for your call service.',
          back: true,
          showAppBar: true,
          compactHeader: true,
          maxWidth: 900,
          scrollId: 'call-wallet',
          actions: [
            IconButton(
              tooltip: 'Refresh wallet',
              onPressed: s.loading || s.recharging ? null : cubit.load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          children: [
            if (!cubit.owner)
              const AppEmptyState(
                title: 'Owner access required',
                message: 'Only the owner can manage the call wallet.',
                icon: Icons.lock_outline,
              )
            else ...[
              CallWalletCard(cubit: cubit, showRecent: false),
              const SizedBox(height: 20),
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Transactions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!s.loading && s.wallet.entries.isEmpty)
                      const Text('No recharges or call charges yet.'),
                    for (final entry in s.wallet.entries)
                      WalletEntryTile(entry: entry),
                    if (s.wallet.nextOffset != null)
                      AppButton(
                        label: 'Load more',
                        secondary: true,
                        busy: s.loadingMore,
                        onPressed: cubit.loadMore,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}
