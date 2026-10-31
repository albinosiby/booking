import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_overview_widgets.dart';
import '../../accounts/widgets/finance_period_widgets.dart';
import '../models/income_models.dart';

class IncomeReportSelection {
  const IncomeReportSelection(this.filter, this.format);
  final IncomeFilter filter;
  final String format;
}

/// A report has its own explicit scope; hidden page filters never carry over.
class IncomeReportSheet extends StatefulWidget {
  const IncomeReportSheet({
    super.key,
    required this.initialAnchor,
    required this.catalog,
    required this.categories,
  });
  final DateTime initialAnchor;
  final FinanceCatalog catalog;
  final List<IncomeCategory> categories;

  @override
  State<IncomeReportSheet> createState() => _IncomeReportSheetState();
}

class _IncomeReportSheetState extends State<IncomeReportSheet> {
  late DateTime anchor = DateTime(
    widget.initialAnchor.year,
    widget.initialAnchor.month,
  );
  bool yearly = false;
  String spaceId = '', source = '', format = 'pdf';

  @override
  Widget build(BuildContext context) => AdaptiveSheetBody(
    initialChildSize: .82,
    builder: (context, controller, _) {
      final spaces = [
        for (final business in widget.catalog.businesses)
          for (final space in business.spaces)
            (
              businessId: business.id,
              spaceId: space.id,
              label: '${business.name} · ${space.name}',
            ),
      ];
      final selectedSpace = spaces
          .where((space) => space.spaceId == spaceId)
          .firstOrNull;
      final filter = IncomeFilter(
        anchor: anchor,
        yearly: yearly,
        source: source.isEmpty ? null : source,
        businessId: selectedSpace?.businessId,
        spaceId: selectedSpace?.spaceId,
      );
      final sources = [
        const PickerItem('', 'All income'),
        const PickerItem(incomeBookings, 'Bookings'),
        const PickerItem(incomeAdmissions, 'Admissions'),
        for (final category in widget.categories)
          PickerItem(
            category.id,
            category.active ? category.name : '${category.name} (archived)',
          ),
      ];
      final sourceName = sources
          .firstWhere((item) => item.value == source)
          .label;
      return Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              children: [
                Text(
                  'Download income report',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  'Choose the period, space and income source for this download.',
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
                  key: const ValueKey('income-report-space'),
                  label: 'Space',
                  value: spaceId,
                  items: [
                    const PickerItem('', 'All spaces'),
                    for (final space in spaces)
                      PickerItem(space.spaceId, space.label),
                  ],
                  onChanged: (value) => setState(() => spaceId = value),
                ),
                const SizedBox(height: 20),
                AppPicker(
                  key: const ValueKey('income-report-source'),
                  label: 'Income source',
                  value: source,
                  items: sources,
                  onChanged: (value) => setState(() => source = value),
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
                        '${financeRangeLabel(FinanceFilter(from: filter.from, until: filter.until))}\n${selectedSpace?.label ?? 'All spaces'}\n$sourceName',
                        key: const ValueKey('income-report-scope'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All matching income entries, payment methods, refunds, and references. The export date appears in the report.',
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
              ).pop(IncomeReportSelection(filter, format)),
            ),
          ),
        ],
      );
    },
  );
}
