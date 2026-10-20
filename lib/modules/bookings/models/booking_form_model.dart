import 'booking_payment_entry_model.dart';
import 'booking_models.dart';
import 'booking_discount.dart';
import 'booking_time_cell.dart';
import 'booking_space_group.dart';
import 'package:equatable/equatable.dart';

class BookingDraft extends Equatable {
  BookingDraft({
    this.businessId,
    this.spaceId,
    this.optionId,
    this.sport,
    this.date = '',
    this.time = '09:00',
    this.duration = 60,
    this.people = '1',
    this.customer = const BookingCustomer(),
    this.notes = '',
    this.reason = '',
    this.discount,
    Iterable<BookingPaymentDraft> payments = const [],
    BookingPaymentDraft? initialPayment,
  }) : initialPayment =
           initialPayment ?? BookingPaymentDraft(id: 'initial-payment'),
       payments = List.unmodifiable(payments);
  final String? businessId, spaceId, optionId, sport;
  final String date, time, people, notes, reason;
  final int duration;
  final BookingDiscount? discount;
  int get startMinute =>
      int.parse(time.split(':')[0]) * 60 + int.parse(time.split(':')[1]);
  String get endTime {
    final minute = (startMinute + duration) % 1440;
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  }

  bool get endsNextDay => startMinute + duration >= 1440;

  final BookingCustomer customer;
  final List<BookingPaymentDraft> payments;
  final BookingPaymentDraft initialPayment;
  List<BookingPaymentDraft> get editablePayments =>
      payments.isEmpty ? [initialPayment] : payments;
  List<BookingPaymentDraft> get recordedPayments =>
      payments.where((p) => !p.isBlank).toList(growable: false);
  BookingSelection? get selection =>
      businessId == null ||
          spaceId == null ||
          optionId == null ||
          date.isEmpty ||
          int.tryParse(people) == null ||
          int.parse(people) < 1
      ? null
      : BookingSelection(
          businessId: businessId!,
          resourceId: spaceId!,
          optionId: optionId!,
          date: date,
          time: time,
          duration: duration,
          people: int.parse(people),
          discount: discount,
        );
  int get received => payments.fold(0, (n, p) => n + (p.minor ?? 0));
  BookingDraft copyWith({
    String? businessId,
    String? spaceId,
    String? optionId,
    String? sport,
    String? date,
    String? time,
    int? duration,
    String? people,
    BookingCustomer? customer,
    String? notes,
    String? reason,
    Iterable<BookingPaymentDraft>? payments,
    BookingDiscount? discount,
    bool clearDiscount = false,
    bool clearSport = false,
    bool clearSpace = false,
    bool clearOption = false,
  }) => BookingDraft(
    discount: clearDiscount ? null : discount ?? this.discount,
    sport: clearSport ? null : sport ?? this.sport,
    businessId: businessId ?? this.businessId,
    spaceId: clearSpace ? null : spaceId ?? this.spaceId,
    optionId: (clearSpace || clearOption) ? null : optionId ?? this.optionId,
    date: date ?? this.date,
    time: time ?? this.time,
    duration: duration ?? this.duration,
    people: people ?? this.people,
    customer: customer ?? this.customer,
    notes: notes ?? this.notes,
    reason: reason ?? this.reason,
    payments: payments ?? this.payments,
    initialPayment: initialPayment,
  );
  @override
  List<Object?> get props => [
    businessId,
    sport,
    spaceId,
    optionId,
    date,
    time,
    duration,
    people,
    customer,
    notes,
    reason,
    payments,
    initialPayment,
    discount,
  ];
}

class BookingFormModel extends Equatable {
  BookingFormModel({
    this.catalog = const BookingCatalog(),
    BookingDraft? draft,
    this.original,
    this.quote,
    Iterable<BookingSlot> slots = const [],
    Iterable<BookingSlot> endSlots = const [],
    Iterable<BookingCustomer> customers = const [],
    this.loading = true,
    this.checking = false,
    this.slotsLoading = false,
    this.slotsLoaded = false,
    this.slotsError,
    this.searching = false,
    this.saving = false,
    this.review = false,
    this.choosingEnd = false,
    this.rangeComplete = false,
    this.error,
    this.resultId,
    this.pending,
    this.activeSection = 0,
  }) : draft = draft ?? BookingDraft(),
       slots = List.unmodifiable(slots),
       endSlots = List.unmodifiable(endSlots),
       customers = List.unmodifiable(customers);
  final BookingCatalog catalog;
  final BookingDraft draft;
  final BookingRecord? original;
  final BookingQuote? quote;
  final List<BookingSlot> slots, endSlots;
  final List<BookingCustomer> customers;
  final bool loading, checking, searching, saving, review;
  final bool choosingEnd, rangeComplete;
  final bool slotsLoading, slotsLoaded;
  final String? slotsError;
  final String? error, resultId;
  final BookingCommand? pending;
  final int activeSection;

