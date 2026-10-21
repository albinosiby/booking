import '../../booking_blocks/models/slot_block_models.dart';
import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../cubit/booking_list_cubit.dart';
import '../models/booking_list_model.dart';
import '../models/booking_models.dart';
import 'booking_widgets.dart';

/// Shared reservation presentation; Cubit owns filters, loading and pagination.
class BookingAgendaView extends StatelessWidget {
  const BookingAgendaView({
    super.key,
    required this.state,
    required this.cubit,
    required this.calendar,
    this.back = false,
  });
  final BookingListModel state;
  final BookingListCubit cubit;
  final bool calendar, back;

  void create(BuildContext context) => context.push(
    Uri(
      path: '/booking/new',
      queryParameters: {
        if (state.businessId != null) 'business_id': state.businessId!,
        if (state.spaceId != null) 'space_id': state.spaceId!,
        if (state.date != null) 'date': state.date!,
      },
    ).toString(),
  );

  Future<void> filters(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _BookingFilters(cubit: cubit, initial: state, calendar: calendar),
  );

  @override
  Widget build(BuildContext context) {
    final s = state, theme = Theme.of(context);
    final selected = DateTime.tryParse(s.date ?? '') ?? DateTime.now();
    final dayLabel = MaterialLocalizations.of(context).formatFullDate(selected);
    final dateLabel = MaterialLocalizations.of(
      context,
    ).formatMediumDate(selected);
    final businesses = s.catalog.filters.where((b) => b.id == s.businessId);
    final activeFilters = [
      if (businesses.isNotEmpty) businesses.first.name,
      if (s.spaceId != null)
        s.catalog.filters
            .expand((b) => b.spaces)
            .where((p) => p.id == s.spaceId)
            .firstOrNull
            ?.name,
    ].whereType<String>().join(' · ');
    return AppPage(
      back: back,
      eyebrow: calendar ? null : 'RESERVATIONS',
      title: calendar ? 'Calendar' : 'Bookings',
      showAppBar: true,
      compactHeader: true,
      actions: [
        if (s.catalog.canManage)
          IconButton(
            tooltip: 'Block slots',
            icon: const Icon(Icons.lock_clock_outlined),
            onPressed: () => context.push(
              '/bookings/blocks',
              extra: BlockLaunch(
                businessId: s.businessId,
                spaceId: s.spaceId,
                date: s.date,
              ),
            ),
          ),
        IconButton(
          tooltip: 'Filter bookings',
          onPressed: () => filters(context),
          icon: const Icon(Icons.tune_rounded),
        ),
        IconButton(
          tooltip: 'Refresh bookings',
          onPressed: s.loading ? null : cubit.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: calendar ? 'Choose calendar date' : 'Choose booking date',
          icon: Icon(
            s.date == null
                ? Icons.calendar_today_outlined
                : Icons.event_available_rounded,
          ),
          onPressed: () async {
            var initial = DateTime.tryParse(s.date ?? '') ?? DateTime.now();
            if (initial.isBefore(DateTime(2000))) {
              initial = DateTime(2000);
            }
            if (initial.isAfter(DateTime(2100, 12, 31))) {
              initial = DateTime(2100, 12, 31);
            }
            final date = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100, 12, 31),
            );
            if (date != null && context.mounted) {
              cubit.date(bookingDate(date));
            }
          },
        ),
      ],
      subtitle: calendar ? null : 'Every reservation, in one place.',
      fillRemaining: s.hasLoaded && s.error == null && s.bookings.isEmpty
          ? _BookingEmptyMessage(calendar: calendar)
          : null,
      maxWidth: 760,
      scrollId: calendar
          ? 'booking-calendar-agenda'
          : 'booking-reservation-list',
      floatingActionButton: s.catalog.canManage
          ? NewBookingFab(onPressed: () => create(context))
          : null,
      children: [
        if (calendar) ...[
          BookingCalendarPanel(
            date: selected,
            counts: s.dateCounts,
            onRangeChanged: cubit.countRange,
            onChanged: (d) => cubit.date(bookingDate(d)),
          ),
          if (s.countsError != null)
            TextButton.icon(
              onPressed: cubit.refreshCounts,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry booking counts'),
            ),
        ],
        if (activeFilters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(activeFilters, style: theme.textTheme.bodySmall),
          ),
        if (!calendar) ...[
          TextFormField(
            key: ValueKey('booking-search-${s.catalog.canView}'),
            initialValue: s.query,
            onChanged: cubit.query,
            onFieldSubmitted: (_) => cubit.search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Customer, phone or reference',
              labelText: 'Search bookings',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search bookings',
                onPressed: cubit.search,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All spaces'),
                    selected: s.businessId == null && s.spaceId == null,
                    onSelected: (selected) {
                      if (selected) cubit.filters();
                    },
                  ),
                ),
                for (final space in orderedWorkspaceBusinesses(
                  context,
                  s.spaceFilters,
                  (f) => f.businessId,
                ))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(space.label),
                      selected:
                          s.businessId == space.businessId &&
                          s.spaceId == space.spaceId,
                      onSelected: (selected) {
                        if (selected) {
                          cubit.filters(
                            businessId: space.businessId,
                            spaceId: space.spaceId,
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (!calendar && s.date != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(dateLabel),
              deleteButtonTooltipMessage: 'Show all dates',
              onDeleted: () => cubit.date(null),
            ),
          ),
        SizedBox(height: calendar ? 12 : 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    calendar ? 'Bookings for $dateLabel' : 'Your bookings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (calendar) ...[
                    const SizedBox(height: 4),
                    Text(dayLabel, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (s.bookings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${s.bookings.length}${s.next == null ? '' : '+'} ${s.bookings.length == 1 ? 'booking' : 'bookings'}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (s.loading) ...[
          AppLoadingState(
            initial: !s.hasLoaded,
            label: !s.hasLoaded ? 'Loading reservations…' : null,
          ),
          const SizedBox(height: 8),
        ],
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
        if (calendar)
          for (final space in orderedWorkspaceBusinesses(
            context,
            s.bookings,
            (b) => b.selection.businessId,
          ).map((b) => b.selection.resourceId).toSet()) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${s.bookings.firstWhere((b) => b.selection.resourceId == space).businessName} · ${s.bookings.firstWhere((b) => b.selection.resourceId == space).spaceName}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            ...([
              ...s.bookings.where((b) => b.selection.resourceId == space),
            ]..sort((a, b) => a.localStart.compareTo(b.localStart))).map(
              (b) => BookingCard(
                booking: b,
                currency: s.catalog.currency,
                canCollect: s.catalog.canCollect,
              ),
            ),
          ]
        else
          ...s.bookings.map(
            (b) => BookingCard(
              booking: b,
              currency: s.catalog.currency,
              canCollect: s.catalog.canCollect,
            ),
          ),
        if (s.next != null)
          AppButton(
            label: 'Load more',
            secondary: true,
            busy: s.loadingMore,
            onPressed: s.loadingMore ? null : () => cubit.load(more: true),
          ),
      ],
    );
  }
}

class _BookingEmptyMessage extends StatelessWidget {
  const _BookingEmptyMessage({required this.calendar});
  final bool calendar;
  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey(
      calendar ? 'calendar-empty-message' : 'bookings-empty-message',
    ),
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.event_available_outlined,
        size: 36,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(height: 16),
      Text(
        calendar ? 'No bookings on this day' : 'Your schedule starts here',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        calendar
            ? 'Choose another date or adjust your filters.'
            : 'Reservations appear here as they are added. Use New booking to get started.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class BookingCalendarPanel extends StatefulWidget {
  const BookingCalendarPanel({
    super.key,
    required this.date,
    required this.onChanged,
    this.counts = const {},
    this.onRangeChanged,
  });
  final Map<String, int> counts;
  final void Function(String from, String until)? onRangeChanged;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  State<BookingCalendarPanel> createState() => _BookingCalendarPanelState();
}

class _BookingCalendarPanelState extends State<BookingCalendarPanel> {
  static final first = DateTime.utc(2000);
  static final last = DateTime.utc(2100, 12, 31);
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const months = [
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
  late final ScrollController controller = ScrollController(
    keepScrollOffset: false,
  )..addListener(reportRange);
  double extent = 80, viewport = 0;
  int get selectedIndex => DateTime.utc(
    widget.date.year,
    widget.date.month,
    widget.date.day,
  ).difference(first).inDays;

  void reportRange() {
    if (!mounted || !controller.hasClients || viewport == 0) return;
    final middle = ((controller.offset + viewport / 2) / extent).floor();
    final from = first.add(
      Duration(days: (middle - 15).clamp(0, last.difference(first).inDays)),
    );
    final until = first.add(
      Duration(days: (middle + 15).clamp(0, last.difference(first).inDays)),
    );
    // Scroll callbacks may occur during layout; publish after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onRangeChanged?.call(bookingDate(from), bookingDate(until));
      }
    });
  }

  void revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = (selectedIndex * extent - (viewport - extent) / 2).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(target);
      reportRange();
    });
  }

  @override
  void didUpdateWidget(covariant BookingCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (bookingDate(oldWidget.date) != bookingDate(widget.date)) {
      revealSelected();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.7,
    );
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    localizations.formatMonthYear(widget.date),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onChanged(DateTime.now());
                  revealSelected();
                },
                child: const Text('Today'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 76 * scale,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemExtent = 76 * scale;
                if (extent != itemExtent || viewport != constraints.maxWidth) {
                  extent = itemExtent;
                  viewport = constraints.maxWidth;
                  revealSelected();
                }
                return ListView.builder(
                  key: const ValueKey('booking-date-strip'),
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  itemExtent: extent,
                  itemCount: last.difference(first).inDays + 1,
                  itemBuilder: (context, index) {
                    // UTC arithmetic preserves every calendar day across DST boundaries.
                    final d = first.add(Duration(days: index));
                    final date = DateTime(d.year, d.month, d.day);
                    final selected = index == selectedIndex;
                    final count = widget.counts[bookingDate(date)];
                    final foreground = selected
                        ? colors.onPrimary
                        : colors.onSurface;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label:
                            '${localizations.formatFullDate(date)}, ${count == null ? 'booking count unavailable' : '$count bookings'}',
                        child: Material(
                          color: selected
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('booking-day-${bookingDate(date)}'),
                            onTap: () => widget.onChanged(date),
                            child: ExcludeSemantics(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${weekdays[date.weekday - 1]} · ${months[date.month - 1]}',
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 9,
                                      height: 1.15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 20,
                                      height: 1.15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    count == null ? '—' : '$count',
                                    key: ValueKey(
                                      'booking-count-${bookingDate(date)}',
                                    ),
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 10,
                                      height: 1.15,
                                      fontWeight: count != null && count > 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingFilters extends StatefulWidget {
  const _BookingFilters({
    required this.cubit,
    required this.initial,
    required this.calendar,
  });
  final BookingListCubit cubit;
  final BookingListModel initial;
  final bool calendar;
  @override
  State<_BookingFilters> createState() => _BookingFiltersState();
}

class _BookingFiltersState extends State<_BookingFilters> {
  late String? business = widget.initial.businessId;
  late String? space = widget.initial.spaceId;
  late String? status = widget.initial.status;
  late String query = widget.initial.query;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Filter bookings',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          AppPicker(
            label: 'Business filter',
            value: business ?? 'all',
            items: [
              const PickerItem('all', 'All assigned businesses'),
              ...orderedWorkspaceBusinesses(
                context,
                widget.initial.catalog.filters,
                (b) => b.id,
              ).map((b) => PickerItem(b.id, b.name)),
            ],
            onChanged: (v) => setState(() {
              business = v == 'all' ? null : v;
              space = null;
            }),
          ),
          if (widget.calendar) ...[
            const SizedBox(height: 16),
            AppPicker(
              label: 'Space filter',
              value: space ?? 'all',
              items: [
                const PickerItem('all', 'All assigned spaces'),
                ...orderedWorkspaceBusinesses(
                      context,
                      widget.initial.catalog.filters,
                      (b) => b.id,
                    )
                    .where((b) => business == null || b.id == business)
                    .expand(
                      (b) => b.spaces.map(
                        (p) => PickerItem(p.id, '${b.name} · ${p.name}'),
                      ),
                    ),
              ],
              onChanged: (v) => setState(() => space = v == 'all' ? null : v),
            ),
          ],
          if (widget.calendar) ...[
            const SizedBox(height: 16),
            TextFormField(
              initialValue: query,
              onChanged: (v) => query = v,
              decoration: const InputDecoration(
                labelText: 'Search customer, phone or reference',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 16),
            AppPicker(
              label: 'Booking status',
              value: status ?? 'all',
              items: const [
                PickerItem('all', 'All statuses'),
                PickerItem('confirmed', 'Confirmed'),
                PickerItem('completed', 'Completed'),
                PickerItem('cancelled', 'Cancelled'),
                PickerItem('no_show', 'No-show'),
              ],
              onChanged: (v) => setState(() => status = v == 'all' ? null : v),
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: 'Apply filters',
            onPressed: () {
              widget.cubit.filters(
                businessId: business,
                spaceId: space,
                status: status,
                query: query,
                updateSearch: widget.calendar,
              );
              Navigator.pop(context);
            },
          ),
          TextButton(
            onPressed: () {
              widget.cubit.filters(updateSearch: widget.calendar);
              Navigator.pop(context);
            },
            child: const Text('Reset filters'),
          ),
        ],
      ),
    ),
  );
}
