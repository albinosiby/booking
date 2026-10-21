import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_widgets.dart';
import '../cubit/expense_form_cubit.dart';
import '../cubit/expenses_state.dart';
import '../widgets/invoice_preview.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key});
  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final cubit = getIt<ExpenseFormCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<bool> leave() async {
    if (cubit.state.busy || cubit.state.picking) return false;
    if (cubit.state.complete) return true;
    if (cubit.state.savedId != null) {
      return await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Expense saved'),
              content: const Text(
                'Some invoices still need uploading. You can retry them here, or reopen this expense to attach them later.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Keep uploading'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Leave'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (cubit.state.reason.isEmpty &&
        cubit.total == 0 &&
        cubit.state.files.isEmpty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Discard this expense?'),
            content: const Text(
              'Your unsaved changes and selected files will be discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool exiting = false;
  Future<void> exit() async {
    if (await leave() && mounted) {
      setState(() => exiting = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  Widget input(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool enabled = true,
    bool money = false,
    int max = 500,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      initialValue: value,
      enabled: enabled,
      onChanged: onChanged,
      maxLength: max,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixText: money ? '₹ ' : null,
      ),
    ),
  );

  Widget totalCard(
    BuildContext c,
    ExpenseFormState s,
    FinanceCatalog catalog,
    bool enabled,
  ) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TOTAL EXPENSE', style: Theme.of(c).textTheme.labelMedium),
        const SizedBox(height: 8),
        if (s.lines.length == 1)
          TextFormField(
            key: ValueKey('expense-total-${s.lines.first.id}'),
            initialValue: s.lines.first.amount,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(c).textTheme.headlineLarge,
            onChanged: (v) => cubit.line(0, s.lines.first.copyWith(amount: v)),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: catalog.currency == 'INR'
                  ? '₹ '
                  : '${catalog.currency} ',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          )
        else
          Text(
            financeMoney(cubit.total, catalog.currency),
            style: Theme.of(c).textTheme.headlineLarge,
          ),
        const SizedBox(height: 4),
        Text(
          s.savedId != null
              ? 'Expense recorded · invoices can be retried safely'
              : s.lines.length == 1
              ? 'One payment source'
              : '${s.lines.length} payment sources',
          style: Theme.of(c).textTheme.bodySmall,
        ),
      ],
    ),
  );

  List<Widget> detailFields(
    BuildContext c,
    ExpenseFormState s,
    FinanceCatalog catalog,
    bool enabled,
  ) => [
    AppPicker(
      label: 'Category',
      value: s.categoryId ?? '',
      enabled: enabled,
      items: [
        const PickerItem('', 'Choose category'),
        ...s.categories
            .where((c) => c.active)
            .map((c) => PickerItem(c.id, c.name)),
      ],
      onChanged: (v) => cubit.fields(categoryId: v),
    ),
    const SizedBox(height: 14),
    input(
      'What was this expense for?',
      s.reason,
      (v) => cubit.fields(reason: v),
      enabled: enabled,
    ),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today_outlined),
      title: const Text('Expense date & time'),
      subtitle: Text(
        s.date == null ? 'Today' : financeStamp(s.date!.toIso8601String()),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: !enabled
          ? null
          : () async {
              final date = await chooseFinanceDateTime(
                c,
                s.date ?? DateTime.now(),
              );
              if (date != null) cubit.fields(date: date);
            },
    ),
    const SizedBox(height: 14),
    FinanceScopePicker(
      catalog: catalog,
      business: s.businessId,
      space: s.spaceId,
      onChanged: cubit.scope,
      sharedLabel: 'Whole organization / shared',
      enabled: enabled,
    ),
    const SizedBox(height: 14),
    input(
      'Reference / invoice number (optional)',
      s.reference,
      (v) => cubit.fields(reference: v),
      enabled: enabled,
      max: 200,
    ),
  ];

  List<Widget> paymentLines(
    BuildContext c,
    ExpenseFormState s,
    FinanceCatalog catalog,
    bool enabled,
  ) => [
    for (var i = 0; i < s.lines.length; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.lines.length == 1
                          ? 'Payment source'
                          : 'Payment ${i + 1}',
                      style: Theme.of(c).textTheme.titleSmall,
                    ),
                  ),
                  if (s.lines.length > 1)
                    IconButton(
                      tooltip: 'Remove payment',
                      onPressed: enabled ? () => cubit.removeLine(i) : null,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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
              AppPicker(
                label: s.lines[i].method == 'cash'
                    ? 'Cash account'
                    : 'Bank account',
                value: s.lines[i].accountId ?? '',
                enabled: enabled,
                items: [
                  const PickerItem('', 'Choose account'),
                  ...catalog.accounts
                      .where(
                        (a) =>
                            a.active &&
                            a.kind ==
                                (s.lines[i].method == 'cash' ? 'cash' : 'bank'),
                      )
                      .map((a) => PickerItem(a.id, a.name)),
                ],
                onChanged: (v) =>
                    cubit.line(i, s.lines[i].copyWith(accountId: v)),
              ),
              const SizedBox(height: 14),
              if (s.lines.length > 1)
                input(
                  'Amount',
                  s.lines[i].amount,
                  (v) => cubit.line(i, s.lines[i].copyWith(amount: v)),
                  enabled: enabled,
                  money: true,
                  max: 12,
                ),
            ],
          ),
        ),
      ),
    TextButton.icon(
      onPressed: enabled ? cubit.addLine : null,
      icon: const Icon(Icons.add),
      label: const Text('Split across another payment source'),
    ),
  ];

  List<Widget> invoiceSection(
    BuildContext c,
    ExpenseFormState s,
    bool enabled,
  ) => [
    Text(
      'Add images or PDFs. Up to 10 files, 15 MB each.',
      style: Theme.of(c).textTheme.bodySmall,
    ),
    const SizedBox(height: 14),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: enabled && !s.picking
              ? () => cubit.pick(camera: true)
              : null,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Camera'),
        ),
        OutlinedButton.icon(
          onPressed: enabled && !s.picking
              ? () => cubit.pick(photos: true)
              : null,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Photos'),
        ),
        OutlinedButton.icon(
          onPressed: enabled && !s.picking ? () => cubit.pick() : null,
          icon: const Icon(Icons.attach_file),
          label: const Text('Files / PDF'),
        ),
      ],
    ),
    if (s.picking) const AppRefreshIndicator(),
    for (var i = 0; i < s.files.length; i++)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: s.files[i].invoice.type == 'application/pdf'
            ? const Icon(Icons.picture_as_pdf_outlined, size: 36)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  s.files[i].bytes,
                  width: 44,
                  height: 52,
                  fit: BoxFit.cover,
                  cacheWidth: 100,
                  errorBuilder: (c, e, s) => const Icon(Icons.image_outlined),
                ),
              ),
        title: Text(
          s.files[i].invoice.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          s.files[i].uploaded
              ? 'Uploaded'
              : s.files[i].error ??
                    '${(s.files[i].invoice.size / (1024 * 1024)).toStringAsFixed(1)} MB · Ready to upload',
        ),
        onTap: () =>
            showInvoicePreview(c, s.files[i].invoice, s.files[i].bytes),
        trailing: enabled
            ? IconButton(
                tooltip: 'Remove invoice',
                onPressed: () => cubit.removeFile(i),
                icon: const Icon(Icons.close),
              )
            : s.files[i].uploaded
            ? const Icon(Icons.check_circle_outline)
            : const Icon(Icons.cloud_upload_outlined),
      ),
  ];

  Widget saveButton(ExpenseFormState s, FinanceCatalog catalog) => AppButton(
    label: s.savedId != null ? 'Retry invoices' : 'Save expense',
    busy: s.busy,
    busyLabel: s.savedId != null ? 'Uploading invoices…' : 'Saving expense…',
    onPressed: s.picking || !catalog.canExpense ? null : cubit.save,
  );

  Widget expenseNote(BuildContext c) => Text(
    'The expense is recorded once. If an invoice upload fails, retrying it will not create another expense.',
    style: Theme.of(c).textTheme.bodySmall,
  );

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<ExpenseFormCubit, ExpenseFormState>(
    bloc: cubit,
    listener: (c, s) {
      if (s.complete) {
        showMessage(
          c,
          'Expense saved${s.files.isEmpty ? '' : ' with ${s.files.length} invoices'}.',
        );
        c.pop();
      }
    },
    builder: (c, s) {
      final catalog = s.catalog, enabled = cubit.editable;
      return PopScope(
        canPop: exiting || s.complete,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) exit();
        },
        child: isDesktopWidth(c)
            ? _desktop(c, s, enabled)
            : AppPage(
                title: 'Add expense',
                back: true,
                showAppBar: true,
                compactHeader: true,
                onBack: exit,
                scrollId: 'add-expense',
                bottomBar: catalog == null
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            12,
                            24,
                            12 + MediaQuery.viewInsetsOf(c).bottom,
                          ),
                          child: saveButton(s, catalog),
                        ),
                      ),
                children: [
                  if (s.loading)
                    AppLoadingState(
                      initial: catalog == null,
                      label: 'Loading expense form…',
                    ),
                  if (s.error != null)
                    AppErrorWidget(
                      message: s.error!,
                      onRetry: catalog == null ? cubit.load : null,
                    ),
                  if (catalog != null) ...[
                    if (!catalog.canExpense)
                      const Text(
                        'You do not have permission to record expenses.',
                      ),
                    totalCard(c, s, catalog, enabled),
                    const FinanceSection('Expense details'),
                    ...detailFields(c, s, catalog, enabled),
                    const FinanceSection('Paid from'),
                    ...paymentLines(c, s, catalog, enabled),
                    const FinanceSection('Invoices', action: 'Optional'),
                    ...invoiceSection(c, s, enabled),
                    const SizedBox(height: 20),
                    expenseNote(c),
                  ],
                ],
              ),
      );
    },
  );

  // Wide web windows: fields on the left; summary, save and invoices on the
  // right. Each column is its own focus group so Tab walks the form in order.
  Widget _desktop(BuildContext c, ExpenseFormState s, bool enabled) {
    final catalog = s.catalog;
    final theme = Theme.of(c);
    String? name(Iterable<(String, String)> all, String? id) =>
        all.where((e) => e.$1 == id).firstOrNull?.$2;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: strong
                  ? theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    )
                  : const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return AppPage(
      title: 'Add expense',
      subtitle: 'Record a payment once, then attach its invoices.',
      back: true,
      onBack: exit,
      scrollId: 'add-expense',
      maxWidth: 1160,
      children: [
        if (s.loading)
          AppLoadingState(
            initial: catalog == null,
            label: 'Loading expense form…',
          ),
        if (s.error != null)
          AppErrorWidget(
            message: s.error!,
            onRetry: catalog == null ? cubit.load : null,
          ),
        if (catalog != null) ...[
          if (!catalog.canExpense)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('You do not have permission to record expenses.'),
            ),
          AppTwoPane(
            secondaryWidth: 380,
            primary: [
              FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPanel(
                      title: 'Amount',
                      child: totalCard(c, s, catalog, enabled),
                    ),
                    AppPanel(
                      title: 'Expense details',
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: detailFields(c, s, catalog, enabled),
                        ),
                      ),
                    ),
                    AppPanel(
                      title: 'Paid from',
                      subtitle: 'Split across sources when paid in parts',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: paymentLines(c, s, catalog, enabled),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            secondary: [
              FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPanel(
                      title: 'Summary',
                      child: AppCard(
                        key: const ValueKey('expense-summary-card'),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            row(
                              'Total',
                              financeMoney(cubit.total, catalog.currency),
                              strong: true,
                            ),
                            const Divider(height: 18),
                            row(
                              'Category',
                              name([
                                    for (final e in s.categories)
                                      (e.id, e.name),
                                  ], s.categoryId) ??
                                  'Not chosen',
                            ),
                            row(
                              'Date',
                              s.date == null
                                  ? 'Today'
                                  : financeStamp(s.date!.toIso8601String()),
                            ),
                            row(
                              'Business',
                              name([
                                    for (final b in catalog.businesses)
                                      (b.id, b.name),
                                  ], s.businessId) ??
                                  'Whole organization',
                            ),
                            row(
                              'Paid from',
                              s.lines.length == 1
                                  ? 'One payment source'
                                  : '${s.lines.length} payment sources',
                            ),
                            row(
                              'Invoices',
                              s.files.isEmpty
                                  ? 'None attached'
                                  : '${s.files.length} attached',
                            ),
                            const SizedBox(height: 18),
                            saveButton(s, catalog),
                            const SizedBox(height: 12),
                            expenseNote(c),
                          ],
                        ),
                      ),
                    ),
                    AppPanel(
                      title: 'Invoices',
                      trailing: Text(
                        'Optional',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      child: AppCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: invoiceSection(c, s, enabled),
                        ),
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
}