  /// Immediate preview from the already loaded start-time tariff. The server
  /// quote remains authoritative for review, payments and confirmation.
  int? get estimatedSubtotal {
    if (option?.minimumDuration != null && !rangeComplete) return null;
    final start = slots
        .where(
          (s) =>
              s.selectable &&
              s.time == draft.time &&
              (s.date == null || s.date == draft.date),
        )
        .firstOrNull;
    if (start == null) return null;
    final minimum = option?.minimumDuration;
    if (minimum == null) return start.total;
    if (minimum <= 0 || draft.duration < minimum) return null;
    return (start.total * draft.duration / minimum).round();
  }

  int? get estimatedTotal {
    final subtotal = estimatedSubtotal;
    if (subtotal == null) return null;
    return (subtotal - (draft.discount?.reduction(subtotal) ?? 0)).clamp(
      0,
      subtotal,
    );
  }

  int? get displayedTotal => quote?.total ?? estimatedTotal;
  BookingBusiness? get business =>
      catalog.businesses.where((b) => b.id == draft.businessId).firstOrNull;
  BookingSpace? get space =>
      business?.spaces.where((s) => s.id == draft.spaceId).firstOrNull;
  BookingOption? get option =>
      space?.options.where((o) => o.id == draft.optionId).firstOrNull;
  String? get selectedSport => draft.sport ?? option?.sport;
  List<String> get sports =>
      business?.spaces
          .expand((p) => p.options)
          .map((o) => o.sport)
          .whereType<String>()
          .toSet()
          .toList() ??
      [];
  List<BookingSpace> get sportSpaces =>
      business?.spaces
          .where(
            (p) =>
                selectedSport == null ||
                p.options.any((o) => o.sport == selectedSport),
          )
          .toList() ??
      [];
  List<BookingOption> get visibleOptions =>
      space?.options
          .where((o) => selectedSport == null || o.sport == selectedSport)
          .toList() ??
      [];
  String? get selectedSpaceTitle {
    if (business?.type != 'turf') return space?.name;
    return BookingSpaceGroup.turf(sportSpaces)
        .expand((group) => group.choices)
        .where((choice) => choice.space.id == draft.spaceId)
        .firstOrNull
        ?.title;
  }

  String get spaceSummary => [
    if (selectedSport != null)
      switch (selectedSport) {
        'football' => 'Football',
        'cricket' => 'Cricket',
        _ => selectedSport!,
      },
    if (space != null) space!.name,
    if (option != null && visibleOptions.length > 1)
      option!.format ?? option!.name,
  ].join(' · ');
  List<BookingTimeCell> get timeCells {
    if (draft.date.isEmpty) return const [];
    final day = DateTime.parse('${draft.date}T00:00:00Z');
    final starts = <String, BookingSlot>{}, ends = <String, BookingSlot>{};
    String endDate(BookingSlot slot) =>
        slot.date ??
        bookingDate(
          day.add(
            Duration(days: (draft.startMinute + (slot.duration ?? 0)) ~/ 1440),
          ),
        );
    for (final slot in slots) {
      starts['${slot.date ?? draft.date}T${slot.time}'] = slot;
    }
    for (final slot in endSlots) {
      ends['${endDate(slot)}T${slot.time}'] = slot;
    }
    final keys = {...starts.keys, ...ends.keys}.toList()..sort();
    final startKey = '${draft.date}T${draft.time}';
    final finishDate = bookingDate(
      day.add(Duration(days: (draft.startMinute + draft.duration) ~/ 1440)),
    );
    final finishKey = '${finishDate}T${draft.endTime}';
    return [
      for (final key in keys)
        (() {
          final base = starts[key], finish = ends[key], slot = finish ?? base!;
          final start = choosingEnd && key == startKey;
          final end = choosingEnd && rangeComplete && key == finishKey;
          final waiting = choosingEnd && !rangeComplete;
          final validEnd = finish?.selectable == true;
          final wallMinutes = DateTime.parse(
            '$key:00Z',
          ).difference(DateTime.parse('$startKey:00Z')).inMinutes;
          final belowMinimum =
              wallMinutes > 0 && wallMinutes < (option?.minimumDuration ?? 0);
          final inRange =
              choosingEnd &&
              rangeComplete &&
              key.compareTo(startKey) > 0 &&
              key.compareTo(finishKey) < 0;
          final enabled =
              !locked &&
              (start ||
                  end ||
                  (waiting
                      ? !slotsLoading && validEnd
                      : base?.selectable == true));
          return BookingTimeCell(
            slot: slot,
            date: key.substring(0, 10),
            enabled: enabled,
            start: start,
            end: end,
            inRange: inRange,
            label: start
                ? 'Start · tap to clear'
                : end
                ? 'End · tap to clear'
                : waiting
                ? slotsLoading
                      ? 'Checking…'
                      : validEnd
                      ? '${finish!.duration} min'
                      : finish?.status == 'minimum' || belowMinimum
                      ? 'Minimum ${option?.minimumDuration} min'
                      : finish?.past == true ||
                            (finish == null && base?.past == true)
                      ? 'Past'
                      : finish?.status == 'booked'
                      ? (business?.type == 'pool' ? 'Unavailable' : 'Booked')
                      : 'Not a valid end'
                : inRange
                ? 'Selected range'
                : base?.status == 'end_only' || base == null
                ? 'End only'
                : null,
          );
        })(),
    ];
  }

