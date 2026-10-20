import 'package:equatable/equatable.dart';

class BusinessDetailField extends Equatable {
  const BusinessDetailField(this.label, this.value);
  final String label, value;
  @override
  List<Object?> get props => [label, value];
}

class BusinessPriceGroup extends Equatable {
  BusinessPriceGroup(this.schedule, Iterable<BusinessDetailField> rates)
    : rates = List.unmodifiable(rates);
  final String schedule;
  final List<BusinessDetailField> rates;
  @override
  List<Object?> get props => [schedule, rates];
}

class BusinessDetailEntry extends Equatable {
  BusinessDetailEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    this.enabled,
    Iterable<BusinessDetailField> fields = const [],
    Iterable<BusinessPriceGroup> prices = const [],
  }) : fields = List.unmodifiable(fields),
       prices = List.unmodifiable(prices);
  final String id, name, subtitle;
  final bool? enabled;
  final List<BusinessDetailField> fields;
  final List<BusinessPriceGroup> prices;
  @override
  List<Object?> get props => [id, name, subtitle, enabled, fields, prices];
}

class BusinessDetailSection extends Equatable {
  BusinessDetailSection(this.title, Iterable<BusinessDetailEntry> entries)
    : entries = List.unmodifiable(entries);
  final String title;
  final List<BusinessDetailEntry> entries;
  @override
  List<Object?> get props => [title, entries];
}

class BusinessDetailSummary extends Equatable {
  BusinessDetailSummary({
    required this.spaceCount,
    this.enabledCount,
    Iterable<BusinessDetailSection> sections = const [],
    this.notice,
  }) : sections = List.unmodifiable(sections);
  final int spaceCount;
  final int? enabledCount;
  final String? notice;
  final List<BusinessDetailSection> sections;
  @override
  List<Object?> get props => [spaceCount, enabledCount, sections, notice];
}
