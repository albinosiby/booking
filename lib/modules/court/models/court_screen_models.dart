import 'court_configuration.dart';

enum CourtSection { overview, courts, pricing, coaching, review }

class CourtOverviewModel {
  const CourtOverviewModel(this.configuration, this.ready);
  final CourtConfiguration configuration;
  final bool ready;
}

class CourtResourcesModel {
  const CourtResourcesModel(this.courts, this.selected);
  final List<CourtResource> courts;
  final CourtResource? selected;
  bool needsSetup(CourtResource resource) =>
      CourtConfiguration(
        courts: [resource],
      ).validate(complete: resource.enabled) !=
      null;
  String setupStatus(CourtResource resource) => !resource.enabled
      ? 'Disabled'
      : needsSetup(resource)
      ? 'Needs setup'
      : 'Configured';
}

class CourtPricingModel {
  const CourtPricingModel(this.courts, this.selected, this.currency);
  final List<CourtResource> courts;
  final CourtResource? selected;
  final String currency;
}

class CourtCoachingModel {
  const CourtCoachingModel(
    this.courts,
    this.plans,
    this.selected,
    this.currency,
  );
  final List<CourtResource> courts;
  final List<CourtPlan> plans;
  final CourtPlan? selected;
  final String currency;
}

class CourtReviewModel {
  const CourtReviewModel(this.configuration, this.currency);
  final CourtConfiguration configuration;
  final String currency;
}