  BookingPaymentEntryModel get paymentEntry =>
      BookingPaymentEntryModel(total: displayedTotal, payments: draft.payments);
  int? get remainingPayment => paymentEntry.remaining;
  int? paymentBalance(String id) => paymentEntry.balanceFor(id);
  String? paymentError(BookingPaymentDraft p) => paymentEntry.errorFor(p);

  bool get locked => saving || pending != null;
  int get paid => original?.netPaid ?? draft.received;
  int? get balance =>
      quote == null ? null : (quote!.total - paid).clamp(0, 1000000000);
  int? get refund =>
      quote == null ? null : (paid - quote!.total).clamp(0, 1000000000);
  BookingFormModel copyWith({
    BookingCatalog? catalog,
    BookingDraft? draft,
    BookingRecord? original,
    BookingQuote? quote,
    bool clearQuote = false,
    Iterable<BookingSlot>? slots,
    Iterable<BookingSlot>? endSlots,
    Iterable<BookingCustomer>? customers,
    bool? loading,
    bool? checking,
    bool? slotsLoading,
    bool? slotsLoaded,
    String? slotsError,
    bool clearSlotsError = false,
    bool? searching,
    bool? saving,
    bool? review,
    bool? choosingEnd,
    bool? rangeComplete,
    String? error,
    String? resultId,
    BookingCommand? pending,
    bool clearPending = false,
    int? activeSection,
  }) => BookingFormModel(
    catalog: catalog ?? this.catalog,
    draft: draft ?? this.draft,
    original: original ?? this.original,
    quote: clearQuote ? null : quote ?? this.quote,
    slots: slots ?? this.slots,
    endSlots: endSlots ?? this.endSlots,
    customers: customers ?? this.customers,
    loading: loading ?? this.loading,
    checking: checking ?? this.checking,
    slotsLoading: slotsLoading ?? this.slotsLoading,
    slotsLoaded: slotsLoaded ?? this.slotsLoaded,
    slotsError: clearSlotsError ? null : slotsError ?? this.slotsError,
    searching: searching ?? this.searching,
    saving: saving ?? this.saving,
    review: review ?? this.review,
    choosingEnd: choosingEnd ?? this.choosingEnd,
    rangeComplete: rangeComplete ?? this.rangeComplete,
    error: error,
    resultId: resultId ?? this.resultId,
    pending: clearPending ? null : pending ?? this.pending,
    activeSection: activeSection ?? this.activeSection,
  );
  @override
  List<Object?> get props => [
    catalog,
    draft,
    original,
    quote,
    slots,
    endSlots,
    customers,
    loading,
    checking,
    slotsLoading,
    slotsLoaded,
    slotsError,
    searching,
    saving,
    review,
    choosingEnd,
    rangeComplete,
    error,
    resultId,
    pending,
    activeSection,
  ];
}
