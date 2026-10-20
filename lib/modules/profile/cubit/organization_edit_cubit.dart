import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../organization/models/location_catalog.dart';
import '../models/organization_edit_model.dart';
import '../repositories/organization_edit_repository.dart';
import 'organization_edit_state.dart';

class OrganizationEditCubit extends Cubit<OrganizationEditState> {
  OrganizationEditCubit(this.session, this.repository)
    : super(OrganizationEditState()) {
    scope = _scope;
    access = session.snapshots.listen((_) {
      if (scope != _scope) {
        epoch++;
        emit(
          OrganizationEditState(
            error: 'Your workspace access changed. Reopen this page.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final OrganizationEditRepository repository;
  late final StreamSubscription access;
  late final String scope;
  int epoch = 0;
  String get _scope =>
      '${session.state.data.organization?.id}:${session.state.data.membership?['id']}:${session.state.data.membership?['role']}';
  bool get authorized => session.state.data.isOwner && scope == _scope;
  bool current(int g) => !isClosed && authorized && g == epoch;
  String errorText(Object e) => e is AppException
      ? e.message
      : 'Could not save organization details. Please try again.';
  Future<void> load() async {
    if (!authorized) {
      emit(
        OrganizationEditState(
          error: 'Only the owner can edit organization details.',
        ),
      );
      return;
    }
    final g = ++epoch;
    emit(state.copy(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.load(),
        repository.catalog(),
      ]);
      if (!current(g)) return;
      final draft = results[0] as OrganizationEditDraft,
          catalog = results[1] as LocationCatalog;
      final codes = draft.locations.map((l) => l.countryCode).toSet().toList();
      final options = await Future.wait(codes.map(repository.states));
      if (current(g)) {
        emit(
          OrganizationEditState(
            draft: draft,
            original: draft,
            countries: catalog.countries,
            states: {
              for (var i = 0; i < codes.length; i++) codes[i]: options[i],
            },
          ),
        );
      }
    } catch (e) {
      if (current(g)) emit(state.copy(loading: false, error: errorText(e)));
    }
  }

  void fields({String? name, String? phone}) {
    if (!authorized || state.busy || state.loading || state.draft == null) {
      return;
    }
    _draft(state.draft!.copy(name: name, phone: phone));
  }

  void location(int i, OrganizationEditLocation l) {
    if (!authorized || state.busy || state.loading || state.draft == null) {
      return;
    }
    final list = [...state.draft!.locations];
    list[i] = l;
    _draft(state.draft!.copy(locations: list));
  }

  void locationFields(
    int i, {
    String? name,
    String? line1,
    String? line2,
    String? city,
    String? stateCode,
    String? pincode,
  }) {
    if (state.draft == null) return;
    location(
      i,
      state.draft!.locations[i].copy(
        name: name,
        line1: line1,
        line2: line2,
        city: city,
        stateCode: stateCode,
        pincode: pincode,
      ),
    );
  }

  void _draft(OrganizationEditDraft d) => emit(
    state.copy(draft: d, errors: state.errors.isEmpty ? {} : validate(d)),
  );
  Future<void> country(int i, String code) async {
    if (!authorized || state.busy || state.loading || state.draft == null) {
      return;
    }
    if (state.draft!.locations[i].countryCode == code) return;
    location(
      i,
      state.draft!.locations[i].copy(countryCode: code, stateCode: ''),
    );
    if (!state.states.containsKey(code)) await loadStates(code);
  }

  Future<void> loadStates(String code) async {
    if (!authorized || state.loadingCountries.contains(code)) return;
    final g = epoch;
    emit(
      state.copy(
        loadingCountries: {...state.loadingCountries, code},
        failedCountries: {...state.failedCountries}..remove(code),
      ),
    );
    try {
      final options = await repository.states(code);
      if (current(g)) {
        emit(
          state.copy(
            states: {...state.states, code: options},
            loadingCountries: {...state.loadingCountries}..remove(code),
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(
          state.copy(
            loadingCountries: {...state.loadingCountries}..remove(code),
            failedCountries: {...state.failedCountries, code},
            error: state.draft!.locations.any((l) => l.countryCode == code)
                ? 'Could not load states. Retry before saving.'
                : null,
          ),
        );
      }
    }
  }

  Map<String, String> validate(OrganizationEditDraft d) {
    final errors = <String, String>{};
    void length(String key, String v, int min, int max) {
      if (v.trim().length < min) {
        errors[key] = 'Enter at least $min characters';
      } else if (v.trim().length > max) {
        errors[key] = 'Use $max characters or fewer';
      }
    }

    length('name', d.name, 2, 120);
    final phone = d.phone.trim(), digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\+?[\d ()-]+$').hasMatch(phone) ||
        digits.length < 6 ||
        digits.length > 15 ||
        phone.length > 30) {
      errors['phone'] = 'Enter a valid phone number';
    }
    for (final l in d.locations) {
      final p = '${l.id}.';
      length('${p}name', l.name, 2, 120);
      length('${p}line1', l.line1, 2, 200);
      length('${p}line2', l.line2, 0, 200);
      length('${p}city', l.city, 2, 120);
      length('${p}pincode', l.pincode, 1, 20);
      if (!state.countries.any((c) => c.code == l.countryCode)) {
        errors['${p}country'] = 'Choose a country';
      }
      final options = state.states[l.countryCode];
      if (options == null || state.failedCountries.contains(l.countryCode)) {
        errors['${p}state'] = 'Load the states before saving';
      } else if (options.isNotEmpty &&
          !options.any((s) => s.code == l.stateCode)) {
        errors['${p}state'] = 'Choose a state';
      }
      if (l.countryCode == 'IN' &&
          !RegExp(r'^[1-9]\d{5}$').hasMatch(l.pincode.trim())) {
        errors['${p}pincode'] = 'Enter a valid six-digit pincode';
      }
    }
    return errors;
  }

  Future<void> save() async {
    if (!authorized || !state.canSave) return;
    final draft = state.draft!, errors = validate(state.draft!);
    if (errors.isNotEmpty) {
      emit(state.copy(errors: errors));
      return;
    }
    final g = epoch;
    emit(state.copy(busy: true, errors: {}));
    try {
      final saved = await repository.save(draft);
      if (!current(g)) return;
      await session.load();
      if (current(g)) {
        emit(
          state.copy(draft: saved, original: saved, busy: false, saved: true),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(
          state.copy(
            busy: false,
            error: errorText(e),
            conflict: e is AppException && e.code == 'CONFLICT',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    epoch++;
    access.cancel();
    return super.close();
  }
}
