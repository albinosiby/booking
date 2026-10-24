import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../models/admission_models.dart';
import '../models/admission_overview.dart';
import 'admission_cards.dart';

class AdmissionFiltersSheet extends StatefulWidget {
  const AdmissionFiltersSheet({
    super.key,
    required this.businesses,
    required this.initial,
  });
  final List<AdmissionBusiness> businesses;
  final AdmissionFilterSelection initial;

  @override
  State<AdmissionFiltersSheet> createState() => _AdmissionFiltersSheetState();
}

class _AdmissionFiltersSheetState extends State<AdmissionFiltersSheet> {
  late String? businessId = widget.initial.businessId;
  late String? spaceId = widget.initial.spaceId;
  late String? status = widget.initial.status;

  @override
  Widget build(BuildContext context) {
    final business = widget.businesses
        .where((b) => b.id == businessId)
        .firstOrNull;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter students',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close filters',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Narrow the list by location or admission status.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AppPicker(
              key: const ValueKey('admission-filter-business'),
              label: 'Business',
              value: businessId ?? '',
              items: [
                const PickerItem('', 'All businesses'),
                for (final b in widget.businesses) PickerItem(b.id, b.name),
              ],
              onChanged: (value) => setState(() {
                final selected = value.isEmpty ? null : value;
                if (selected != businessId) spaceId = null;
                businessId = selected;
              }),
            ),
            const SizedBox(height: 16),
            AppPicker(
              key: const ValueKey('admission-filter-space'),
              label: business?.spaceLabel ?? 'Pool or court',
              value: spaceId ?? '',
              enabled: business != null,
              items: [
                const PickerItem('', 'All pools or courts'),
                for (final p in business?.pools ?? <AdmissionPool>[])
                  PickerItem(p.id, p.name),
              ],
              onChanged: (value) =>
                  setState(() => spaceId = value.isEmpty ? null : value),
            ),
            if (business == null) ...[
              const SizedBox(height: 8),
              Text(
                'Choose a business to filter a specific pool or court.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            AppPicker(
              key: const ValueKey('admission-filter-status'),
              label: 'Status',
              value: status ?? '',
              items: [
                const PickerItem('', 'All statuses'),
                for (final value in const [
                  'active',
                  'upcoming',
                  'completed',
                  'expired',
                  'cancelled',
                ])
                  PickerItem(value, admissionStatusLabel(value)),
              ],
              onChanged: (value) =>
                  setState(() => status = value.isEmpty ? null : value),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Apply filters',
              onPressed: () => Navigator.pop(
                context,
                AdmissionFilterSelection(
                  businessId: businessId,
                  spaceId: spaceId,
                  status: status,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, const AdmissionFilterSelection()),
                  child: const Text('Clear filters'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
