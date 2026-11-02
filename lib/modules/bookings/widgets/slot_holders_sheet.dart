import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../design_system/design_system.dart';
import '../models/slot_holder.dart';

/// One row naming who holds a slot.
class SlotHolderTile extends StatelessWidget {
  const SlotHolderTile({super.key, required this.holder});
  final SlotHolder holder;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(switch (holder.kind) {
      'admission' => Icons.card_membership_outlined,
      'block' => Icons.block,
      _ => Icons.event_available_outlined,
    }),
    title: Text(holder.title),
    subtitle: Text(holder.details),
  );
}

/// Loads and lists who holds one booked or blocked slot.
Future<void> showSlotHoldersSheet(
  BuildContext context, {
  required String title,
  required Future<List<SlotHolder>> Function() load,
}) => showAdaptiveSheet<void>(
  context: context,
  builder: (_) => _SlotHoldersSheet(title: title, load: load),
);

class _SlotHoldersSheet extends StatefulWidget {
  const _SlotHoldersSheet({required this.title, required this.load});
  final String title;
  final Future<List<SlotHolder>> Function() load;
  @override
  State<_SlotHoldersSheet> createState() => _SlotHoldersSheetState();
}

class _SlotHoldersSheetState extends State<_SlotHoldersSheet> {
  late Future<List<SlotHolder>> holders = widget.load();
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 12.h),
        FutureBuilder<List<SlotHolder>>(
          future: holders,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const AppLoadingState(label: 'Checking who holds it…');
            }
            if (snap.hasError) {
              return AppErrorWidget(
                message: '${snap.error}',
                onRetry: () => setState(() => holders = widget.load()),
              );
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const Text(
                'Nobody holds this slot now. Refresh availability to see the latest times.',
              );
            }
            return Column(
              children: [for (final h in list) SlotHolderTile(holder: h)],
            );
          },
        ),
      ],
    ),
  );
}
