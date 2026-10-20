import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/helpers/validation.dart';
import '../../bookings/repositories/booking_repository.dart';
import '../../bookings/models/booking_models.dart' show bookingDate;
import '../../bookings/cubit/booking_form_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/cubit/workspace_state.dart' show LoadStatus;
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';
import '../repositories/accounts_repository.dart';
import '../../workspace/repositories/refreshable_reads.dart';

String financeError(Object e) => e is AppException
    ? e.message
    : 'Could not complete this action. Please try again.';

abstract class FinanceCubit<S> extends Cubit<S> {
  FinanceCubit(this.session, super.initialState) {
    accessScope = bookingScope(session);
    access = session.snapshots.listen((_) {
      if (bookingScope(session) != accessScope) {
        epoch++;
        onAccessChanged();
        if (followsAccessChanges &&
            session.state.status == LoadStatus.ready &&
            session.state.data.organization != null) {
          accessScope = bookingScope(session);
          onAccessRestored();
        }
      }
    });
  }
  final WorkspaceSession session;
  late final StreamSubscription access;
  late String accessScope;
  bool get followsAccessChanges => false;
  void onAccessRestored() {}
  int epoch = 0;
  bool get authorized => bookingScope(session) == accessScope;
  bool current(int g) => !isClosed && g == epoch && authorized;
  void onAccessChanged();
  @override
  Future<void> close() {
    epoch++;
    access.cancel();
    return super.close();
  }
}

class AccountsOverviewCubit extends FinanceCubit<AccountsOverviewModel> {
  @override
  bool get followsAccessChanges => true;
  @override
  void onAccessRestored() {
    load(filter: FinanceFilter.month(DateTime.now()));
  }

  AccountsOverviewCubit(
    WorkspaceSession session,
    this.repository,
    BookingRepository bookings,
  ) : super(
        session,
        AccountsOverviewModel(filter: FinanceFilter.month(DateTime.now())),
      ) {
    changes = repository.changes.listen((_) => load());
    bookingChanges = bookings.changes.listen((_) => load());
  }
  final AccountsRepository repository;
  late final StreamSubscription changes, bookingChanges;
  @override
  void onAccessChanged() => emit(
    AccountsOverviewModel(
      filter: state.filter,
      error: 'Your access changed. Reopen Accounts.',
    ),
  );
  Future<void> refresh() async {
    await session.load();
    final source = repository;
    if (source is RefreshableReads) {
      (source as RefreshableReads).invalidateReads();
    }
    return load();
  }

