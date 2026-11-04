import 'package:equatable/equatable.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';

class BlockLaunch {
  const BlockLaunch({this.businessId, this.spaceId, this.date});
  final String? businessId, spaceId, date;
}

class SlotBlock extends Equatable {
  SlotBlock({
    required this.id,
    required this.start,
    required this.end,
    required this.timezone,
    required this.creator,
    required this.createdAt,
    required this.allDay,
    required this.canUnblock,
    Iterable<String> spaces = const [],
    this.sharedGround = false,
  }) : spaces = List.unmodifiable(spaces);
  final String id, start, end, timezone, creator, createdAt;
  final bool allDay, canUnblock, sharedGround;
  final List<String> spaces;
  @override
  List<Object?> get props => [
    id,
    start,
    end,
    timezone,
    creator,
    createdAt,
    allDay,
    canUnblock,
    spaces,
    sharedGround,
  ];
}

/// One half-hour of the selected spaces on the block form's grid.
class BlockSlot extends Equatable {
  const BlockSlot(this.time, this.status);
  final String time;

  /// available, booked, blocked or past.
  final String status;
  bool get open => status == 'available';
  @override
  List<Object?> get props => [time, status];
}

String blockSlotEnd(String time, int minutes) {
  final total =
      int.parse(time.substring(0, 2)) * 60 +
      int.parse(time.substring(3)) +
      minutes;
  final wrapped = total % 1440;
  return '${(wrapped ~/ 60).toString().padLeft(2, '0')}:${(wrapped % 60).toString().padLeft(2, '0')}';
}

/// One continuous interval to block. [end] at or before [start] finishes on
/// the next day; grid ranges use 24:00 for midnight until they are saved.
class BlockPeriod extends Equatable {
  const BlockPeriod(this.start, this.end);
  final String start, end;
  bool overlaps(String from, String until) =>
      start.compareTo(until) < 0 && from.compareTo(end) < 0;
  bool get overnight => end.compareTo(start) <= 0;
  String get label =>
      '$start – ${TimeFormat.display(end)}${overnight && end != '00:00' ? ' +1 day' : ''}';
  @override
  List<Object?> get props => [start, end];
}

class SlotBlockPage {
  SlotBlockPage(Iterable<SlotBlock> items, this.next)
    : items = List.unmodifiable(items);
  final List<SlotBlock> items;
  final int? next;
}

class BlockRequest {
  BlockRequest({
    required this.key,
    required this.businessId,
    required Iterable<String> spaces,
    required this.date,
    required this.allDay,
    required this.start,
    required this.end,
  }) : spaces = List.unmodifiable(spaces);
  final String key, businessId, date, start, end;
  final bool allDay;
  final List<String> spaces;
  String get endDate => bookingDate(
    DateTime.parse(
      '${date}T00:00:00Z',
    ).add(Duration(days: allDay || end.compareTo(start) <= 0 ? 1 : 0)),
  );
}

class BlockListModel extends Equatable {
  BlockListModel({
    this.catalog = const BookingCatalog(),
    this.businessId,
    this.date = '',
    Iterable<SlotBlock> blocks = const [],
    this.next,
    this.loading = false,
    this.busyId,
    this.error,
  }) : blocks = List.unmodifiable(blocks);
  final BookingCatalog catalog;
  final String? businessId, busyId, error;
  final String date;
  final List<SlotBlock> blocks;
  final int? next;
  final bool loading;
  bool get locked => busyId != null;
  BookingBusiness? get business =>
      catalog.businesses.where((b) => b.id == businessId).firstOrNull;
  BlockListModel copy({
    BookingCatalog? catalog,
    String? businessId,
    String? date,
    Iterable<SlotBlock>? blocks,
    int? next,
    bool clearNext = false,
    bool? loading,
    String? busyId,
    bool clearBusy = false,
    String? error,
  }) => BlockListModel(
    catalog: catalog ?? this.catalog,
    businessId: businessId ?? this.businessId,
    date: date ?? this.date,
    blocks: blocks ?? this.blocks,
    next: clearNext ? null : next ?? this.next,
    loading: loading ?? this.loading,
    busyId: clearBusy ? null : busyId ?? this.busyId,
    error: error,
  );
  @override
  List<Object?> get props => [
    catalog,
    businessId,
    date,
    blocks,
    next,
    loading,
    busyId,
    error,
  ];
}

class BlockFormModel extends Equatable {
  BlockFormModel({
    this.catalog = const BookingCatalog(),
    this.businessId,
    this.date = '',
    Iterable<String> spaces = const [],
    this.allDay = true,
    this.start = '09:00',
    this.end = '10:00',
    this.loading = false,
    this.saving = false,
    this.review = false,
    Iterable<BlockRequest> pending = const [],
    this.savedId,
    this.error,
    Iterable<BlockSlot> slots = const [],
    this.slotStep = 30,
    this.slotsLoading = false,
    this.slotsError,
    Iterable<BlockPeriod> ranges = const [],
    this.anchor,
    this.custom = false,
  }) : spaces = Set.unmodifiable(spaces),
       pending = List.unmodifiable(pending),
       slots = List.unmodifiable(slots),
       ranges = List.unmodifiable(
         [...ranges]..sort((a, b) => a.start.compareTo(b.start)),
       );
  final BookingCatalog catalog;
  final String? businessId, savedId, error;
  final String date, start, end;
  final Set<String> spaces;
  final bool allDay, loading, saving, review;

