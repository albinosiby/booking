import '../repositories/business_details_mapper.dart';
import '../../../core/state/workspace_screen_cubit.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/business_management_model.dart';
import '../models/business_availability_action.dart';
import '../models/business_removal_action.dart';
import '../repositories/business_repository.dart';

class BusinessManagementCubit
    extends WorkspaceScreenCubit<BusinessManagementModel> {
  BusinessManagementCubit(WorkspaceSession session, this.repository)
    : super(session, BusinessManagementModel.new);
  String? _detailId;
  bool _savingOrder = false;
  BusinessManagementModel _model(WorkspaceState snapshot) =>
      BusinessManagementModel(
        snapshot,
        details: {
          if (snapshot.data.isOwner)
            for (final b in snapshot.data.businesses.where(
              (b) => b.id == _detailId,
            ))
              b.id: describeBusiness(
                b,
                snapshot.data.organization?.currency ?? 'INR',
              ),
        },
      );
  void showDetails(String id) {
    _detailId = id;
    emit(state.copyWith(details: _model(state).details));
  }

  final BusinessRepository repository;
  @override
  BusinessManagementModel mapSnapshot(WorkspaceState snapshot) {
    if (workspaceAccessScope(snapshot.data) !=
        workspaceAccessScope(state.data)) {
      return _model(snapshot);
    }
    return state.copyWith(
      snapshot: snapshot,
      details: _model(snapshot).details,
    );
  }

  void startReorder() {
    if (_savingOrder ||
        state.reordering ||
        !state.data.isOwner ||
        state.busy ||
        state.data.businesses.length < 2) {
      return;
    }
    emit(
      state.copyWith(
        draftOrder: state.data.businesses.map((b) => b.id).toList(),
        orderRevision: state.data.organization!.businessOrderRevision,
      ),
    );
  }

  void reorder(int from, int to) {
    if (_savingOrder ||
        !state.reordering ||
        state.busy ||
        !state.data.isOwner) {
      return;
    }
    final ids = [...state.draftOrder!];
    if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) return;
    ids.insert(to, ids.removeAt(from));
    emit(state.copyWith(draftOrder: ids));
  }

  /// Drag and accessibility actions both enter the same unsaved draft.
  void moveBusiness(int from, int to) {
    if (_savingOrder || state.busy || !state.data.isOwner) return;
    final count = state.businesses.length;
    if (from == to || from < 0 || to < 0 || from >= count || to >= count) {
      return;
    }
    startReorder();
    reorder(from, to);
  }

  void cancelReorder() {
    if (!_savingOrder && !state.busy) emit(state.copyWith(clearDraft: true));
  }

  Future<bool> saveOrder() async {
    if (_savingOrder ||
        !state.reordering ||
        state.busy ||
        !state.data.isOwner) {
      return false;
    }
    final ids = [...state.draftOrder!], revision = state.orderRevision!;
    if (revision != state.data.organization?.businessOrderRevision) {
      emit(
        state.copyWith(
          clearDraft: true,
          message:
              'The business list changed. Review the latest order and reorder again.',
        ),
      );
      return false;
    }
    // Session snapshots arrive asynchronously. Lock synchronously so a second
    // tap cannot end the draft while the first request is still in flight.
    _savingOrder = true;
    try {
      final result = await save(() => repository.reorder(ids, revision));
      if (!isClosed) {
        emit(state.copyWith(snapshot: session.state, clearDraft: true));
      }
      return result;
    } finally {
      _savingOrder = false;
    }
  }

  Future<bool> rename(String id, String name) async {
    if (_savingOrder || !state.data.isOwner || state.busy || state.reordering) {
      return false;
    }
    final error = Validation.name(name.trim());
    if (error != null) {
      emit(state.copyWith(message: error));
      return false;
    }
    return save(() => repository.rename(id, name.trim()));
  }

  bool _changingStatus = false;
  bool _removing = false;
  Future<bool> removeBusiness(BusinessRemovalAction action) async {
    if (_removing ||
        _changingStatus ||
        _savingOrder ||
        state.busy ||
        state.reordering ||
        !state.data.isOwner) {
      return false;
    }
    final business = state.data.businesses
        .where((b) => b.id == action.id)
        .firstOrNull;
    if (business == null || business.version != action.version) {
      emit(
        state.copyWith(
          message:
              'Business changed. Review its latest details before removing it.',
        ),
      );
      return false;
    }
    _removing = true;
    try {
      final saved = await save(
        () => repository.remove(action.id, action.version),
      );
      if (!isClosed) emit(state.copyWith(snapshot: session.state));
      return saved;
    } finally {
      _removing = false;
    }
  }

  Future<bool> setBookingEnabled(BusinessAvailabilityAction action) async {
    if (_changingStatus ||
        _removing ||
        _savingOrder ||
        state.busy ||
        state.reordering ||
        !state.data.isOwner) {
      return false;
    }
    final business = state.data.businesses
        .where((b) => b.id == action.id)
        .firstOrNull;
    final current = business == null
        ? null
        : BusinessAvailabilityAction.forBusiness(business);
    if (current == null ||
        current.version != action.version ||
        current.enabled != action.enabled) {
      emit(
        state.copyWith(
          message: 'Business changed. Review its latest status and try again.',
        ),
      );
      return false;
    }
    _changingStatus = true;
    try {
      return await save(
        () => repository.setBookingEnabled(
          action.id,
          action.enabled,
          action.version,
        ),
      );
    } finally {
      _changingStatus = false;
    }
  }
}
