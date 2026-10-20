import '../models/booking_discount.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_access.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/booking_models.dart';
import '../models/booking_form_model.dart';
import '../repositories/booking_repository.dart';

String bookingError(Object e) => e is AppException
    ? e.message
    : 'Could not complete this action. Please try again.';
String bookingScope(WorkspaceSession session) =>
    workspaceAccessScope(session.state.data);

class BookingFormCubit extends Cubit<BookingFormModel> {
  BookingFormCubit(this.session, this.repository, this.launch)
    : super(BookingFormModel()) {
    scope = bookingScope(session);
    subscription = session.snapshots.listen((_) {
      if (bookingScope(session) != scope) {
        scope = bookingScope(session);
        generation++;
        _customerMatches.clear();
        slotGeneration++;
        availabilityTimer?.cancel();
        quoteTimer?.cancel();
        emit(
          BookingFormModel(
            loading: false,
            error:
                'Your account or access changed. Reopen booking to continue.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final BookingRepository repository;
  final BookingLaunch launch;
  late StreamSubscription subscription;
  late String scope;
  int generation = 0, searchGeneration = 0, slotGeneration = 0;
  Timer? availabilityTimer, quoteTimer, customerTimer;
  final Map<String, List<BookingCustomer>> _customerMatches = {};
  String _phoneDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
  String availabilityKey(BookingDraft d) =>
      '${d.businessId}/${d.spaceId}/${d.optionId}/${d.date}/${state.choosingEnd ? d.time : d.duration}/${d.people}/${state.original?.id}/${state.choosingEnd}';
  void scheduleSlots() {
    availabilityTimer?.cancel();
    if (state.draft.selection != null) {
      availabilityTimer = Timer(Duration.zero, () => unawaited(slots()));
    }
  }

  void scheduleQuote() {
    quoteTimer?.cancel();
    if (state.draft.selection != null &&
        (state.option?.minimumDuration == null || state.rangeComplete)) {
      quoteTimer = Timer(Duration.zero, () => unawaited(checkQuote()));
    }
  }

  bool valid(int g) => !isClosed && g == generation;
  Future<void> load() async {
    final g = ++generation;
    emit(BookingFormModel());
    try {
      final results = await Future.wait<Object?>([
        repository.catalog(),
        if (launch.rescheduleId != null)
          repository.detail(launch.rescheduleId!),
      ]);
      final catalog = results[0] as BookingCatalog;
      final original = launch.rescheduleId == null
          ? null
          : results[1] as BookingRecord;
      if (!valid(g)) return;
      if (!catalog.canManage) {
        emit(
          BookingFormModel(
            loading: false,
            error: 'Booking management permission is required.',
          ),
        );
        return;
      }
      var draft = original == null
          ? BookingDraft(
              businessId: launch.businessId,
              date: launch.date ?? '',
              time: launch.time ?? '09:00',
            )
          : BookingDraft(
              businessId: original.selection.businessId,
              spaceId: original.selection.resourceId,
              optionId: original.selection.optionId,
              date: original.selection.date,
              time: original.selection.time,
              duration: original.selection.duration,
              people: '${original.selection.people}',
              customer: original.customer,
              notes: original.notes,
              discount: original.selection.discount,
            );
      emit(
        BookingFormModel(
          catalog: catalog,
          draft: draft,
          original: original,
          loading: false,
        ),
      );
      final id =
          original?.selection.businessId ??
          launch.businessId ??
          catalog.businesses
              .where((b) => b.spaces.any((p) => p.id == launch.spaceId))
              .firstOrNull
              ?.id ??
          (catalog.businesses.length == 1 ? catalog.businesses.first.id : null);
      if (id != null) {
        chooseBusiness(id, keepDraft: original != null);
        if (original == null && launch.spaceId != null) {
          chooseSpace(launch.spaceId!);
        }
      }
      scheduleSlots();
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(loading: false, error: bookingError(e)));
      }
    }
  }

  void _edit(
    BookingDraft draft, {
    bool selection = false,
    bool refreshSlots = true,
    bool preserveRange = false,
  }) {
    if (state.locked) return;
    searchGeneration++;
    if (selection) {
      generation++;
      quoteTimer?.cancel();
      if (refreshSlots) {
        slotGeneration++;
        availabilityTimer?.cancel();
      }
    }
    emit(
      state.copyWith(
        draft: draft,
        clearQuote: selection,
        choosingEnd: selection && !preserveRange ? false : null,
        rangeComplete: selection && !preserveRange ? false : null,
        slots: selection && refreshSlots ? [] : null,
        endSlots: selection && refreshSlots ? [] : null,
        slotsLoading: selection && refreshSlots ? false : null,
        slotsLoaded: selection && refreshSlots ? false : null,
        clearSlotsError: selection && refreshSlots,
        review: false,
        checking: selection ? false : null,
        customers: [],
        searching: false,
      ),
    );
    if (selection && refreshSlots) scheduleSlots();
  }

  void chooseBusiness(String id, {bool keepDraft = false}) {
    if (state.locked) return;
    if (!keepDraft && state.draft.businessId == id && state.option != null) {
      return;
    }
    final b = state.catalog.businesses.where((b) => b.id == id).firstOrNull;
    if (b == null) return;
    if (state.original != null && id != state.original!.selection.businessId) {
      return;
    }
    if (keepDraft) {
      if (!b.spaces.any((s) => s.id == state.draft.spaceId)) {
        _edit(state.draft.copyWith(clearSpace: true), selection: true);
      }
      return;
    }
    _edit(
      state.draft.copyWith(
        businessId: id,
        date:
            state.draft.date.isNotEmpty &&
                state.draft.date.compareTo(b.today) >= 0
            ? state.draft.date
            : launch.date != null && launch.date!.compareTo(b.today) >= 0
            ? launch.date
            : b.today,
        clearSpace: true,
        clearSport: true,
      ),
      selection: true,
    );
    if (b.spaces.length == 1) {
      chooseSpace(b.spaces.first.id);
    } else if (state.sports.isNotEmpty) {
      chooseSport(state.sports.first);
    }
  }

  void chooseSpace(String id) {
    if (state.locked) return;
    if (state.draft.spaceId == id && state.option != null) return;
    final p = state.business?.spaces.where((s) => s.id == id).firstOrNull;
    if (p == null) return;
    _edit(
      state.draft.copyWith(
        spaceId: id,
        sport:
            state.draft.sport ??
            (state.sports.length == 1 ? state.sports.single : null),
        clearOption: true,
      ),
      selection: true,
    );
    final option =
        p.options
            .where(
              (o) => state.draft.sport != null && o.sport == state.draft.sport,
            )
            .firstOrNull ??
        (p.options.length == 1 ? p.options.first : null);
    if (option != null) chooseOption(option.id);
  }

  void chooseSport(String sport) {
    if (state.locked || !state.sports.contains(sport)) return;
    if (state.draft.sport == sport && state.option != null) return;
    final p = state.space?.options.any((o) => o.sport == sport) == true
        ? state.space
        : state.business?.spaces
              .where((p) => p.options.any((o) => o.sport == sport))
              .firstOrNull;
    if (p == null) return;
    _edit(
      state.draft.copyWith(sport: sport, clearOption: true),
      selection: true,
    );
    chooseSpace(p.id);
  }

  void chooseOption(String id) {
    if (state.locked || state.draft.optionId == id) return;
    final o = state.space?.options.where((o) => o.id == id).firstOrNull;
    if (o == null) return;
    _edit(
      state.draft.copyWith(
        optionId: id,
        sport: o.sport,
        duration: o.defaultDuration,
        time: o.fixedTime ?? state.draft.time,
        people: o.groupMode == 'exact' || o.groupMode == 'at_least'
            ? '${o.groupPeople}'
            : state.draft.people,
      ),
      selection: true,
    );
  }

  void date(String v) {
    if (v == state.draft.date) return;
    _edit(state.draft.copyWith(date: v), selection: true);
  }

  void time(String v) {
    if (state.locked) return;
    if (state.option?.minimumDuration != null) {
      final preloaded = state.slots
          .where(
            (slot) =>
                slot.time == v &&
                (slot.date == null || slot.date == state.draft.date),
          )
          .firstOrNull
          ?.endOptions;
      _edit(
        state.draft.copyWith(time: v, duration: state.option!.minimumDuration!),
        selection: true,
        refreshSlots: false,
      );
      emit(
        state.copyWith(
          choosingEnd: true,
          rangeComplete: false,
          endSlots: preloaded ?? [],
        ),
      );
      slotGeneration++;
      availabilityTimer?.cancel();
      emit(state.copyWith(slotsLoading: false));
      if (preloaded == null) unawaited(slots());
      return;
    }
    _edit(state.draft.copyWith(time: v), selection: true, refreshSlots: false);
    scheduleQuote();
  }

  void chooseSlot(BookingSlot slot) {
    if (state.locked) return;
    if (state.option?.minimumDuration == null) {
      if (slot.selectable && state.slots.contains(slot)) time(slot.time);
      return;
    }
    final cell = state.timeCells.where((c) => c.slot == slot).firstOrNull;
    if (cell == null || !cell.enabled) return;
    if (cell.start) {
      chooseStartAgain();
      return;
    }
    if (cell.end) {
      clearEnd();
      return;
    }
    if (state.choosingEnd && !state.rangeComplete) {
      if (slot.duration != null) finishDuration(slot.duration!);
    } else {
      time(slot.time);
    }
  }

  void clearEnd() {
    if (state.locked) return;
    generation++;
    quoteTimer?.cancel();
    emit(
      state.copyWith(
        rangeComplete: false,
        clearQuote: true,
        checking: false,
        review: false,
      ),
    );
  }

  void chooseStartAgain() {
    if (state.locked) return;
    generation++;
    quoteTimer?.cancel();
    slotGeneration++;
    availabilityTimer?.cancel();
    emit(
      state.copyWith(
        choosingEnd: false,
        rangeComplete: false,
        draft: state.draft.copyWith(
          duration: state.option?.minimumDuration ?? state.draft.duration,
        ),
        clearQuote: true,
        endSlots: [],
        slotsLoading: false,
        checking: false,
        review: false,
        clearSlotsError: true,
      ),
    );
  }

  void duration(int v) =>
      _edit(state.draft.copyWith(duration: v), selection: true);
  void finishDuration(int length) {
    final minimum = state.option?.minimumDuration;
    if (minimum == null ||
        length < minimum ||
        length > 1440 ||
        (length - minimum) % 15 != 0) {
      emit(
        state.copyWith(
          error:
              'Choose at least $minimum minutes, then extend in 15-minute increments.',
          clearQuote: true,
        ),
      );
      return;
    }
    _edit(
      state.draft.copyWith(duration: length),
      selection: true,
      refreshSlots: false,
      preserveRange: true,
    );
    emit(state.copyWith(choosingEnd: true, rangeComplete: true));
    scheduleQuote();
  }

  void endTime(String value) {
    if (state.locked || state.option?.minimumDuration == null) return;
    final parts = value.split(':');
    final hour = int.tryParse(parts.first),
        minute = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 24 ||
        minute < 0 ||
        minute > 59 ||
        hour == 24 && minute != 0) {
      return;
    }
    var end = (hour * 60 + minute) % 1440;
    if (end <= state.draft.startMinute) end += 1440;
    finishDuration(end - state.draft.startMinute);
  }

  void people(String v) =>
      _edit(state.draft.copyWith(people: v), selection: true);
  void customerName(String v) {
    _edit(
      state.draft.copyWith(
        customer: state.draft.customer.copyWith(name: v, clearId: true),
      ),
    );
    _scheduleCustomers();
  }

  void customerPhone(String v) {
    _edit(
      state.draft.copyWith(
        customer: state.draft.customer.copyWith(phone: v, clearId: true),
      ),
    );
    _scheduleCustomers();
  }

  void _scheduleCustomers() {
    customerTimer?.cancel();
    searchGeneration++;
    if (isClosed || state.locked) return;
    final digits = _phoneDigits(state.draft.customer.phone);
    if (state.draft.customer.name.trim().isNotEmpty || digits.length < 3) {
      emit(state.copyWith(customers: [], searching: false));
      return;
    }
    // A narrower query can reuse known matching records immediately. Always
    // refresh because a previous bounded response may not contain every match.
    final known = <String, BookingCustomer>{};
    for (final matches in _customerMatches.values) {
      for (final customer in matches) {
        if (_phoneDigits(customer.phone).contains(digits)) {
          known[customer.id ?? '${customer.name}/${customer.phone}'] = customer;
        }
      }
    }
    emit(state.copyWith(customers: known.values.take(40), searching: false));
    customerTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(searchCustomers()),
    );
  }

  void customerEmail(String v) => _edit(
    state.draft.copyWith(customer: state.draft.customer.copyWith(email: v)),
  );
  void notes(String v) => _edit(state.draft.copyWith(notes: v));
  void reason(String v) => _edit(state.draft.copyWith(reason: v));
  void chooseCustomer(BookingCustomer c) {
    customerTimer?.cancel();
    searchGeneration++;
    _edit(state.draft.copyWith(customer: c));
    emit(state.copyWith(customers: [], searching: false));
  }

  void section(int n) {
    if (!state.locked) emit(state.copyWith(activeSection: n));
  }

  void discount(BookingDiscount? value) {
    if (state.locked || state.original != null) return;
    generation++;
    quoteTimer?.cancel();
    emit(
      state.copyWith(
        draft: state.draft.copyWith(
          discount: value,
          clearDiscount: value == null,
        ),
        clearQuote: true,
        checking: false,
        review: false,
      ),
    );
    if (value == null || value.validate(state.estimatedSubtotal) == null) {
      scheduleQuote();
    }
  }

  void addPayment([String method = 'cash']) {
    if (state.locked ||
        !state.catalog.canCollect ||
        state.original != null ||
        state.draft.payments.length >= 20) {
      return;
    }
    _edit(
      state.draft.copyWith(
        payments: [
          ...state.draft.payments,
          BookingPaymentDraft(
            method: method,
            amount:
                state.remainingPayment == null || state.remainingPayment == 0
                ? ''
                : (state.remainingPayment! / 100).toStringAsFixed(2),
          ),
        ],
      ),
    );
  }

  void updatePayment(
    String id,
    BookingPaymentDraft Function(BookingPaymentDraft) update,
  ) {
    if (state.locked || !state.catalog.canCollect || state.original != null) {
      return;
    }
    final rows = state.draft.editablePayments;
    _edit(
      state.draft.copyWith(
        payments: rows.map((p) => p.id == id ? update(p) : p),
      ),
    );
  }

  void payBalance(String id) {
    final balance = state.paymentBalance(id);
    if (balance == null || balance <= 0) return;
    updatePayment(
      id,
      (p) => p.copyWith(amount: (balance / 100).toStringAsFixed(2)),
    );
  }

  void removePayment(String id) => _edit(
    state.draft.copyWith(
      payments: state.draft.payments.where((p) => p.id != id),
    ),
  );
  Future<void> searchCustomers() async {
    if (state.locked || state.draft.customer.name.trim().isNotEmpty) return;
    final phone = state.draft.customer.phone;
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 3) return;
    final token = ++searchGeneration, capturedScope = scope;
    emit(state.copyWith(searching: true));
    bool current() =>
        !isClosed &&
        token == searchGeneration &&
        scope == capturedScope &&
        state.draft.customer.phone == phone &&
        state.draft.customer.name.trim().isEmpty;
    try {
      final list = await repository.customers(phone);
      if (current()) {
        _customerMatches[_phoneDigits(phone)] = list;
        while (_customerMatches.length > 12) {
          _customerMatches.remove(_customerMatches.keys.first);
        }
        emit(state.copyWith(customers: list, searching: false));
      }
    } catch (_) {
      // Optional suggestions must never prevent manually entering a customer.
      if (current()) emit(state.copyWith(searching: false));
    }
  }

  Future<void> slots() async {
    availabilityTimer?.cancel();
    if (state.locked || state.slotsLoading) return;
    final selection = state.draft.selection;
    if (selection == null) return;
    final token = ++slotGeneration, key = availabilityKey(state.draft);
    emit(
      state.copyWith(
        slotsLoading: true,
        clearSlotsError: true,
        error: state.error,
      ),
    );
    try {
      final result = await repository.availability(
        !state.choosingEnd && state.option?.minimumDuration != null
            ? state.draft
                  .copyWith(duration: state.option!.minimumDuration!)
                  .selection!
            : selection,
        excludeId: state.original?.id,
        endTimes: state.choosingEnd,
      );
      if (!isClosed &&
          token == slotGeneration &&
          key == availabilityKey(state.draft)) {
        emit(
          state.copyWith(
            slots: state.choosingEnd ? null : result,
            endSlots: state.choosingEnd ? result : [],
            slotsLoading: false,
            slotsLoaded: true,
            clearSlotsError: true,
            error: state.error,
          ),
        );
      }
    } catch (e) {
      if (!isClosed &&
          token == slotGeneration &&
          key == availabilityKey(state.draft)) {
        emit(
          state.copyWith(
            slots: state.choosingEnd ? null : [],
            endSlots: [],
            slotsLoading: false,
            slotsLoaded: state.choosingEnd ? state.slotsLoaded : false,
            slotsError: bookingError(e),
            error: state.error,
          ),
        );
      }
    }
  }

  Future<void> checkQuote() async {
    quoteTimer?.cancel();
    if (state.locked || state.checking) return;
    if (state.option?.minimumDuration != null && !state.rangeComplete) {
      emit(
        state.copyWith(
          clearQuote: true,
          error: 'Choose a start time, then a finish time.',
        ),
      );
      return;
    }
    final s = state.draft.selection;
    if (s == null) {
      emit(
        state.copyWith(
          error: 'Complete the space, date, time and participant count.',
        ),
      );
      return;
    }
    final discountError = state.draft.discount?.validate(
      state.estimatedSubtotal,
    );
    if (discountError != null) {
      emit(state.copyWith(error: discountError, clearQuote: true));
      return;
    }
    final option = state.option;
    if (option?.minimumDuration != null &&
        (s.duration < option!.minimumDuration! ||
            (s.duration - option.minimumDuration!) % 15 != 0 ||
            s.duration > 1440)) {
      emit(
        state.copyWith(
          clearQuote: true,
          error: 'Choose a valid end time after the minimum booking duration.',
        ),
      );
      return;
    }
    if (option != null && !option.acceptsPeople(s.people)) {
      emit(state.copyWith(clearQuote: true, error: option.groupExplanation));
      return;
    }
    final g = generation;
    emit(state.copyWith(checking: true, clearQuote: true));
    try {
      final q = await repository.quote(s, excludeId: state.original?.id);
      if (valid(g)) emit(state.copyWith(quote: q, checking: false));
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(checking: false, error: bookingError(e)));
      }
    }
  }

  Future<void> review() async {
    if (state.locked) return;
    if (state.draft.selection == null ||
        (state.option?.minimumDuration != null && !state.rangeComplete)) {
      return;
    }
    final discountError = state.draft.discount?.validate(
      state.estimatedSubtotal,
    );
    if (discountError != null) {
      emit(state.copyWith(error: discountError));
      return;
    }
    final error = state.original == null
        ? state.draft.customer.validate()
        : state.draft.reason.trim().length < 2
        ? 'Enter a reschedule reason.'
        : null;
    if (error != null) {
      emit(state.copyWith(error: error));
      return;
    }
    for (final p in state.draft.recordedPayments) {
      if (p.validate() != null) {
        emit(state.copyWith(error: p.validate()));
        return;
      }
    }
    // Without a loaded tariff, paid bookings must wait for a known total.
    if (state.original == null &&
        state.draft.received > 0 &&
        state.displayedTotal == null) {
      await checkQuote();
      if (isClosed || state.quote == null) return;
    }
    if (state.original == null &&
        state.displayedTotal != null &&
        state.draft.received > state.displayedTotal!) {
      emit(state.copyWith(error: 'Split payments exceed the booking total.'));
      return;
    }
    emit(state.copyWith(review: true));
    if (state.quote == null && !state.checking) unawaited(checkQuote());
  }

  void editReview() {
    if (!state.locked) emit(state.copyWith(review: false));
  }

  Future<void> confirm() async {
    if (state.saving) return;
    if (state.pending != null) {
      await _send(state.pending!);
      return;
    }
    if (!state.review || state.quote == null) return;
    if (state.original == null && state.draft.received > state.quote!.total) {
      emit(state.copyWith(error: 'Split payments exceed the booking total.'));
      return;
    }
    final original = state.original, key = const Uuid().v4();
    final command = BookingCommand(
      key,
      original == null ? '/bookings' : '/bookings/${original.id}/reschedule',
      original == null
          ? {
              'selection': state.draft.selection!.toJson(),
              'quote_token': state.quote!.token,
              'customer': state.draft.customer.toJson(),
              'notes': state.draft.notes,
              'payments': state.draft.recordedPayments
                  .map((p) => p.toJson())
                  .toList(),
            }
          : {
              'version': original.version,
              'selection': state.draft.selection!.toJson(),
              'quote_token': state.quote!.token,
              'reason': state.draft.reason.trim(),
            },
    );
    await _send(command);
  }

  Future<void> _send(BookingCommand command) async {
    final g = generation;
    availabilityTimer?.cancel();
    quoteTimer?.cancel();
    slotGeneration++;
    emit(state.copyWith(saving: true, slotsLoading: false, pending: command));
    try {
      final id = await repository.submit(command);
      if (valid(g)) {
        emit(state.copyWith(saving: false, resultId: id, clearPending: true));
      }
    } catch (e) {
      if (!valid(g)) return;
      if (e is AppException && e.code == 'NETWORK') {
        try {
          final id = await repository.commandResult(command.key);
          if (valid(g) && id != null) {
            emit(
              state.copyWith(saving: false, resultId: id, clearPending: true),
            );
            return;
          }
        } catch (_) {}
        if (valid(g)) {
          emit(
            state.copyWith(
              saving: false,
              error:
                  'Confirmation could not be verified. Retry confirmation; your request will not be duplicated.',
            ),
          );
        }
      } else {
        emit(
          state.copyWith(
            saving: false,
            clearPending: true,
            review: false,
            clearQuote: true,
            error: bookingError(e),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    generation++;
    slotGeneration++;
    availabilityTimer?.cancel();
    quoteTimer?.cancel();
    customerTimer?.cancel();
    await subscription.cancel();
    return super.close();
  }
}
