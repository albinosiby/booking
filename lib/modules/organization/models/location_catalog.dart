import '../../workspace/models/workspace.dart';

class LocationCatalog {
  LocationCatalog({
    required Iterable<CatalogOption> countries,
    required Iterable<String> timezones,
  }) : countries = List.unmodifiable(countries),
       timezones = List.unmodifiable(timezones);
  final List<CatalogOption> countries;
  final List<String> timezones;
  factory LocationCatalog.fromJson(Map<String, dynamic> json) =>
      LocationCatalog(
        countries: (json['countries'] as List).map(
          (item) => CatalogOption.fromJson(Map<String, dynamic>.from(item)),
        ),
        timezones: List<String>.from(json['timezones']),
      );
}
