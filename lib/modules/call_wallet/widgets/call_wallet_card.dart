import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import '../../../design_system/design_system.dart';
import '../cubit/call_wallet_cubit.dart';
import '../models/call_wallet_models.dart';

/// Opens the Recharge page; the balance is read again when the owner returns.
Future<void> openRecharge(BuildContext context, CallWalletCubit cubit) async {
  await context.push(Routes.callWalletRecharge);
  await cubit.load();
}

class WalletLowBadge extends StatelessWidget {
  const WalletLowBadge({super.key, required this.wallet});
  final CallWallet wallet;
  @override
  Widget build(BuildContext context) => AppStatusBadge(
    label: wallet.empty ? 'Recharge needed' : 'Low balance',
    icon: Icons.warning_amber_rounded,
    color: Theme.of(context).colorScheme.error,
  );
}

String rechargePhaseLabel(RechargePhase phase) => switch (phase) {
  RechargePhase.creating => 'Preparing payment…',
  RechargePhase.checkout => 'Waiting for payment…',
  RechargePhase.confirming => 'Confirming payment…',
  RechargePhase.idle => 'Recharge',
};

class RechargeNoticeBanner extends StatelessWidget {
  const RechargeNoticeBanner({super.key, required this.notice, this.onClose});
  final RechargeNotice notice;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final waiting = notice.status == RechargeStatus.pending;
    final color = notice.success
        ? c.primaryContainer
        : waiting
        ? c.secondaryContainer
        : c.errorContainer;
    return Container(
      key: const ValueKey('recharge-notice'),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            notice.success
                ? Icons.check_circle_outline_rounded
                : waiting
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(notice.message)),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class WalletEntryTile extends StatelessWidget {
  const WalletEntryTile({super.key, required this.entry});
  final WalletEntry entry;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final credit = entry.amountPaise >= 0;
    final local = MaterialLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.kind == WalletEntryKind.callCharge
            ? Icons.phone_in_talk_outlined
            : credit
            ? Icons.add_card_rounded
            : Icons.remove_circle_outline_rounded,
      ),
      title: Text(entry.title),
      subtitle: Text(
        [
          '${local.formatMediumDate(entry.createdAt)}, '
              '${local.formatTimeOfDay(TimeOfDay.fromDateTime(entry.createdAt))}',
          if (entry.details.isNotEmpty) entry.details,
        ].join('\n'),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${credit ? '+' : ''}${rupees(entry.amountPaise)}',
            style: t.textTheme.titleSmall?.copyWith(
              color: credit ? t.colorScheme.primary : null,
            ),
          ),
          Text(
            'Bal ${rupees(entry.balanceAfterPaise)}',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Balance, recharge and recent activity on the Call booking page.
class CallWalletCard extends StatelessWidget {
  const CallWalletCard({
    super.key,
    required this.cubit,
    this.showRecent = true,
  });
  final CallWalletCubit cubit;
  final bool showRecent;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CallWalletCubit, CallWalletState>(
    bloc: cubit,
    builder: (context, s) {
      final t = Theme.of(context), w = s.wallet;
      return AppCard(
        key: const ValueKey('call-wallet-card'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Call wallet', style: t.textTheme.titleLarge),
                if (!s.loading && w.low) WalletLowBadge(wallet: w),
              ],
            ),
            const SizedBox(height: 16),
            if (s.loading)
              const AppRefreshIndicator(label: 'Loading wallet…')
            else ...[
              Text(
                rupees(w.balancePaise),
                key: const ValueKey('call-wallet-balance'),
                style: t.textTheme.displaySmall,
              ),
              if (w.rateSet) ...[
                const SizedBox(height: 4),
                Text(
                  'About ${w.minutesLeft} minutes of calls · '
                  '${rupees(w.ratePaisePerMinute)} per minute',
                ),
              ],
              if (w.low) ...[
                const SizedBox(height: 12),
                Text(
                  w.empty
                      ? 'Your balance has run out. Recharge so callers can keep booking by phone.'
                      : 'Your balance is running low. Recharge to avoid interruptions.',
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.error,
                  ),
                ),
              ],
            ],
            if (s.notice != null) ...[
              const SizedBox(height: 16),
              RechargeNoticeBanner(
                notice: s.notice!,
                onClose: cubit.dismissNotice,
              ),
            ],
            if (s.error != null) ...[
              const SizedBox(height: 16),
              AppErrorWidget(
                message: s.error!,
                onRetry: s.recharging ? null : cubit.load,
              ),
            ],
            const SizedBox(height: 20),
            AppButton(
              key: const ValueKey('call-wallet-recharge'),
              label: 'Recharge',
              busyLabel: rechargePhaseLabel(s.phase),
              busy: s.recharging,
              icon: Icons.account_balance_wallet_outlined,
              onPressed: s.loading || !w.rechargeEnabled
                  ? null
                  : () => openRecharge(context, cubit),
            ),
            if (!s.loading && !w.rechargeEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'Online recharge is not available yet. Contact support to add balance.',
                style: t.textTheme.bodySmall,
              ),
            ],
            if (showRecent && w.entries.isNotEmpty) ...[
              const Divider(height: 32),
              Text('Recent activity', style: t.textTheme.titleSmall),
              for (final entry in w.entries.take(3))
                WalletEntryTile(entry: entry),
              TextButton(
                onPressed: () => context.push(Routes.callWallet),
                child: const Text('View all transactions'),
              ),
            ],
          ],
        ),
      );
    },
  );
}
