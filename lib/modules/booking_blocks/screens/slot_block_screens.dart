import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_form_sections.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/slot_block_cubits.dart';
import '../models/slot_block_models.dart';

String _day(BuildContext context, String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : MaterialLocalizations.of(context).formatFullDate(d);
}

String _shortDay(BuildContext context, String date) {
  final d = DateTime.tryParse(date);
  return d == null
      ? date
      : MaterialLocalizations.of(context).formatShortMonthDay(d);
}

/// Wall-clock label for a block edge; another day's date is added when it
/// differs from the day being viewed.
String _edge(BuildContext context, String stamp, String day) {
  final p = stamp.split('T');
  if (p.length < 2 || p[1].length < 5) return stamp;
  final time = p[1].substring(0, 5);
  return p[0] == day ? time : '$time · ${_shortDay(context, p[0])}';
}

class SlotBlocksScreen extends StatefulWidget {
  const SlotBlocksScreen({super.key, this.launch = const BlockLaunch()});
  final BlockLaunch launch;
  @override
  State<SlotBlocksScreen> createState() => _SlotBlocksScreenState();
}

class _SlotBlocksScreenState extends State<SlotBlocksScreen> {
  late final cubit = getIt<BlockListCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.launch,
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> add(BlockListModel s) async {
    final changed = await context.push<bool>(
      '/bookings/blocks/new',
      extra: BlockLaunch(
        businessId: s.businessId,
        spaceId: widget.launch.spaceId,
        date: s.business != null && s.date.compareTo(s.business!.today) >= 0
            ? s.date
            : null,
      ),
    );
    if (changed == true && !cubit.isClosed) await cubit.load();
  }

