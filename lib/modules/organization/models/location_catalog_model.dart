import 'package:equatable/equatable.dart';
import '../../workspace/models/workspace.dart';

class LocationCatalogState extends Equatable {
  const LocationCatalogState({
    this.countries = const [],
    this.states = const [],
    this.timezones = const [],
    this.busy = true,
    this.error,
    this.country = 'IN',
  });
  final List<CatalogOption> countries, states;
  final List<String> timezones;
  final bool busy;
  final String? error;
  final String country;
  @override
  List<Object?> get props => [
    countries,
    states,
    timezones,
    busy,
    error,
    country,
  ];
}
