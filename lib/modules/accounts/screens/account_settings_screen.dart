import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/accounts_cubits.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';
import '../widgets/accounts_widgets.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final cubit = getIt<AccountSettingsCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) cubit.load();
  }

  Future<void> _accountAction(String action, MoneyAccount account) async {
    if (action == 'primary') {
      await cubit.primary(account.id);
      return;
    }
    if (action == 'rename') {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RenameAccountDialog(name: account.name),
      );
      if (mounted && name != null) await cubit.rename(account.id, name);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Archive bank account?'),
        content: const Text(
          'Transaction history is retained. Replace any primary setting or payment mappings first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (mounted && yes == true) await cubit.archive(account.id);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => BlocBuilder<AccountSettingsCubit, AccountSettingsModel>(
      bloc: cubit,
      builder: (c, s) {
        final catalog = s.catalog;
        final banks =
            catalog?.accounts
                .where((a) => a.kind == 'bank' && a.active)
                .toList() ??
            <MoneyAccount>[];
        final archived =
            catalog?.accounts.where((a) => !a.active).toList() ??
            <MoneyAccount>[];
        if (isDesktopWidth(c) && box.maxWidth >= AppPage.wideWidth) {
          return _desktop(c, s, banks, archived);
        }
        final theme = Theme.of(c);
        return AppPage(
          title: 'Account settings',
          showAppBar: true,
          back: true,
          compactHeader: true,
          children: [
            if (s.loading)
              AppLoadingState(
                initial: s.catalog == null,
                label: s.catalog == null ? 'Loading bank accounts…' : null,
              )
            else if (s.busy)
              const AppSavingIndicator(label: 'Saving settings…'),
            if (s.error != null)
              AppErrorWidget(message: s.error!, onRetry: cubit.load),
            if (catalog != null && !catalog.canManage)
              const AppEmptyState(
                title: 'Owner access required',
                message:
                    'Only the owner can manage bank accounts and payment routing.',
              ),
            if (catalog?.canManage == true) ...[
              Text(
                'Your money, organised.',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage balances and decide where payments go.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              for (final account in catalog!.accounts.where(
                (a) => a.active && a.kind == 'cash',
              ))
                _AccountBalanceCard(
                  account: account,
                  currency: catalog.currency,
                  footer: !account.openingSet
                      ? TextButton.icon(
                          onPressed: s.busy
                              ? null
                              : () => _open('/accounts/cash/opening'),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Set opening cash balance'),
                        )
                      : null,
                ),
              const SizedBox(height: 12),
              AppCard(
                onTap: s.busy ? null : () => _open('/accounts/entry/transfer'),
                child: Row(
                  children: [
                    const _SettingsIcon(Icons.swap_horiz_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transfer money',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Move money between cash and banks',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              _SettingsHeading(
                title: 'Bank accounts',
                subtitle:
                    '${banks.length} active ${banks.length == 1 ? 'account' : 'accounts'}',
              ),
              const SizedBox(height: 12),
              if (banks.isEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SettingsIcon(Icons.account_balance_outlined),
                      const SizedBox(height: 14),
                      Text(
                        'Add your first bank account',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Your first account becomes the primary destination for digital payments.',
                      ),
                    ],
                  ),
                ),
              for (final account in banks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AccountBalanceCard(
                    account: account,
                    currency: catalog.currency,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Manage ${account.name}',
                      enabled: !s.busy,
                      onSelected: (action) => _accountAction(action, account),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        if (!account.primary)
                          const PopupMenuItem(
                            value: 'primary',
                            child: Text('Set as primary'),
                          ),
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive account'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (banks.isEmpty) const SizedBox(height: 12),
              AppButton(
                label: 'Add bank account',
                icon: Icons.add_rounded,
                secondary: banks.isNotEmpty,
                onPressed: s.busy ? null : () => _open('/accounts/bank/new'),
              ),
              const SizedBox(height: 10),
              Text(
                'Balances reflect your opening balance and recorded entries.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 26),
              const _SettingsHeading(
                title: 'Payment routing',
                subtitle: 'Choose where digital payments arrive',
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.alt_route_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A space setting overrides its business default. Otherwise, the primary bank is used. Cash goes to Cash in hand.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (banks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Add a bank account to set up UPI, card and bank transfer destinations.',
                  ),
                ),
              if (catalog.businesses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Your businesses will appear here once they are added.',
                  ),
                ),
              for (final business in orderedWorkspaceBusinesses(
                context,
                catalog.businesses,
                (b) => b.id,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      key: PageStorageKey('routing-${business.id}'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      title: Text(
                        business.name,
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        '${business.spaces.length} ${business.spaces.length == 1 ? 'space' : 'spaces'} · Payment destinations',
                        style: theme.textTheme.bodySmall,
                      ),
                      children: [
                        const Divider(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Business default',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        _routes(
                          catalog,
                          business,
                          null,
                          s.busy || banks.isEmpty,
                        ),
                        for (final space in business.spaces)
                          ExpansionTile(
                            key: PageStorageKey(
                              'routing-${business.id}-${space.id}',
                            ),
                            tilePadding: EdgeInsets.zero,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              space.name,
                              style: theme.textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              'Individual space settings',
                              style: theme.textTheme.bodySmall,
                            ),
                            children: [
                              _routes(
                                catalog,
                                business,
                                space,
                                s.busy || banks.isEmpty,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              for (final account in catalog.accounts.where(
                (a) => a.active && a.kind == 'clearing',
              )) ...[
                const SizedBox(height: 12),
                _AccountBalanceCard(
                  account: account,
                  currency: catalog.currency,
                  footer: const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Historical or unmapped digital payments. Transfer these to the bank that received them.',
                    ),
                  ),
                ),
              ],
              if (archived.isNotEmpty)
                ExpansionTile(
                  key: const PageStorageKey('account-settings-archived'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Archived accounts (${archived.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: const Text('Kept for your transaction history'),
                  children: [
                    for (final account in archived)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AccountBalanceCard(
                          account: account,
                          currency: catalog.currency,
                        ),
                      ),
                  ],
                ),
            ],
          ],
        );
      },
    ),
  );

  // Wide web windows: headline balances, account grid and routing side panel.
  Widget _desktop(
    BuildContext c,
    AccountSettingsModel s,
    List<MoneyAccount> banks,
    List<MoneyAccount> archived,
  ) {
    final catalog = s.catalog;
    final theme = Theme.of(c), scheme = theme.colorScheme;
    final manage = catalog?.canManage == true;
    return AppPage(
      title: 'Account settings',
      back: true,
      showAppBar: true,
      maxWidth: 1200,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account settings', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Your money, organised. Manage balances and decide where payments go.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
          if (manage) ...[
            OutlinedButton.icon(
              onPressed: s.busy
                  ? null
                  : () => _open('/accounts/entry/transfer'),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Transfer money'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: s.busy ? null : () => _open('/accounts/bank/new'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add bank account'),
            ),
          ],
        ],
      ),
      children: [
        if (s.loading)
          AppLoadingState(
            initial: catalog == null,
            label: catalog == null ? 'Loading bank accounts…' : null,
          )
        else if (s.busy)
          const AppSavingIndicator(label: 'Saving settings…'),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (catalog != null && !catalog.canManage)
          const AppEmptyState(
            title: 'Owner access required',
            message:
                'Only the owner can manage bank accounts and payment routing.',
          ),
        if (catalog != null && manage) ...[
          _desktopStats(catalog, banks),
          const SizedBox(height: 28),
          AppTwoPane(
            primaryFlex: 3,
            secondaryFlex: 2,
            primary: [
              AppPanel(
                title: 'Money accounts',
                subtitle:
                    '${banks.length} active bank ${banks.length == 1 ? 'account' : 'accounts'} · balances reflect your opening balance and recorded entries',
                child: _EvenGrid(
                  children: [
                    for (final account in catalog.accounts.where(
                      (a) => a.active && a.kind == 'cash',
                    ))
                      _AccountBalanceCard(
                        account: account,
                        currency: catalog.currency,
                        footer: !account.openingSet
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: TextButton.icon(
                                  onPressed: s.busy
                                      ? null
                                      : () => _open('/accounts/cash/opening'),
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Set opening cash balance'),
                                ),
                              )
                            : null,
                      ),
                    for (final account in banks)
                      _AccountBalanceCard(
                        account: account,
                        currency: catalog.currency,
                        trailing: _bankMenu(account, s.busy),
                      ),
                    for (final account in catalog.accounts.where(
                      (a) => a.active && a.kind == 'clearing',
                    ))
                      _AccountBalanceCard(
                        account: account,
                        currency: catalog.currency,
                        footer: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Historical or unmapped digital payments. Transfer these to the bank that received them.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    _AddAccountTile(
                      first: banks.isEmpty,
                      onTap: s.busy ? null : () => _open('/accounts/bank/new'),
                    ),
                  ],
                ),
              ),
              if (archived.isNotEmpty)
                AppPanel(
                  title: 'Archived accounts (${archived.length})',
                  subtitle: 'Kept for your transaction history',
                  child: _EvenGrid(
                    children: [
                      for (final account in archived)
                        _AccountBalanceCard(
                          account: account,
                          currency: catalog.currency,
                        ),
                    ],
                  ),
                ),
            ],
            secondary: [
              AppPanel(
                title: 'Payment routing',
                subtitle: 'Choose where digital payments arrive',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.alt_route_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'A space setting overrides its business default. Otherwise, the primary bank is used. Cash goes to Cash in hand.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (banks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Add a bank account to set up UPI, card and bank transfer destinations.',
                        ),
                      ),
                    if (catalog.businesses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Your businesses will appear here once they are added.',
                        ),
                      ),
                    for (final business in orderedWorkspaceBusinesses(
                      c,
                      catalog.businesses,
                      (b) => b.id,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _desktopRouting(
                          catalog,
                          business,
                          s.busy || banks.isEmpty,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _bankMenu(MoneyAccount account, bool busy) => PopupMenuButton<String>(
    tooltip: 'Manage ${account.name}',
    enabled: !busy,
    onSelected: (action) => _accountAction(action, account),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'rename', child: Text('Rename')),
      if (!account.primary)
        const PopupMenuItem(value: 'primary', child: Text('Set as primary')),
      const PopupMenuItem(value: 'archive', child: Text('Archive account')),
    ],
  );

  Widget _desktopStats(FinanceCatalog catalog, List<MoneyAccount> banks) {
    String money(int n) => financeMoney(n, catalog.currency);
    final cash = catalog.accounts
        .where((a) => a.active && a.kind == 'cash')
        .firstOrNull;
    final bankTotal = banks.any((a) => a.balance == null)
        ? null
        : banks.fold<int>(0, (sum, a) => sum + a.balance!);
    final primary = banks.where((a) => a.primary).firstOrNull;
    final spaces = catalog.businesses.fold<int>(
      0,
      (sum, b) => sum + b.spaces.length,
    );
    return AppStatRow(
      children: [
        AppStatTile(
          icon: Icons.account_balance_outlined,
          label: 'In bank accounts',
          value: banks.isEmpty
              ? money(0)
              : bankTotal == null
              ? 'Unavailable'
              : money(bankTotal),
          caption:
              '${banks.length} active ${banks.length == 1 ? 'account' : 'accounts'}',
          highlight: true,
        ),
        AppStatTile(
          icon: Icons.payments_outlined,
          label: 'Cash in hand',
          value: cash?.balance == null ? 'Unavailable' : money(cash!.balance!),
          caption: cash == null || cash.openingSet
              ? 'Recorded balance'
              : 'Opening balance not set',
        ),
        AppStatTile(
          icon: Icons.star_outline_rounded,
          label: 'Primary bank',
          value: primary?.name ?? 'Not set',
          caption: 'Default for digital payments',
        ),
        AppStatTile(
          icon: Icons.alt_route_rounded,
          label: 'Custom routes',
          value: '${catalog.routes.length}',
          caption:
              '${catalog.businesses.length} ${catalog.businesses.length == 1 ? 'business' : 'businesses'} · $spaces ${spaces == 1 ? 'space' : 'spaces'}',
        ),
      ],
    );
  }

  Widget _desktopRouting(
    FinanceCatalog catalog,
    FinanceBusiness business,
    bool busy,
  ) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const _SettingsIcon(Icons.storefront_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(business.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${business.spaces.length} ${business.spaces.length == 1 ? 'space' : 'spaces'} · Payment destinations',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'BUSINESS DEFAULT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _routes(catalog, business, null, busy),
          ),
          for (final space in business.spaces) ...[
            Divider(height: 1, color: scheme.outline.withValues(alpha: .35)),
            ExpansionTile(
              key: PageStorageKey('routing-${business.id}-${space.id}'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(space.name, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                'Individual space settings',
                style: theme.textTheme.bodySmall,
              ),
              children: [_routes(catalog, business, space, busy)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _routes(
    FinanceCatalog catalog,
    FinanceBusiness business,
    FinanceSpace? space,
    bool busy,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      children: [
        for (final method in ['upi', 'card', 'bank_transfer'])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppPicker(
              label: financeLabel(method),
              value:
                  catalog.routes
                      .where(
                        (r) =>
                            r.businessId == business.id &&
                            r.spaceId == space?.id &&
                            r.method == method,
                      )
                      .firstOrNull
                      ?.accountId ??
                  '',
              enabled: !busy,
              items: [
                PickerItem(
                  '',
                  space == null ? 'Use primary bank' : 'Use business default',
                ),
                ...catalog.accounts
                    .where((a) => a.kind == 'bank' && a.active)
                    .map((a) => PickerItem(a.id, a.name)),
              ],
              onChanged: (value) => cubit.route(
                business.id,
                space?.id,
                method,
                value.isEmpty ? null : value,
              ),
            ),
          ),
      ],
    ),
  );
}

class _RenameAccountDialog extends StatefulWidget {
  const _RenameAccountDialog({required this.name});
  final String name;
  @override
  State<_RenameAccountDialog> createState() => _RenameAccountDialogState();
}

class _RenameAccountDialogState extends State<_RenameAccountDialog> {
  late final input = TextEditingController(text: widget.name);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename bank account'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: input,
        maxLength: 100,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Account display name'),
        validator: (value) => (value?.trim().length ?? 0) < 2
            ? 'Enter at least 2 characters'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, input.text.trim());
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

/// Two-column card grid whose rows share the tallest card's height.
class _EvenGrid extends StatelessWidget {
  const _EvenGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 600 ? 2 : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: i + columns < children.length ? 16 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + columns; j++) ...[
                      if (j > i) const SizedBox(width: 16),
                      Expanded(
                        child: j < children.length
                            ? children[j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Desktop grid tile that opens the add-bank-account flow.
class _AddAccountTile extends StatelessWidget {
  const _AddAccountTile({required this.first, this.onTap});
  final bool first;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return AppCard(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 150),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .5),
                  width: 1.5,
                ),
              ),
              child: Icon(Icons.add_rounded, color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              first
                  ? 'Add your first bank account'
                  : 'Add another bank account',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              first
                  ? 'It becomes the primary destination for digital payments.'
                  : 'Route UPI, card or transfers to it per business.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
  );
}

class _AccountBalanceCard extends StatelessWidget {
  const _AccountBalanceCard({
    required this.account,
    required this.currency,
    this.trailing,
    this.footer,
  });
  final MoneyAccount account;
  final String currency;
  final Widget? trailing, footer;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsIcon(
                account.kind == 'cash'
                    ? Icons.payments_outlined
                    : account.kind == 'bank'
                    ? Icons.account_balance_outlined
                    : Icons.inbox_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: theme.textTheme.titleSmall),
                    if (account.kind == 'bank' && account.bankName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${account.bankName}${account.accountNumber.isNotEmpty || account.lastFour.isEmpty ? '' : ' · •••• ${account.lastFour}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (account.kind == 'bank' &&
                        account.accountNumber.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SelectableText(
                          'Account number: ${account.accountNumber}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (account.primary || !account.active)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          account.active ? 'PRIMARY ACCOUNT' : 'ARCHIVED',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: account.active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          Text(
            account.kind == 'cash' ? 'Cash in hand' : 'Recorded balance',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            account.balance == null
                ? 'Unavailable'
                : financeMoney(account.balance!, currency),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key, this.cash = false});
  final bool cash;
  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  late final cubit = getIt<BankAccountCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.cash,
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<BankAccountCubit, BankAccountModel>(
    bloc: cubit,
    listener: (c, s) {
      if (s.saved) c.pop();
    },
    builder: (c, s) => AppPage(
      title: widget.cash ? 'Cash opening balance' : 'Add bank account',
      back: true,
      showAppBar: true,
      compactHeader: true,
      children: [
        Text(
          '${widget.cash ? 'Set the amount of cash you held at this time. ' : 'Your first bank account becomes primary automatically. '}Opening balance is the balance immediately before entries at the selected time. Entries before this time remain in history and are not added again. ',
        ),
        const SizedBox(height: 20),
        if (!widget.cash)
          _field(
            'Account display name',
            s.name,
            (v) => cubit.update(name: v),
            s,
          ),
        if (!widget.cash)
          _field('Bank name', s.bank, (v) => cubit.update(bank: v), s),
        if (!widget.cash)
          _field(
            'Full account number',
            s.accountNumber,
            (v) => cubit.update(accountNumber: v),
            s,
            numeric: true,
          ),
        _field(
          'Opening balance',
          s.opening,
          (v) => cubit.update(opening: v),
          s,
          numeric: true,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Opening balance date & time'),
          subtitle: Text(
            '${financeStamp(s.date.toLocal().toString())} · device local time',
          ),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: s.busy
              ? null
              : () async {
                  final date = await chooseFinanceDateTime(c, s.date);
                  if (date != null) cubit.update(date: date);
                },
        ),
        if (!widget.cash)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as primary bank'),
            value: s.primary,
            onChanged: s.busy ? null : (v) => cubit.update(primary: v),
          ),
        if (s.error != null) AppErrorWidget(message: s.error!),
        const SizedBox(height: 20),
        AppButton(
          label: widget.cash ? 'Set opening balance' : 'Save bank account',
          busy: s.busy,
          onPressed: cubit.save,
        ),
      ],
    ),
  );
  Widget _field(
    String label,
    String value,
    ValueChanged<String> onChanged,
    BankAccountModel s, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      initialValue: value,
      enabled: !s.busy && cubit.pending == null,
      onChanged: onChanged,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
