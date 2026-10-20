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

class FinanceEntryScreen extends StatefulWidget {
  const FinanceEntryScreen({super.key, required this.kind});
  final String kind;
  @override
  State<FinanceEntryScreen> createState() => _FinanceEntryScreenState();
}

class _FinanceEntryScreenState extends State<FinanceEntryScreen> {
  late final cubit = getIt<FinanceEntryCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.kind,
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<FinanceEntryCubit, FinanceEntryModel>(
    bloc: cubit,
    listener: (c, s) {
      if (s.saved) {
        showMessage(
          c,
          '${s.kind == 'transfer' ? 'Transfer' : 'Entry'} recorded.',
        );
        c.pop();
      }
    },
    builder: (c, s) {
      final catalog = s.catalog,
          transfer = s.kind == 'transfer',
          expense = s.kind == 'expense',
          enabled = cubit.editable;
      return AppPage(
        title: transfer
            ? 'Transfer money'
            : expense
            ? 'Add expense'
            : 'Add extra income',
        back: true,
        showAppBar: true,
        compactHeader: true,
        children: [
          if (s.loading)
            AppLoadingState(
              initial: s.catalog == null,
              label: s.catalog == null ? 'Loading accounts…' : null,
            ),
          if (s.error != null)
            AppErrorWidget(
              message: s.error!,
              onRetry: catalog == null ? cubit.load : null,
            ),
          if (catalog != null) ...[
            if (!transfer) ...[
              FinanceScopePicker(
                catalog: catalog,
                business: s.businessId,
                space: s.spaceId,
                onChanged: cubit.scope,
                sharedLabel: 'Whole organization / shared',
                enabled: enabled,
              ),
              const SizedBox(height: 16),
            ],
            if (transfer) ...[
              const Text(
                'Move money between your accounts. This does not count as income or an expense.',
              ),
              const SizedBox(height: 16),
            ],
            _text(
              'Category',
              s.category,
              (v) => cubit.fields(category: v),
              enabled,
            ),
            _text(
              expense
                  ? 'Reason for expense'
                  : transfer
                  ? 'Reason for transfer'
                  : 'Reason for extra income',
              s.reason,
              (v) => cubit.fields(reason: v),
              enabled,
              maxLines: 3,
            ),
            _text(
              'Reference · optional',
              s.reference,
              (v) => cubit.fields(reference: v),
              enabled,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Transaction date & time'),
              subtitle: Text(
                '${financeStamp(s.date.toLocal().toString())} · device local time',
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: !enabled
                  ? null
                  : () async {
                      final date = await chooseFinanceDateTime(c, s.date);
                      if (date != null) cubit.fields(date: date);
                    },
            ),
            for (var i = 0; i < s.lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              transfer ? 'From account' : 'Payment ${i + 1}',
                              style: Theme.of(c).textTheme.titleMedium,
                            ),
                          ),
                          if (!transfer && s.lines.length > 1)
                            IconButton(
                              tooltip: 'Remove split',
                              onPressed: enabled ? () => cubit.remove(i) : null,
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!transfer) ...[
                        AppPicker(
                          label: 'Payment method',
                          value: s.lines[i].method,
                          enabled: enabled,
                          items: const [
                            PickerItem('cash', 'Cash'),
                            PickerItem('upi', 'UPI'),
                            PickerItem('card', 'Card'),
                            PickerItem('bank_transfer', 'Bank transfer'),
                          ],
                          onChanged: (v) => cubit.method(i, v),
                        ),
                        const SizedBox(height: 14),
                      ],
                      AppPicker(
                        label: transfer
                            ? 'From'
                            : expense
                            ? 'Paid from'
                            : 'Received into',
                        value: s.lines[i].accountId,
                        enabled: enabled,
                        items: catalog.accounts
                            .where(
                              (a) =>
                                  a.active &&
                                  (transfer ||
                                      (s.lines[i].method == 'cash'
                                          ? a.kind == 'cash'
                                          : a.kind == 'bank')),
                            )
                            .map((a) => PickerItem(a.id, a.name))
                            .toList(),
                        onChanged: (v) =>
                            cubit.line(i, s.lines[i].copyWith(accountId: v)),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: ValueKey('finance-amount-${s.lines[i].id}'),
                        initialValue: s.lines[i].amount,
                        enabled: enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount · ${catalog.currency}',
                        ),
                        onChanged: (v) =>
                            cubit.line(i, s.lines[i].copyWith(amount: v)),
                      ),
                    ],
                  ),
                ),
              ),
            if (transfer) ...[
              const SizedBox(height: 12),
              AppPicker(
                label: 'To account',
                value: s.toAccountId,
                enabled: enabled,
                items: catalog.accounts
                    .where(
                      (a) =>
                          a.active &&
                          a.kind != 'clearing' &&
                          a.id != s.lines.first.accountId,
                    )
                    .map((a) => PickerItem(a.id, a.name))
                    .toList(),
                onChanged: (v) => cubit.fields(toAccountId: v),
              ),
            ] else
              TextButton.icon(
                onPressed: enabled ? cubit.add : null,
                icon: const Icon(Icons.add),
                label: const Text('Split across another account'),
              ),
            const SizedBox(height: 20),
            Text(
              'Total ${financeMoney(cubit.total, catalog.currency)}',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: transfer
                  ? 'Confirm transfer'
                  : expense
                  ? 'Record expense'
                  : 'Record extra income',
              busy: s.busy,
              onPressed: cubit.save,
            ),
          ],
        ],
      );
    },
  );
  Widget _text(
    String label,
    String value,
    ValueChanged<String> changed,
    bool enabled, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      initialValue: value,
      onChanged: changed,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
