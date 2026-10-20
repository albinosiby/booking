import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import 'dart:typed_data';
import '../repositories/organization_repository.dart';
import '../models/organization_draft.dart';
import '../../workspace/cubit/workspace_state.dart';
import '../models/organization_screen_model.dart';

class OrganizationCubit extends WorkspaceScreenCubit<OrganizationScreenModel> {
  OrganizationCubit(WorkspaceSession session, this.repository)
    : super(session, OrganizationScreenModel.fromSnapshot);
  final OrganizationRepository repository;
  @override
  OrganizationScreenModel mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot);
  void selectState(String? code) =>
      emit(state.copyWith(stateCode: code, clearState: code == null));
  void selectTimezone(String value) => emit(state.copyWith(timezone: value));
  void selectCurrency(String value) => emit(state.copyWith(currency: value));
  void selectLogo(Uint8List bytes, String type) => emit(
    state.copyWith(
      logo: Uint8List.fromList(bytes).asUnmodifiableView(),
      logoType: type,
    ),
  );
  Future<bool> create(OrganizationDraft draft) =>
      save(() => repository.create(draft));
  Future<bool> uploadLogo(Uint8List bytes, String contentType) =>
      save(() => repository.uploadLogo(bytes, contentType));
}
