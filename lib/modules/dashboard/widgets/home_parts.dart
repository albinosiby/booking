import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 150000 → `₹1,500`, 150050 → `₹1,500.50`.
String homeMoney(int minor, String currency) {
  final whole = (minor.abs() ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final cents = minor.abs() % 100;
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  return '${minor < 0 ? '−' : ''}$symbol$whole${cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}'}';
}

/// `2030-07-01` → `today`, `tomorrow`, `1 Jul`, or `1 Jul 2031` in another
/// year. Lowercase words read naturally mid-sentence ("Expired yesterday").
String homeDate(String date, {String? today}) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  final now = DateTime.tryParse(today ?? '') ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(day).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  if (diff == -1) return 'yesterday';
  return '${d.day} ${_months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

/// `17:30` → `5:30 PM`.
String homeTime(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts.first), m = parts.length > 1 ? parts[1] : '00';
  if (h == null) return time;
  return '${h % 12 == 0 ? 12 : h % 12}:$m ${h % 24 < 12 ? 'AM' : 'PM'}';
}

/// One Home card: icon, title, a short summary chip and divided rows.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.summary,
    this.footer = const [],
  });
  final IconData icon;
  final String title;
  final String? summary;
  final List<Widget> children, footer;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (summary != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    summary!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 6),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .35),
              ),
            children[i],
          ],
          ...footer,
        ],
      ),
    );
  }
}

/// One thing to act on: who, what, when, how much, and one action.
class HomeTaskRow extends StatelessWidget {
  const HomeTaskRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.meta,
    this.amount,
    this.amountColor,
    this.action,
    this.onTap,
    this.longAction = false,
  });
  final String title, subtitle;

  /// A long action label moves under the details on phones.
  final bool longAction;
  final Widget? leading, action;
  final String? meta, amount;
  final Color? amountColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Narrow or enlarged text: the action moves under the details.
            final stacked =
                constraints.maxWidth < 300 ||
                (longAction && constraints.maxWidth < 440) ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                if (meta != null) ...[
                  SizedBox(height: 2),
                  Text(meta!, style: muted),
                ],
              ],
            );
            final value = amount == null
                ? null
                : Text(
                    amount!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: amountColor,
                    ),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading ?? HomeInitials(title),
                    SizedBox(width: 12),
                    Expanded(child: details),
                    if (value != null || (!stacked && action != null)) ...[
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ?value,
                          if (!stacked && action != null) ...[
                            SizedBox(height: 6),
                            action!,
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
                if (stacked && action != null)
                  Padding(
                    padding: EdgeInsets.only(left: 56, top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: action,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A person's initials in a soft circle.
class HomeInitials extends StatelessWidget {
  const HomeInitials(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    return CircleAvatar(
      radius: 22,
      backgroundColor: scheme.primary.withValues(alpha: .14),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A booking's start time in a rounded tile, in place of initials.
class HomeTimeTile extends StatelessWidget {
  const HomeTimeTile(this.time, {super.key});
  final String time;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = homeTime(time).split(' ');
    return Container(
      width: 56,
      padding: EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label.first,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (label.length > 1)
            Text(label.last, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// A compact action button for a row.
class HomeRowAction extends StatelessWidget {
  const HomeRowAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    );
    return primary
        ? FilledButton.tonal(
            style: style,
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Text(label),
          );
  }
}

/// A calm one-line state, such as "All payments are in".
class HomeEmptyLine extends StatelessWidget {
  const HomeEmptyLine({
    super.key,
    required this.message,
    this.icon = Icons.check_circle_outline,
  });
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: muted)),
          ),
        ],
      ),
    );
  }
}
