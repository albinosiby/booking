import 'hall_configuration.dart';

enum HallSection { overview, halls, pricing, review }

class HallOverviewModel {
  const HallOverviewModel(this.configuration, this.ready);
  final HallConfiguration configuration;
  final bool ready;
}

class HallResourcesModel {
  const HallResourcesModel(this.halls, this.selected);
  final List<HallResource> halls;
  final HallResource? selected;
}

class HallPricingModel {
  const HallPricingModel(
    this.halls,
    this.selected,
    this.currency,
    this.selectedOption,
  );
  final List<HallResource> halls;
  final HallResource? selected;
  final String currency;
  final String? selectedOption;
}

class HallReviewModel {
  const HallReviewModel(this.configuration, this.currency);
  final HallConfiguration configuration;
  final String currency;
}