  Future<void> load({FinanceFilter? filter}) async {
    if (!authorized) return;
    final g = ++epoch, f = filter ?? state.filter;
    final old = state;
    final retain = f == old.filter;
    emit(
      AccountsOverviewModel(
        filter: f,
        catalog: old.catalog,
        overview: retain ? old.overview : null,
        transactions: retain ? old.transactions : const [],
        loading: true,
      ),
    );
    try {
      final catalog = await repository.catalog();
      var selected = f;
      if (state.catalog == null && filter == null) {
        selected = FinanceFilter.month(DateTime.parse(catalog.today));
      }
      if (!current(g)) return;
      if (!catalog.canView) {
        emit(AccountsOverviewModel(filter: selected, catalog: catalog));
        return;
      }
      final results = await Future.wait([
        repository.overview(selected),
        repository.transactions(selected),
      ]);
      if (current(g)) {
        emit(
          AccountsOverviewModel(
            filter: selected,
            catalog: catalog,
            overview: results[0] as FinanceOverview,
            transactions: (results[1] as FinanceTransactionPage).items
                .take(6)
                .toList(growable: false),
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(
          AccountsOverviewModel(
            filter: f,
            catalog: accessFailure(e) ? null : state.catalog,
            overview: accessFailure(e) ? null : state.overview,
            transactions: accessFailure(e) ? const [] : state.transactions,
            error: financeError(e),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    changes.cancel();
    bookingChanges.cancel();
    return super.close();
  }
}

class AccountSettingsCubit extends FinanceCubit<AccountSettingsModel> {
  @override
  bool get followsAccessChanges => true;
  @override
  void onAccessRestored() {
    load();
  }

  AccountSettingsCubit(WorkspaceSession session, this.repository)
    : super(session, const AccountSettingsModel()) {
    changes = repository.changes.listen((_) {
      if (!state.busy) load();
    });
  }
  late final StreamSubscription changes;
  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
  }

  final AccountsRepository repository;
  @override
  void onAccessChanged() => emit(
    const AccountSettingsModel(
      error: 'Your access changed. Reopen account settings.',
    ),
  );
  Future<void> load() async {
    if (!authorized) return;
    final g = ++epoch;
    emit(AccountSettingsModel(catalog: state.catalog, loading: true));
    try {
      final c = await repository.catalog();
      if (current(g)) emit(AccountSettingsModel(catalog: c));
    } catch (e) {
      if (current(g)) {
        emit(
          AccountSettingsModel(
            catalog: accessFailure(e) ? null : state.catalog,
            error: financeError(e),
          ),
        );
      }
    }
  }

  Future<void> change(Future<void> Function() work) async {
    if (state.busy || !authorized) return;
    final g = ++epoch;
    emit(AccountSettingsModel(catalog: state.catalog, busy: true));
    try {
      await work();
      if (current(g)) await load();
    } catch (e) {
      if (current(g)) {
        emit(
          AccountSettingsModel(catalog: state.catalog, error: financeError(e)),
        );
      }
    }
  }

  Future<void> rename(String id, String name) =>
      change(() => repository.updateBank(id, {'name': name.trim()}));
  Future<void> primary(String id) =>
      change(() => repository.updateBank(id, {'is_primary': true}));
  Future<void> archive(String id) =>
      change(() => repository.updateBank(id, {'archive': true}));
  Future<void> route(
    String business,
    String? space,
    String method,
    String? account,
  ) => change(
    () => repository.route({
      'business_id': business,
      'resource_id': space,
      'method': method,
      'account_id': account,
    }),
  );
}

class BankAccountCubit extends FinanceCubit<BankAccountModel> {
  BankAccountCubit(
    WorkspaceSession session,
    this.repository, {
    this.cash = false,
  }) : super(
         session,
         BankAccountModel(
           date: DateTime.now(),
           name: cash ? 'Cash in hand' : '',
         ),
       );
  final bool cash;
  final AccountsRepository repository;
  final key = const Uuid().v4();
  Map<String, Object?>? pending;
  @override
  void onAccessChanged() => emit(
    BankAccountModel(
      date: DateTime.now(),
      error: 'Your access changed. Reopen this form.',
    ),
  );
  void update({
    String? name,
    String? bank,
    String? accountNumber,
    String? opening,
    DateTime? date,
    bool? primary,
  }) {
    if (!state.busy && pending == null) {
      emit(
        state.copyWith(
          name: name,
          bank: bank,
          accountNumber: accountNumber,
          opening: opening,
          date: date,
          primary: primary,
        ),
      );
    }
  }

  Future<void> save() async {
    if (state.busy || !authorized) return;
    final value = state.opening.trim();
    final negative = value.startsWith('-'),
        minor = financeOpeningMinor(negative ? value.substring(1) : value);
    if (state.name.trim().length < 2 ||
        minor == null ||
        (!cash &&
            !RegExp(r'^[0-9]{6,34}$').hasMatch(state.accountNumber.trim()))) {
      emit(
        state.copyWith(
          error:
              'Enter an account name, valid opening balance and a full account number (6–34 digits).',
        ),
      );
      return;
    }
    pending ??= {
      'command_key': key,
      'name': state.name.trim(),
      'bank_name': state.bank.trim(),
      'account_number': state.accountNumber.trim(),
      'opening_minor': minor * (negative ? -1 : 1),
      'opening_at': state.date.toUtc().toIso8601String(),
      'is_primary': state.primary,
    };
    final g = ++epoch;
    emit(state.copyWith(busy: true));
    try {
      if (cash) {
        await repository.cashOpening({
          for (final k in ['command_key', 'opening_minor', 'opening_at'])
            k: pending![k],
        });
      } else {
        await repository.createBank(pending!);
      }
      if (current(g)) emit(state.copyWith(busy: false, saved: true));
    } catch (e) {
      if (current(g)) {
        if (e is AppException &&
            ['VALIDATION_ERROR', 'REQUEST_ERROR'].contains(e.code)) {
          pending = null;
        }
        emit(
          state.copyWith(
            busy: false,
            error: '${financeError(e)} Retry saves the same account.',
          ),
        );
      }
    }
  }
}

class FinanceEntryCubit extends FinanceCubit<FinanceEntryModel> {
  FinanceEntryCubit(WorkspaceSession session, this.repository, String kind)
    : super(session, FinanceEntryModel(kind: kind, date: DateTime.now()));
  final AccountsRepository repository;
  final key = const Uuid().v4();
  Map<String, Object?>? pending;
  @override
  void onAccessChanged() => emit(
    FinanceEntryModel(
      kind: state.kind,
      date: DateTime.now(),
      error: 'Your access changed. Reopen this form.',
    ),
  );
  Future<void> load() async {
    if (!authorized) return;
    final g = ++epoch;
    emit(state.copyWith(loading: true));
    try {
      final c = await repository.catalog();
      if (current(g)) {
        emit(
          state.copyWith(
            catalog: c,
            loading: false,
            lines: [
              FinanceDraftLine(
                id: const Uuid().v4(),
                accountId: c.destination('cash', null, null),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(state.copyWith(loading: false, error: financeError(e)));
      }
    }
  }

  bool get editable => !state.busy && pending == null && authorized;
  void fields({
    String? reason,
    String? category,
    String? reference,
    DateTime? date,
    String? toAccountId,
  }) {
    if (editable) {
      emit(
        state.copyWith(
          reason: reason,
          category: category,
          reference: reference,
          date: date,
          toAccountId: toAccountId,
        ),
      );
    }
  }

  void scope(String? business, String? space) {
    if (editable) {
      emit(
        state.copyWith(
          businessId: business,
          spaceId: space,
          clearScope: true,
          lines: state.lines
              .map(
                (l) => l.copyWith(
                  accountId: state.catalog?.destination(
                    l.method,
                    business,
                    space,
                  ),
                  clearAccount:
                      state.catalog?.destination(l.method, business, space) ==
                      null,
                ),
              )
              .toList(),
        ),
      );
    }
  }

  void line(int index, FinanceDraftLine value) {
    if (editable) {
      final l = [...state.lines];
      l[index] = value.id.isEmpty ? value.copyWith(id: l[index].id) : value;
      emit(state.copyWith(lines: l));
    }
  }

  void method(int i, String method) => line(
    i,
    state.lines[i].copyWith(
      method: method,
      accountId: state.catalog?.destination(
        method,
        state.businessId,
        state.spaceId,
      ),
      clearAccount:
          state.catalog?.destination(method, state.businessId, state.spaceId) ==
          null,
    ),
  );
  void add() {
    if (editable && state.lines.length < 20) {
      emit(
        state.copyWith(
          lines: [
            ...state.lines,
            FinanceDraftLine(
              id: const Uuid().v4(),
              accountId: state.catalog?.destination('cash', null, null),
            ),
          ],
        ),
      );
    }
  }

  void remove(int i) {
    if (editable && state.lines.length > 1) {
      emit(state.copyWith(lines: [...state.lines]..removeAt(i)));
    }
  }

  int get total =>
      state.lines.fold(0, (n, l) => n + (Validation.priceMinor(l.amount) ?? 0));
  Future<void> save() async {
    if (state.busy || !authorized || state.catalog == null) return;
    if (state.reason.trim().length < 2 ||
        state.category.trim().length < 2 ||
        state.lines.any(
          (l) =>
              l.accountId == null ||
              (Validation.priceMinor(l.amount) ?? 0) <= 0,
        )) {
      emit(
        state.copyWith(
          error:
              'Enter a reason, category, positive amount and an account for each payment.',
        ),
      );
      return;
    }
    if (state.kind == 'transfer' &&
        (state.toAccountId == null ||
            state.toAccountId == state.lines.first.accountId)) {
      emit(state.copyWith(error: 'Choose two different accounts.'));
      return;
    }
    pending ??= {
      'command_key': key,
      'kind': state.kind,
      'business_id': state.kind == 'transfer' ? null : state.businessId,
      'resource_id': state.kind == 'transfer' ? null : state.spaceId,
      'category': state.category.trim(),
      'reason': state.reason.trim(),
      'reference': state.reference.trim(),
      'occurred_at': state.date.toUtc().toIso8601String(),
      'lines': state.lines
          .map(
            (l) => {
              'account_id': l.accountId,
              'method': state.kind == 'transfer' ? 'transfer' : l.method,
              'amount_minor': Validation.priceMinor(l.amount),
            },
          )
          .toList(),
      if (state.kind == 'transfer') 'to_account_id': state.toAccountId,
    };
    final g = ++epoch;
    emit(state.copyWith(busy: true));
    try {
      await repository.entry(pending!);
      if (current(g)) emit(state.copyWith(busy: false, saved: true));
    } catch (e) {
      if (current(g)) {
        if (e is AppException && e.code != 'NETWORK') pending = null;
        emit(state.copyWith(busy: false, error: financeError(e)));
      }
    }
  }
}

class TransactionsCubit extends FinanceCubit<TransactionsModel> {
  @override
  bool get followsAccessChanges => true;
  @override
  void onAccessRestored() {
    load(filter: FinanceFilter.month(DateTime.now()));
  }

  TransactionsCubit(
    WorkspaceSession session,
    this.repository,
    FinanceFilter filter,
  ) : super(session, TransactionsModel(filter: filter)) {
    changes = repository.changes.listen((_) => load());
  }
  late final StreamSubscription changes;
  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
  }

  Future<void> refresh() async {
    await session.load();
    final source = repository;
    if (source is RefreshableReads) {
      (source as RefreshableReads).invalidateReads();
    }
    return load();
  }

  final AccountsRepository repository;
  @override
  void onAccessChanged() => emit(
    TransactionsModel(
      filter: state.filter,
      error: 'Your access changed. Reopen transactions.',
    ),
  );
  Future<void> load({FinanceFilter? filter, bool more = false}) async {
    if (!authorized || (more && state.loading)) return;
    final g = ++epoch,
        f = filter ?? state.filter,
        old = state.items,
        cursor = more ? state.next : null;
    final retain = f == state.filter;
    if (more && cursor == null) return;
    emit(
      TransactionsModel(
        filter: f,
        items: retain ? old : const [],
        next: retain ? state.next : null,
        loading: true,
      ),
    );
    try {
      final p = await repository.transactions(f, cursor: cursor ?? 0);
      if (current(g)) {
        emit(
          TransactionsModel(
            filter: f,
            items: List.unmodifiable(more ? [...old, ...p.items] : p.items),
            next: p.next,
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(
          TransactionsModel(
            filter: f,
            items: retain && !accessFailure(e) ? old : const [],
            next: retain && !accessFailure(e) ? state.next : null,
            error: financeError(e),
          ),
        );
      }
    }
  }
}

class TransactionDetailsCubit extends FinanceCubit<TransactionDetailsModel> {
  TransactionDetailsCubit(
    WorkspaceSession session,
    this.repository,
    FinanceTransaction entry,
  ) : super(session, TransactionDetailsModel(entry));
  final AccountsRepository repository;
  final key = const Uuid().v4();
  @override
  void onAccessChanged() => emit(
    TransactionDetailsModel(
      state.transaction,
      error: 'Your access changed. Close this page.',
    ),
  );
  Future<void> reverse(String reason) async {
    if (state.busy || state.reversed || !authorized) return;
    final g = ++epoch;
    emit(TransactionDetailsModel(state.transaction, busy: true));
    try {
      await repository.reverse(state.transaction.id, {
        'command_key': key,
        'reason': reason,
      });
      if (current(g)) {
        emit(TransactionDetailsModel(state.transaction, reversed: true));
      }
    } catch (e) {
      if (current(g)) {
        emit(
          TransactionDetailsModel(state.transaction, error: financeError(e)),
        );
      }
    }
  }
}

abstract interface class ReportSaver {
  Future<bool> save(List<int> bytes, String filename);
}

class DeviceReportSaver implements ReportSaver {
  @override
  Future<bool> save(List<int> bytes, String filename) async =>
      await FilePicker.saveFile(
        fileName: filename,
        bytes: Uint8List.fromList(bytes),
        mimeType: filename.endsWith('.pdf')
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        type: FileType.custom,
        allowedExtensions: [filename.split('.').last],
      ) !=
      null;
}

class ReportsCubit extends FinanceCubit<ReportsModel> {
  ReportsCubit(
    WorkspaceSession session,
    this.repository,
    this.saver,
    FinanceFilter filter,
  ) : super(session, ReportsModel(filter: filter));
  final AccountsRepository repository;
  final ReportSaver saver;
  @override
  void onAccessChanged() => emit(
    ReportsModel(
      filter: state.filter,
      error: 'Your access changed. Reopen reports.',
    ),
  );
  DateTime? periodAnchor;
  void selectType(String type) {
    if (state.busy) return;
    final d = periodAnchor ??= DateTime.parse(state.filter.from);
    final filter = type == 'yearly'
        ? state.filter.dates('${d.year}-01-01', '${d.year}-12-31')
        : type == 'monthly'
        ? state.filter.dates(
            bookingDate(DateTime(d.year, d.month)),
            bookingDate(DateTime(d.year, d.month + 1, 0)),
          )
        : state.filter;
    emit(ReportsModel(filter: filter, type: type));
  }

  void configure(FinanceFilter filter, String type) {
    if (!state.busy) {
      periodAnchor = DateTime.parse(filter.from);
      emit(ReportsModel(filter: filter, type: type));
    }
  }

  Future<void> download(String format) async {
    if (state.busy || !authorized) return;
    final g = ++epoch, f = state.filter, type = state.type;
    emit(ReportsModel(filter: f, type: type, busy: true));
    try {
      final bytes = await repository.report(f, type, format);
      if (!current(g)) return;
      final saved = await saver.save(
        bytes,
        'booking-os-$type-${f.from}-${f.until}.$format',
      );
      if (current(g)) {
        emit(
          ReportsModel(
            filter: f,
            type: type,
            message: saved ? 'Report saved.' : 'Download cancelled.',
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(ReportsModel(filter: f, type: type, error: financeError(e)));
      }
    }
  }
}
