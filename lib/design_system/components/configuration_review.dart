import 'package:flutter/material.dart';
import 'app_card.dart';

class ReviewHeader extends StatelessWidget {
  const ReviewHeader({
    super.key,
    required this.name,
    required this.summary,
    this.error,
  });
  final String name, summary;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                error == null ? Icons.task_alt : Icons.info_outline,
                size: 19,
                color: error == null ? colors.primary : colors.error,
              ),
              Text(
                error == null ? 'Ready to apply' : 'Needs attention',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: error == null ? colors.primary : colors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            error ??
                'Check the details below. You can edit anything before applying it online.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: error == null ? colors.onSurfaceVariant : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewTag extends StatelessWidget {
  const ReviewTag(this.label, {super.key, this.active = false});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (active ? c.primary : c.onSurface).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: active ? c.primary : c.onSurfaceVariant,
        ),
      ),
    );
  }
}

class ReviewSpaceCard extends StatelessWidget {
  const ReviewSpaceCard({
    super.key,
    required this.name,
    required this.icon,
    required this.children,
    this.subtitle,
    this.enabled = true,
    this.onEdit,
  });
  final String name;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool enabled;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 10),
                child: Icon(
                  icon,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit $name',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
            ],
          ),
          if (!enabled) ...[
            const SizedBox(height: 8),
            const ReviewTag('Disabled'),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class ReviewDetail extends StatelessWidget {
  const ReviewDetail({
    super.key,
    required this.label,
    required this.value,
    this.onEdit,
  });
  final String label, value;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit $label',
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
      ],
    ),
  );
}

/// A two-column rate row wraps vertically at narrow widths/large text sizes.
class ReviewRate extends StatelessWidget {
  const ReviewRate({super.key, required this.label, required this.price});
  final String label, price;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final rate = Text(
        price,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child:
            box.maxWidth < 230 ||
                MediaQuery.textScalerOf(context).scale(14) > 20
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(label), rate],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(label)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(alignment: Alignment.topRight, child: rate),
                  ),
                ],
              ),
      );
    },
  );
}

class ReviewPricingGroup extends StatelessWidget {
  const ReviewPricingGroup({
    super.key,
    required this.schedule,
    required this.children,
  });
  final String schedule;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          schedule,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

class ReviewMore extends StatefulWidget {
  const ReviewMore({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  State<ReviewMore> createState() => _ReviewMoreState();
}

class _ReviewMoreState extends State<ReviewMore> {
  // Expansion state must not read the surrounding page's stored scroll offset.
  final _bucket = PageStorageBucket();
  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _bucket,
    child: ExpansionTile(
      key: const PageStorageKey('review-details'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(widget.title, style: Theme.of(context).textTheme.bodyMedium),
      children: widget.children,
    ),
  );
}

class ReviewNote extends StatelessWidget {
  const ReviewNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}
