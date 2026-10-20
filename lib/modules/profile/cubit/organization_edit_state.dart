import 'package:equatable/equatable.dart';
import '../../workspace/models/workspace.dart';
import '../models/organization_edit_model.dart';

class OrganizationEditState extends Equatable {
  OrganizationEditState({
    this.draft,
    this.original,
    this.loading = false,
    this.busy = false,
    this.saved = false,
    this.conflict = false,
    this.error,
    Iterable<CatalogOption> countries = const [],
    Map<String, List<CatalogOption>> states = const {},
    Iterable<String> loadingCountries = const [],
    Iterable<String> failedCountries = const [],
    Map<String, String> errors = const {},
  }) : countries = List.unmodifiable(countries),
       states = Map.unmodifiable(
         states.map((k, v) => MapEntry(k, List<CatalogOption>.unmodifiable(v))),
       ),
       loadingCountries = Set.unmodifiable(loadingCountries),
       failedCountries = Set.unmodifiable(failedCountries),
       errors = Map.unmodifiable(errors);
  final OrganizationEditDraft? draft, original;
  final bool loading, busy, saved, conflict;
  final String? error;
  final List<CatalogOption> countries;
  final Map<String, List<CatalogOption>> states;
  final Set<String> loadingCountries, failedCountries;
  final Map<String, String> errors;
  bool get dirty => draft != null && draft != original;
  bool get canSave =>
      dirty &&
      !loading &&
      !busy &&
      !conflict &&
      !saved &&
      draft!.locations.every(
        (l) =>
            states.containsKey(l.countryCode) &&
            !loadingCountries.contains(l.countryCode) &&
            !failedCountries.contains(l.countryCode),
      );
  OrganizationEditState copy({
    OrganizationEditDraft? draft,
    OrganizationEditDraft? original,
    bool? loading,
    bool? busy,
    bool? saved,
    bool? conflict,
    String? error,
    List<CatalogOption>? countries,
    Map<String, List<CatalogOption>>? states,
    Iterable<String>? loadingCountries,
    Iterable<String>? failedCountries,
    Map<String, String>? errors,
  }) => OrganizationEditState(
    draft: draft ?? this.draft,
    original: original ?? this.original,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    saved: saved ?? this.saved,
    conflict: conflict ?? this.conflict,
    error: error,
    countries: countries ?? this.countries,
    states: states ?? this.states,
    loadingCountries: loadingCountries ?? this.loadingCountries,
    failedCountries: failedCountries ?? this.failedCountries,
    errors: errors ?? this.errors,
  );
  @override
  List<Object?> get props => [
    draft,
    original,
    loading,
    busy,
    saved,
    conflict,
    error,
    countries,
    states,
    loadingCountries,
    failedCountries,
    errors,
  ];
}