  Future<void> pickDate(BlockListModel s) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(s.date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null && !cubit.isClosed) cubit.date(bookingDate(d));
  }

  Future<void> unblock(SlotBlock block) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded),
        title: const Text('Unblock these slots?'),
        content: const Text(
          'New bookings will be allowed again, subject to normal availability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep blocked'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (yes == true && !cubit.isClosed) await cubit.unblock(block);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BlockListCubit, BlockListModel>(
    bloc: cubit,
    builder: (context, s) {
      final theme = Theme.of(context), c = theme.colorScheme;
      return AppPage(
        title: 'Blocked slots',
        back: true,
        showAppBar: true,
        compactHeader: true,
        maxWidth: 760,
        actions: [
          IconButton(
            tooltip: 'Refresh blocked slots',
            onPressed: s.loading || s.locked ? null : () => cubit.load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        floatingActionButton: s.catalog.canManage && s.business != null
            ? FloatingActionButton.extended(
                heroTag: null,
                backgroundColor: c.primary,
                foregroundColor: c.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onPressed: s.locked ? null : () => add(s),
                icon: const Icon(Icons.lock_clock_outlined),
                label: const Text(
                  'Block slots',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              )
            : null,
        children: [
          Text(
            'Close spaces for maintenance, private use or unavailable hours.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (s.catalog.businesses.length > 1) ...[
            BookingBusinessCards(
              businesses: s.catalog.businesses,
              selected: s.businessId,
              enabled: !s.locked,
              onSelected: cubit.business,
            ),
            const SizedBox(height: 16),
          ],
          if (s.date.isNotEmpty) ...[
            BookingDateRow(
              date: s.date,
              today: '2000-01-01',
              enabled: !s.locked,
              onSelected: cubit.date,
              onPick: () => pickDate(s),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _day(context, s.date),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!s.loading || s.blocks.isNotEmpty)
                  _CountBadge(count: s.blocks.length, more: s.next != null),
              ],
            ),
            if (s.business != null)
              Text(
                'Times use ${s.business!.timezone}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (s.loading)
            AppLoadingState(
              initial: s.blocks.isEmpty,
              label: s.blocks.isEmpty ? 'Loading blocked slots…' : null,
            ),
          if (s.error != null)
            AppErrorWidget(message: s.error!, onRetry: () => cubit.load()),
          if (!s.loading && s.blocks.isEmpty && s.error == null)
            AppEmptyState(
              title: 'Nothing blocked',
              message: s.catalog.canManage
                  ? 'Every space is open for booking on this day. Tap Block slots to close one.'
                  : 'Every space is open for booking on this day.',
              icon: Icons.lock_open_rounded,
            ),
          for (final block in s.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BlockCard(
                block: block,
                day: s.date,
                busy: s.busyId == block.id,
                onUnblock: block.canUnblock && !s.locked
                    ? () => unblock(block)
                    : null,
              ),
            ),
          if (s.next != null)
            TextButton(
              onPressed: s.loading || s.locked
                  ? null
                  : () => cubit.load(more: true),
              child: const Text('Load more blocks'),
            ),
          const SizedBox(height: 72),
        ],
      );
    },
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.more});
  final int count;
  final bool more;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? c.errorContainer : c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? '$count${more ? '+' : ''} blocked' : 'All open',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: active ? c.onErrorContainer : c.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.day,
    required this.busy,
    this.onUnblock,
  });
  final SlotBlock block;
  final String day;
  final bool busy;
  final VoidCallback? onUnblock;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = theme.colorScheme;
    final spaces = block.sharedGround
        ? ['Your assigned shared ground']
        : block.spaces;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: c.error),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            block.allDay
                                ? Icons.event_busy_outlined
                                : Icons.lock_clock_outlined,
                            size: 20,
                            color: c.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                block.allDay
                                    ? 'Entire day'
                                    : '${_edge(context, block.start, day)} – ${_edge(context, block.end, day)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                block.allDay
                                    ? '${_edge(context, block.start, day)} – ${_edge(context, block.end, day)}'
                                    : 'Specific hours',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in spaces)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              name,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Blocked by ${block.creator} · ${block.createdAt.replaceFirst('T', ' ')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (onUnblock != null || busy)
                          TextButton.icon(
                            onPressed: busy ? null : onUnblock,
                            icon: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded, size: 18),
                            label: Text(busy ? 'Unblocking…' : 'Unblock'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NewSlotBlockScreen extends StatefulWidget {
  const NewSlotBlockScreen({super.key, this.launch = const BlockLaunch()});
  final BlockLaunch launch;
  @override
  State<NewSlotBlockScreen> createState() => _NewSlotBlockScreenState();
}

class _NewSlotBlockScreenState extends State<NewSlotBlockScreen> {
  late final cubit = getIt<BlockFormCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.launch,
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> time(BlockFormModel s, bool start) async {
    final v = await showAppTimePicker(
      context: context,
      initialTime: start ? s.start : s.end,
    );
    if (v != null && !cubit.isClosed) cubit.time(v, start: start);
  }

  Future<void> pickDate(BlockFormModel s) async {
    final today = DateTime.parse(s.business!.today),
        last = DateTime(2100, 12, 31);
    var initial = DateTime.tryParse(s.date) ?? today;
    if (initial.isBefore(today)) initial = today;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
    );
    if (value != null && !cubit.isClosed) cubit.date(bookingDate(value));
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<BlockFormCubit, BlockFormModel>(
    bloc: cubit,
    listenWhen: (a, b) => a.savedId != b.savedId,
    listener: (context, s) {
      if (s.savedId != null) context.pop(true);
    },
    builder: (context, s) {
      final ready = !s.loading && s.catalog.canManage && s.business != null;
      return PopScope(
        canPop: !s.locked,
        child: AppPage(
          title: s.review ? 'Review blocked slots' : 'Block slots',
          back: true,
          showAppBar: true,
          compactHeader: true,
          maxWidth: 760,
          onBack: () => s.locked
              ? showMessage(
                  context,
                  'Retry to verify this block before leaving.',
                )
              : s.review
              ? cubit.edit()
              : context.pop(),
          bottomBar: ready ? _BlockBar(model: s, onSubmit: cubit.submit) : null,
          children: [
            if (s.loading)
              const AppLoadingState(
                initial: true,
                label: 'Getting spaces ready…',
              ),
            if (s.error != null && !ready) ...[
              AppErrorWidget(
                message: s.error!,
                onRetry: s.locked ? cubit.submit : () => cubit.load(),
              ),
              const SizedBox(height: 16),
            ],
            if (ready && s.review) _ReviewCard(model: s, onEdit: cubit.edit),
            if (ready && !s.review) ...[_spaces(context, s), _when(context, s)],
            if (!s.loading && s.catalog.businesses.isEmpty && s.error == null)
              const AppEmptyState(
                showCard: false,
                title: 'No spaces ready',
                message:
                    'Configure and activate a business before blocking its spaces.',
                icon: Icons.meeting_room_outlined,
              ),
          ],
        ),
      );
    },
  );

  Widget _spaces(BuildContext context, BlockFormModel s) {
    final b = s.business!, all = s.spaces.length == b.spaces.length;
    return BookingFormSection(
      number: 1,
      title: 'Select spaces',
      summary: s.spaces.isEmpty
          ? 'Choose one or more spaces to close'
          : '${s.spaces.length} of ${b.spaces.length} selected',
      children: [
        if (s.catalog.businesses.length > 1) ...[
          BookingBusinessCards(
            businesses: s.catalog.businesses,
            selected: s.businessId,
            enabled: !s.locked,
            onSelected: cubit.business,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                b.name,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(
              onPressed: s.locked
                  ? null
                  : all
                  ? cubit.clearSpaces
                  : cubit.allSpaces,
              child: Text(all ? 'Clear' : 'Select all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _ChoiceLayout(
          children: [
            for (final space in b.spaces)
              BookingChoiceCard(
                key: ValueKey('block-space-${space.id}'),
                title: space.name,
                icon: bookingBusinessIcon(b.type),
                selected: s.spaces.contains(space.id),
                compact: true,
                onTap: s.locked ? null : () => cubit.space(space.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _when(BuildContext context, BlockFormModel s) {
    final theme = Theme.of(context), c = theme.colorScheme;
    final b = s.business!;
    return BookingFormSection(
      number: 2,
      title: 'Date & time',
      summary: 'Times use ${b.timezone}',
      children: [
        BookingDateRow(
          date: s.date,
          today: b.today,
          enabled: !s.locked,
          onSelected: cubit.date,
          onPick: () => pickDate(s),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.event_busy_outlined),
                label: Text('Entire day'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.schedule_rounded),
                label: Text('Specific hours'),
              ),
            ],
            selected: {s.allDay},
            onSelectionChanged: s.locked ? null : (v) => cubit.allDay(v.single),
          ),
        ),
        const SizedBox(height: 16),
        if (s.spaces.isEmpty)
          _Hint(
            icon: Icons.touch_app_outlined,
            text: 'Choose a space to see its slots for this day.',
          )
        else if (s.allDay)
          _Hint(
            icon: s.busySlots > 0
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            color: s.busySlots > 0 ? c.error : c.primary,
            text: s.slotsLoading && s.slots.isEmpty
                ? 'Checking bookings for this day…'
                : s.busySlots > 0
                ? 'This day already has bookings. Reschedule or cancel them before blocking the entire day, or block specific hours instead.'
                : 'No bookings on this day. The selected spaces will be closed from midnight to midnight.',
          )
        else if (s.custom) ...[
          Text('Exact times', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: 'Start',
                  value: s.start,
                  onTap: s.locked ? null : () => time(s, true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeTile(
                  label: 'Finish',
                  value:
                      '${TimeFormat.display(s.end)}${s.endDate != s.date ? ' +1 day' : ''}',
                  onTap: s.locked ? null : () => time(s, false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A finish at or before the start means the following day (up to one day).',
            style: theme.textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: s.locked ? null : cubit.useGrid,
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Pick from slots'),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose hours to block',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh slots',
                onPressed: s.locked || s.slotsLoading ? null : cubit.loadSlots,
                icon: s.slotsLoading
                    ? const AppRefreshIndicator(
                        label: 'Checking slots…',
                        iconOnly: true,
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          Text(
            'Tap the first and last half hour. Tap the start again to clear.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          const _Legend(),
          const SizedBox(height: 12),
          if (s.slotsError != null)
            AppErrorWidget(
              message: s.slotsError!,
              onRetry: s.locked ? null : cubit.loadSlots,
            ),
          if (s.slotsLoading && s.slots.isEmpty)
            const AppLoadingState(initial: true, label: 'Checking slots…')
          else if (s.slots.isNotEmpty)
            _BlockTimeGrid(
              model: s,
              enabled: !s.locked,
              onSelected: cubit.pick,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: s.locked
                  ? null
                  : () => cubit.time(s.start, start: true),
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Enter exact times'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme, tint = color ?? c.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.value, this.onTap});
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = theme.colorScheme;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.outline.withValues(alpha: .4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.schedule, size: 18, color: c.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget item(Color fill, Color border, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(c.surface, c.outline.withValues(alpha: .4), 'Available'),
        item(c.primary, c.primary, 'Selected'),
        item(
          c.onSurface.withValues(alpha: .06),
          c.outline.withValues(alpha: .4),
          'Booked',
        ),
        item(c.errorContainer, c.error.withValues(alpha: .5), 'Blocked'),
      ],
    );
  }
}

/// Same look as the new-booking time grid, over half hours of the selected
/// spaces. Past half hours are hidden.
class _BlockTimeGrid extends StatelessWidget {
  const _BlockTimeGrid({
    required this.model,
    required this.enabled,
    required this.onSelected,
  });
  final BlockFormModel model;
  final bool enabled;
  final ValueChanged<BlockSlot> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final s = model, c = Theme.of(context).colorScheme;
      final columns = box.maxWidth >= 600
          ? 6
          : box.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 3
          : 2;
      final width = (box.maxWidth - (columns - 1) * 8) / columns;
      final visible = s.slots.where((x) => x.status != 'past').toList();
      if (visible.isEmpty) {
        return const _Hint(
          icon: Icons.history_toggle_off,
          text: 'This day has no remaining slots.',
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in visible)
            Builder(
              builder: (context) {
                final t = slot.time;
                final start = s.hasRange && t == s.from,
                    end = s.hasRange && t == s.until,
                    active = start || end,
                    inRange =
                        s.hasRange &&
                        t.compareTo(s.from!) > 0 &&
                        t.compareTo(s.until!) < 0;
                final selectable = enabled && slot.open;
                final blocked = slot.status == 'blocked';
                final status = start && end
                    ? 'Until ${blockSlotEnd(t, s.slotStep)}'
                    : start
                    ? 'From'
                    : end
                    ? 'Until ${blockSlotEnd(t, s.slotStep)}'
                    : inRange
                    ? 'Blocking'
                    : switch (slot.status) {
                        'booked' => 'Booked',
                        'blocked' => 'Blocked',
                        _ => 'Available',
                      };
                final text = active
                    ? c.onPrimary
                    : blocked
                    ? c.onErrorContainer
                    : selectable
                    ? c.onSurface
                    : c.onSurfaceVariant;
                return SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    selected: active || inRange,
                    enabled: selectable,
                    label: '$t, $status',
                    child: Material(
                      color: active
                          ? c.primary
                          : inRange
                          ? c.primary.withValues(alpha: .12)
                          : blocked
                          ? c.errorContainer
                          : selectable
                          ? c.surface
                          : c.onSurface.withValues(alpha: .06),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: active || inRange
                              ? c.primary
                              : blocked
                              ? c.error.withValues(alpha: .5)
                              : c.outline.withValues(alpha: .4),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('block-time-$t'),
                        onTap: selectable ? () => onSelected(slot) : null,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 72),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                t,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: text,
                                  decoration: slot.status == 'booked' && !active
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                status,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: text),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

String _range(BlockFormModel s) => s.allDay
    ? 'Entire day'
    : !s.timeChosen
    ? 'Choose hours'
    : '${s.start} – ${TimeFormat.display(s.end)}${s.endDate != s.date ? ' +1 day' : ''}';

class _BlockBar extends StatelessWidget {
  const _BlockBar({required this.model, required this.onSubmit});
  final BlockFormModel model;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final s = model, theme = Theme.of(context), c = theme.colorScheme;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BLOCKING',
          style: theme.textTheme.labelSmall?.copyWith(
            color: c.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        Text(
          _range(s),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          s.spaces.isEmpty
              ? 'Choose a space'
              : '${s.spaces.length} space${s.spaces.length == 1 ? '' : 's'} · ${_shortDay(context, s.date)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
    final action = AppButton(
      label: s.pending != null
          ? 'Retry block'
          : s.review
          ? 'Confirm block'
          : 'Review block',
      icon: s.review ? Icons.lock_rounded : Icons.check_rounded,
      busy: s.saving,
      busyLabel: 'Blocking…',
      onPressed: s.saving ? null : onSubmit,
    );
    return Material(
      elevation: 16,
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 728),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, box) =>
                        box.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              summary,
                              const SizedBox(height: 10),
                              action,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 2, child: summary),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: action),
                            ],
                          ),
                  ),
                  if (s.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.model, required this.onEdit});
  final BlockFormModel model;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final s = model, theme = Theme.of(context), c = theme.colorScheme;
    final names = s.business!.spaces
        .where((p) => s.spaces.contains(p.id))
        .map((p) => p.name)
        .toList();
    Widget row(IconData icon, String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lock_clock_outlined,
                      color: c.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _range(s),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _day(context, s.date),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              row(
                bookingBusinessIcon(s.business!.type),
                'Business',
                Text(s.business!.name, style: theme.textTheme.bodyLarge),
              ),
              row(
                Icons.grid_view_rounded,
                'Spaces',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in names)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(name, style: theme.textTheme.labelMedium),
                      ),
                  ],
                ),
              ),
              row(
                Icons.schedule_rounded,
                'From',
                Text(
                  '${_shortDay(context, s.date)} · ${s.startTime}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              row(
                Icons.flag_outlined,
                'Until',
                Text(
                  '${_shortDay(context, s.endDate)} · ${s.endTime}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              row(
                Icons.public,
                'Time zone',
                Text(s.business!.timezone, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Hint(
          icon: Icons.info_outline,
          text:
              'No one can book these spaces during this time. Shared ground layouts and sports using the same ground are also closed. Existing bookings are never cancelled.',
        ),
        const SizedBox(height: 8),
        if (!s.locked)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit selection'),
            ),
          ),
      ],
    );
  }
}

class _ChoiceLayout extends StatelessWidget {
  const _ChoiceLayout({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      final columns =
          children.length == 1 || (largeText && constraints.maxWidth < 380)
          ? 1
          : constraints.maxWidth >= 620
          ? 3
          : 2;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
