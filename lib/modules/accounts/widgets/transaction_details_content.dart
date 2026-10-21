import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';

/// Read-only receipt presentation; the screen's Cubit owns correction commands.
class TransactionDetailsContent extends StatelessWidget {
  const TransactionDetailsContent({
    super.key,
    required this.model,
    required this.currency,
  });
  final TransactionDetailsModel model;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final e = model.transaction,
        theme = Theme.of(context),
        colors = theme.colorScheme;
    final outgoing = !model.isTransfer && e.net < 0;
    final color = outgoing ? colors.error : colors.primary;
    String money(int n) => financeMoney(n.abs(), currency);
    Widget heading(String title) => Padding(
      padding: EdgeInsets.only(top: 22.h, bottom: 10.h),
      child: Text(title, style: theme.textTheme.titleMedium),
    );
    Widget detail(String label, String value, {bool copy = false}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
          if (copy)
            IconButton(
              tooltip: 'Copy reference',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) showMessage(context, 'Reference copied');
              },
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 24.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(22.r),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 25.r,
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(
                  model.isTransfer
                      ? Icons.swap_horiz_rounded
                      : outgoing
                      ? Icons.north_east_rounded
                      : Icons.south_west_rounded,
                  color: color,
                ),
              ),
              SizedBox(height: 14.h),
              Text(
                model.typeLabel,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
              SizedBox(height: 6.h),
              SelectableText(
                '${model.isTransfer
                    ? ''
                    : outgoing
                    ? '− '
                    : e.net > 0
                    ? '+ '
                    : ''}${money(model.displayAmount)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                financeStamp(e.date),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (model.reversed)
                Padding(
                  padding: EdgeInsets.only(top: 12.h),
                  child: const Text(
                    'Reversal recorded. Original entry retained.',
                  ),
                ),
            ],
          ),
        ),
        heading(model.isTransfer ? 'Account transfer' : 'Payment breakdown'),
        AppCard(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
          child: Column(
            children: [
              if (e.lines.isEmpty)
                Padding(
                  padding: EdgeInsets.all(12.r),
                  child: const Text('No account movements available.'),
                ),
              for (final (index, line) in e.lines.indexed) ...[
                if (index > 0) const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        line.amount < 0
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                        size: 19.r,
                        color: colors.onSurfaceVariant,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.isTransfer
                                  ? (line.amount < 0 ? 'From' : 'To')
                                  : (line.amount < 0
                                        ? 'Paid from'
                                        : 'Received in'),
                              style: theme.textTheme.labelSmall,
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              line.accountName,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              financeLabel(line.method),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          '${line.amount < 0 ? '−' : '+'} ${money(line.amount)}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        heading('Details'),
        AppCard(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Text(
                  e.reason.isEmpty ? 'No reason provided' : e.reason,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const Divider(height: 16),
              detail('Category', model.categoryLabel),
              detail('Business / space', model.scopeLabel),
              detail('Recorded by', e.staff),
              if (e.reference.isNotEmpty)
                detail('Reference', e.reference, copy: true),
              if (e.reversesId != null) detail('Original entry', e.reversesId!),
            ],
          ),
        ),
        if (e.admissionId != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.card_membership),
            title: const Text('View admission'),
            subtitle: Text(e.bookingReference ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admissions/${e.admissionId}'),
          ),
        if (e.bookingId != null) ...[
          heading('Related booking'),
          AppCard(
            onTap: () => context.push('/booking/${e.bookingId}'),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Icon(Icons.event_note_outlined, color: colors.primary),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.bookingReference?.isNotEmpty == true
                            ? e.bookingReference!
                            : 'Open booking',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (e.customer?.isNotEmpty == true)
                        Text(e.customer!, style: theme.textTheme.bodySmall),
                      if (e.tariff != null)
                        Text(
                          'Tariff: ${money(e.tariff!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
