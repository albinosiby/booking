import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_overview_widgets.dart';
import '../../accounts/widgets/finance_period_widgets.dart';
import '../models/expense_models.dart';

class ExpenseReportSelection {
  const ExpenseReportSelection(this.filter, this.format);
  final ExpenseFilter filter;
  final String format;
}

/// The report scope is chosen explicitly and never inherits hidden page filters.
class ExpenseReportSheet extends StatefulWidget {
  const ExpenseReportSheet({
    super.key,
    required this.initialAnchor,
    required this.categories,
    this.initialFormat = 'pdf',
  });
  final DateTime initialAnchor;
  final List<ExpenseCategory> categories;
  final String initialFormat;

  @override
  State<ExpenseReportSheet> createState() => _ExpenseReportSheetState();
}

class _ExpenseReportSheetState extends State<ExpenseReportSheet> {
  late DateTime anchor = DateTime(
    widget.initialAnchor.year,
    widget.initialAnchor.month,
  );
  bool yearly = false;
  String category = '';
  late String format = widget.initialFormat;

  @override
  Widget build(BuildContext context) => AdaptiveSheetBody(
    initialChildSize: .82,
    builder: (context, controller, _) {
      final filter = ExpenseFilter(
        anchor: anchor,
        yearly: yearly,
        categoryId: category.isEmpty ? null : category,
      );
      final categories = [
        const PickerItem('', 'All expenses'),
        for (final item in widget.categories)
          PickerItem(
            item.id,
            item.active ? item.name : '${item.name} (archived)',
          ),
      ];
      final categoryName = categories
          .firstWhere((item) => item.value == category)
          .label;
      return Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              children: [
                Text(
                  'Download expense report',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  'Choose the period and expense category for this download.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Text('Period', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                FinancePeriodBar(
                  anchor: anchor,
                  yearly: yearly,
                  onChanged: (date, isYearly) => setState(() {
                    anchor = DateTime(date.year, date.month);
                    yearly = isYearly;
                  }),
                ),
                const SizedBox(height: 20),
                AppPicker(
                  key: const ValueKey('expense-report-category'),
                  label: 'Expense category',
                  value: category,
                  items: categories,
                  onChanged: (value) => setState(() => category = value),
                ),
                const SizedBox(height: 20),
                Text(
                  'File format',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'pdf', label: Text('PDF')),
                    ButtonSegment(value: 'xlsx', label: Text('Excel')),
                  ],
                  selected: {format},
                  onSelectionChanged: (value) =>
                      setState(() => format = value.first),
                ),
                const SizedBox(height: 20),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report includes',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${financeRangeLabel(FinanceFilter(from: filter.from, until: filter.until))}\n$categoryName',
                        key: const ValueKey('expense-report-scope'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All matching expenses, reversals, payment methods, references and invoice counts. The export date appears in the report.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: AppButton(
              label: format == 'pdf' ? 'Download PDF' : 'Download Excel',
              icon: Icons.download_outlined,
              onPressed: () => Navigator.of(
                context,
              ).pop(ExpenseReportSelection(filter, format)),
            ),
          ),
        ],
      );
    },
  );
}
