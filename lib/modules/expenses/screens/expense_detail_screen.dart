import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../widgets/expense_receipt.dart';
import '../cubit/expense_detail_cubit.dart';
import '../cubit/expenses_state.dart';
import '../models/expense_models.dart';
import '../widgets/invoice_preview.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late final cubit = getIt<ExpenseDetailCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.id,
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ExpenseDetailCubit, ExpenseDetailState>(
        bloc: cubit,
        builder: (c, s) {
          if (isDesktopWidth(c)) return _desktop(c, s);
          final d = s.detail,
              currency = s.catalog?.currency ?? 'INR',
              canAttach = d?.canAttach == true;
          return AppPage(
            title: 'Expense details',
            back: true,
            showAppBar: true,
            compactHeader: true,
            children: [
              if (s.loading)
                AppLoadingState(
                  initial: d == null,
                  label: d == null ? 'Loading expense…' : null,
                ),
              if (s.busy) const AppRefreshIndicator(),
              if (s.error != null)
                AppErrorWidget(message: s.error!, onRetry: cubit.load),
              if (d != null) ...[
                ExpenseReceipt(detail: d, currency: currency),
                ExpenseDetailHeading(
                  title: 'Invoices',
                  count: d.invoices.length,
                ),
                if (d.invoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No invoices attached')),
                  ),
                for (final file in d.invoices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: invoiceCard(c, s, file),
                  ),
                if (canAttach && d.invoices.length < 10)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: s.busy ? null : cubit.add,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Add invoices'),
                    ),
                  ),
              ],
            ],
          );
        },
      );

  Widget invoiceCard(
    BuildContext c,
    ExpenseDetailState s,
    ExpenseInvoice file,
  ) {
    final canAttach = s.detail?.canAttach == true;
    return AppCard(
      onTap: s.busy || (!file.ready && !canAttach)
          ? null
          : () async {
              if (!file.ready) {
                await cubit.add(pending: file);
                return;
              }
              final bytes = await cubit.preview(file);
              if (bytes != null && c.mounted) {
                await showInvoicePreview(c, file, bytes);
              }
            },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(c).colorScheme.primaryContainer,
            foregroundColor: Theme.of(c).colorScheme.onPrimaryContainer,
            child: Icon(
              file.type == 'application/pdf'
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, style: Theme.of(c).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  '${file.type == 'application/pdf' ? 'PDF' : 'Image'} · ${file.size < 1024 * 1024 ? '${(file.size / 1024).ceil()} KB' : '${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB'}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  file.ready
                      ? 'Tap to view'
                      : canAttach
                      ? 'Upload incomplete · tap to retry with the original file'
                      : 'Upload incomplete',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!file.ready && canAttach)
            IconButton(
              tooltip: 'Remove incomplete upload',
              onPressed: s.busy ? null : () => cubit.remove(file),
              icon: const Icon(Icons.close),
            )
          else if (file.ready)
            const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  // Wide web windows: receipt and invoices on the left, details on the right.
  Widget _desktop(BuildContext c, ExpenseDetailState s) {
    final d = s.detail,
        currency = s.catalog?.currency ?? 'INR',
        canAttach = d?.canAttach == true;
    final theme = Theme.of(c);
    return AppPage(
      title: 'Expense details',
      subtitle: d?.item.reason,
      back: true,
      maxWidth: 1160,
      children: [
        if (s.loading)
          AppLoadingState(
            initial: d == null,
            label: d == null ? 'Loading expense…' : null,
          ),
        if (s.busy) const AppRefreshIndicator(),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (d != null)
          AppTwoPane(
            secondaryFirst: true,
            secondaryWidth: 400,
            secondary: [
              AppPanel(
                title: 'Receipt',
                child: ExpenseReceiptHero(detail: d, currency: currency),
              ),
              AppPanel(
                title: 'Invoices',
                subtitle: d.invoices.isEmpty
                    ? 'Images or PDFs attached to this expense'
                    : '${d.invoices.length} of 10 attached',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d.invoices.isEmpty)
                      AppCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 32,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              const Text('No invoices attached'),
                            ],
                          ),
                        ),
                      ),
                    for (final file in d.invoices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: invoiceCard(c, s, file),
                      ),
                    if (canAttach && d.invoices.length < 10) ...[
                      if (d.invoices.isEmpty) const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: s.busy ? null : cubit.add,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add invoices'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            primary: [
              AppPanel(
                title: 'Expense information',
                child: ExpenseInformationCard(item: d.item, wide: true),
              ),
              AppPanel(
                title: 'Paid from',
                subtitle: d.item.lines.length > 1
                    ? '${d.item.lines.length} payment sources'
                    : null,
                child: ExpensePaymentsCard(
                  item: d.item,
                  currency: currency,
                  wide: true,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
