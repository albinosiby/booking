import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/call_wallet_cubit.dart';
import '../models/call_wallet_models.dart';
import '../widgets/call_wallet_card.dart';

/// Plans and the custom amount come from the API, so admins change them
/// without an app release. The server checks the amount again.
class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});
  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  late final cubit = getIt<CallWalletCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final amount = TextEditingController();
  final form = GlobalKey<FormState>();
  int? plan;
  bool custom = false;

  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    amount.dispose();
    cubit.close();
    super.dispose();
  }

  int? get customPaise {
    final value = int.tryParse(amount.text.trim());
    return value == null ? null : value * 100;
  }

  /// The second plan is preselected, as the usual top-up; a lone plan is chosen.
  int? selectedPlan(CallWallet w) {
    if (custom) return null;
    if (plan != null && w.plansPaise.contains(plan)) return plan;
    if (w.plansPaise.isEmpty) return null;
    return w.plansPaise[w.plansPaise.length > 1 ? 1 : 0];
  }

  int? chosen(CallWallet w) => custom ? customPaise : selectedPlan(w);

  void pay(CallWallet w) {
    if (custom && !form.currentState!.validate()) return;
    final value = chosen(w);
    if (value != null) cubit.recharge(value);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CallWalletCubit, CallWalletState>(
    bloc: cubit,
    builder: (context, s) {
      final t = Theme.of(context), w = s.wallet, value = chosen(w);
      final paid = s.notice?.success == true;
      return AppPage(
        title: 'Recharge',
        subtitle: 'Add balance for your call booking service.',
        back: true,
        showAppBar: true,
        compactHeader: true,
        maxWidth: 720,
        scrollId: 'call-wallet-recharge',
        children: [
          if (!cubit.owner)
            const AppEmptyState(
              title: 'Owner access required',
              message: 'Only the owner can recharge the call wallet.',
              icon: Icons.lock_outline,
            )
          else if (s.loading)
            const AppRefreshIndicator(label: 'Loading wallet…')
          else ...[
            _BalanceCard(wallet: w),
            const SizedBox(height: 20),
            if (s.notice != null) ...[
              RechargeNoticeBanner(
                notice: s.notice!,
                onClose: cubit.dismissNotice,
              ),
              const SizedBox(height: 16),
            ],
            if (paid) ...[
              AppButton(
                key: const ValueKey('recharge-done'),
                label: 'Done',
                icon: Icons.check_rounded,
                onPressed: () => context.canPop()
                    ? context.pop(true)
                    : cubit.dismissNotice(),
              ),
              const SizedBox(height: 20),
            ],
            if (s.error != null) ...[
              AppErrorWidget(
                message: s.error!,
                onRetry: s.recharging ? null : cubit.load,
              ),
              const SizedBox(height: 16),
            ],
            if (!w.rechargeEnabled)
              const AppEmptyState(
                title: 'Online recharge is not available yet',
                message: 'Contact support to add balance to your wallet.',
                icon: Icons.account_balance_wallet_outlined,
              )
            else
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Choose a plan', style: t.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Calls are charged ${rupees(w.ratePaisePerMinute)} per started minute.',
                      ),
                      const SizedBox(height: 16),
                      _PlanGrid(
                        children: [
                          for (final p in w.plansPaise)
                            _PlanTile(
                              key: ValueKey('recharge-plan-$p'),
                              title: rupees(p),
                              caption: 'About ${w.minutesFor(p)} min',
                              selected: selectedPlan(w) == p,
                              onTap: s.recharging
                                  ? null
                                  : () => setState(() {
                                      plan = p;
                                      custom = false;
                                    }),
                            ),
                          if (w.customEnabled)
                            _PlanTile(
                              key: const ValueKey('recharge-plan-custom'),
                              title: 'Custom',
                              caption: 'Enter an amount',
                              icon: Icons.edit_outlined,
                              selected: custom,
                              onTap: s.recharging
                                  ? null
                                  : () => setState(() => custom = true),
                            ),
                        ],
                      ),
                      if (custom) ...[
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const ValueKey('recharge-amount'),
                          controller: amount,
                          autofocus: true,
                          enabled: !s.recharging,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                            helperText:
                                'From ${rupees(w.customMinPaise)} to ${rupees(w.customMaxPaise)}'
                                '${customPaise != null && w.minutesFor(customPaise!) > 0 ? ' · about ${w.minutesFor(customPaise!)} min' : ''}',
                          ),
                          validator: (_) => w.customError(customPaise),
                          onChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) => pay(w),
                        ),
                      ],
                      const SizedBox(height: 24),
                      AppButton(
                        key: const ValueKey('recharge-pay'),
                        label: value == null ? 'Pay' : 'Pay ${rupees(value)}',
                        busyLabel: rechargePhaseLabel(s.phase),
                        busy: s.recharging,
                        icon: Icons.lock_outline_rounded,
                        onPressed: value == null ? null : () => pay(w),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Payments are processed securely by Cashfree.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet});
  final CallWallet wallet;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), w = wallet;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Current balance', style: t.textTheme.titleSmall),
              if (w.low) WalletLowBadge(wallet: w),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rupees(w.balancePaise),
            key: const ValueKey('recharge-balance'),
            style: t.textTheme.displaySmall,
          ),
          if (w.rateSet) ...[
            const SizedBox(height: 4),
            Text(
              'About ${w.minutesLeft} minutes of calls · '
              '${rupees(w.ratePaisePerMinute)} per minute',
            ),
          ],
        ],
      ),
    );
  }
}

/// Two plans per row on phones, up to four on wider screens.
class _PlanGrid extends StatelessWidget {
  const _PlanGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final columns = box.maxWidth >= 520 ? 4 : 2;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    super.key,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String title, caption;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), c = t.colorScheme;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primaryContainer : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? c.primary : c.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: t.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded, color: c.primary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(caption, style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
