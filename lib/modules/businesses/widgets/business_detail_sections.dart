import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/business_detail_model.dart';

class BusinessDetailFields extends StatelessWidget {
  const BusinessDetailFields({super.key, required this.fields});
  final List<BusinessDetailField> fields;
  @override
  Widget build(BuildContext context) => SelectionArea(
    child: LayoutBuilder(
      builder: (context, box) {
        final twoColumns = box.maxWidth >= 600;
        return Wrap(
          spacing: 24,
          runSpacing: 18,
          children: [
            for (final field in fields)
              SizedBox(
                width: twoColumns ? (box.maxWidth - 24) / 2 : box.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      field.value.isEmpty ? 'Not provided' : field.value,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class BusinessDetailSectionView extends StatelessWidget {
  const BusinessDetailSectionView({
    super.key,
    required this.section,
    required this.businessId,
  });
  final BusinessDetailSection section;
  final String businessId;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(section.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      for (final entry in section.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey('business-$businessId-${entry.id}'),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                entry.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.subtitle),
                    if (entry.enabled != null) ...[
                      const SizedBox(height: 8),
                      ReviewTag(
                        entry.enabled! ? 'Enabled' : 'Disabled',
                        active: entry.enabled!,
                      ),
                    ],
                  ],
                ),
              ),
              children: [
                const Divider(height: 24),
                BusinessDetailFields(fields: entry.fields),
                if (entry.prices.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Saved prices',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Prices apply on the selected days and times. Seasonal prices take priority on their dates.',
                  ),
                  const SizedBox(height: 12),
                  for (final price in entry.prices)
                    ReviewPricingGroup(
                      schedule: price.schedule,
                      children: [
                        for (final rate in price.rates)
                          ReviewRate(label: rate.label, price: rate.value),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
    ],
  );
}

class BusinessDetailIdentity extends StatelessWidget {
  const BusinessDetailIdentity({
    super.key,
    required this.icon,
    required this.type,
    required this.organization,
  });
  final IconData icon;
  final String type, organization;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final colors = Theme.of(context).colorScheme;
      final symbol = Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 30, color: colors.primary),
      );
      final labels = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(organization, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
      if (box.maxWidth < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [symbol, const SizedBox(height: 14), labels],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          symbol,
          const SizedBox(width: 16),
          Expanded(child: labels),
        ],
      );
    },
  );
}
