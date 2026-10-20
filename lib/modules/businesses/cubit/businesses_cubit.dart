import '../../../core/state/workspace_screen_cubit.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/business_repository.dart';
import '../models/business_draft.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/cubit/workspace_state.dart';
import '../models/businesses_screen_model.dart';

class BusinessesCubit extends WorkspaceScreenCubit<BusinessesScreenModel> {
  BusinessesCubit(WorkspaceSession session, this.repository)
    : super(session, BusinessesScreenModel.fromSnapshot) {
    final organization = state.data.organization?.name ?? '';
    emit(
      state.copyWith(
        names: {
          for (final type in BusinessType.values)
            type: organization.isEmpty
                ? type.label
                : '$organization ${type.label}',
        },
      ),
    );
  }
  final BusinessRepository repository;
  @override
  BusinessesScreenModel mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot);
  void toggleService(BusinessType type) {
    if (state.disabled) return;
    final selected = {...state.selected};
    selected.contains(type) ? selected.remove(type) : selected.add(type);
    emit(state.copyWith(selected: selected));
  }

  void nameService(BusinessType type, String name) {
    if (state.disabled) return;
    emit(state.copyWith(names: {...state.names, type: name}));
  }

  /// Save each selection once. Successful items leave the selection immediately;
  /// failed and unconfirmed items remain for review, without retrying writes.
  Future<bool> addSelected() async {
    if (state.disabled ||
        state.selected.isEmpty ||
        !state.data.isOwner ||
        state.data.locations.isEmpty) {
      return false;
    }
    final drafts = BusinessType.values
        .where(state.selected.contains)
        .map(
          (type) => BusinessDraft(
            name: (state.names[type] ?? '').trim(),
            type: type,
            locationId: state.data.locations.first['id'] as String,
          ),
        )
        .toList();
    if (drafts.any((draft) => Validation.name(draft.name) != null)) {
      return false;
    }
    emit(state.copyWith(adding: true));
    try {
      for (final draft in drafts) {
        if (isClosed) return false;
        final existingIds = session.state.data.businesses
            .map((b) => b.id)
            .toSet();
        final ok = await save(() => repository.add(draft));
        if (isClosed) return false;
        final confirmed =
            ok ||
            session.state.data.businesses.any(
              (b) =>
                  !existingIds.contains(b.id) &&
                  b.name == draft.name &&
                  b.type == draft.type &&
                  b.locationId == draft.locationId,
            );
        if (!confirmed) return false;
        // Use the refreshed snapshot directly; stream delivery may still be queued.
        emit(
          state.copyWith(
            snapshot: session.state,
            selected: {...state.selected}..remove(draft.type),
          ),
        );
        if (!ok) return false;
      }
      return true;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(snapshot: session.state, adding: false));
      }
    }
  }
}