  /// Requests whose save result is unknown; retried with the same keys.
  final List<BlockRequest> pending;

  /// Grid state for Specific hours: tiles are clock times. [anchor] is a
  /// tapped start waiting for its end; [ranges] are finished start–end pairs.
  final List<BlockSlot> slots;
  final int slotStep;
  final bool slotsLoading, custom;
  final String? slotsError, anchor;
  final List<BlockPeriod> ranges;
  bool get locked => saving || pending.isNotEmpty;
  bool get timeChosen => allDay || custom || ranges.isNotEmpty;

  /// What will be blocked: the whole day, the exact times, or each range.
  List<BlockPeriod> get periods => allDay
      ? const [BlockPeriod('00:00', '00:00')]
      : custom
      ? [BlockPeriod(start, end)]
      : [
          for (final r in ranges)
            BlockPeriod(r.start, r.end == '24:00' ? '00:00' : r.end),
        ];

  /// Whether a range from [anchor] may finish at [time]: every half hour in
  /// between is free and it does not overlap another chosen range.
  bool canEnd(String time) {
    final from = anchor;
    if (from == null || time.compareTo(from) <= 0) return false;
    final between = slots.where(
      (s) => s.time.compareTo(from) >= 0 && s.time.compareTo(time) < 0,
    );
    return between.isNotEmpty &&
        between.every((s) => s.open) &&
        !ranges.any((r) => r.overlaps(from, time));
  }

  BlockPeriod? rangeAt(String time) => ranges
      .where((r) => r.start.compareTo(time) <= 0 && time.compareTo(r.end) < 0)
      .firstOrNull;

  int get busySlots => slots.where((s) => s.status == 'booked').length;
  String get startTime => allDay ? '00:00' : start;
  String get endTime => allDay ? '00:00' : end;
  BookingBusiness? get business =>
      catalog.businesses.where((b) => b.id == businessId).firstOrNull;
  String get endDate => date.isEmpty
      ? ''
      : bookingDate(
          DateTime.parse(
            '${date}T00:00:00Z',
          ).add(Duration(days: allDay || end.compareTo(start) <= 0 ? 1 : 0)),
        );
  String? get validation => business == null
      ? 'Choose a business.'
      : spaces.isEmpty
      ? 'Choose at least one space.'
      : spaces.length > 100
      ? 'Choose at most 100 spaces.'
      : date.isEmpty
      ? 'Choose a date.'
      : !allDay && !custom && anchor != null
      ? 'Tap the end time for the block starting at $anchor.'
      : !timeChosen
      ? 'Choose the hours to block.'
      : null;
  BlockFormModel copy({
    BookingCatalog? catalog,
    String? businessId,
    String? date,
    Iterable<String>? spaces,
    bool? allDay,
    String? start,
    String? end,
    bool? loading,
    bool? saving,
    bool? review,
    Iterable<BlockRequest>? pending,
    bool clearPending = false,
    String? savedId,
    String? error,
    Iterable<BlockSlot>? slots,
    int? slotStep,
    bool? slotsLoading,
    String? slotsError,
    bool clearSlotsError = false,
    Iterable<BlockPeriod>? ranges,
    String? anchor,
    bool clearAnchor = false,
    bool? custom,
  }) => BlockFormModel(
    catalog: catalog ?? this.catalog,
    businessId: businessId ?? this.businessId,
    date: date ?? this.date,
    spaces: spaces ?? this.spaces,
    allDay: allDay ?? this.allDay,
    start: start ?? this.start,
    end: end ?? this.end,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    review: review ?? this.review,
    pending: clearPending ? const [] : pending ?? this.pending,
    savedId: savedId ?? this.savedId,
    error: error,
    slots: slots ?? this.slots,
    slotStep: slotStep ?? this.slotStep,
    slotsLoading: slotsLoading ?? this.slotsLoading,
    slotsError: clearSlotsError ? null : slotsError ?? this.slotsError,
    ranges: ranges ?? this.ranges,
    anchor: clearAnchor ? null : anchor ?? this.anchor,
    custom: custom ?? this.custom,
  );
  @override
  List<Object?> get props => [
    catalog,
    businessId,
    date,
    spaces,
    allDay,
    start,
    end,
    loading,
    saving,
    review,
    pending,
    savedId,
    error,
    slots,
    slotStep,
    slotsLoading,
    slotsError,
    ranges,
    anchor,
    custom,
  ];
}
