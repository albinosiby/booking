import 'pool_configuration.dart';

enum PoolSection { overview, pools, pricing, groups, coaching, plans, review }

class PoolOverviewModel {
  const PoolOverviewModel(this.configuration, this.ready);
  final PoolConfiguration configuration;
  final bool ready;
}

class PoolResourcesModel {
  const PoolResourcesModel(this.pools, this.selected);
  final List<PoolResource> pools;
  final PoolResource? selected;
  bool needsSetup(PoolResource resource) =>
      PoolConfiguration(
        pools: [resource],
      ).validate(complete: resource.enabled, requireProducts: false) !=
      null;
  String setupStatus(PoolResource resource) => !resource.enabled
      ? 'Disabled'
      : needsSetup(resource)
      ? 'Needs setup'
      : 'Configured';
}

class PoolPricingModel {
  const PoolPricingModel(this.pools, this.selected, this.currency);
  final List<PoolResource> pools;
  final PoolResource? selected;
  final String currency;
}

class PoolGroupsModel {
  const PoolGroupsModel(this.offers, this.pools, this.selected, this.currency);
  final List<PoolGroupOffer> offers;
  final List<PoolResource> pools;
  final PoolGroupOffer? selected;
  final String currency;
}

class PoolPlansModel {
  const PoolPlansModel(
    this.plans,
    this.pools,
    this.selected,
    this.currency,
    this.coaches,
    this.coachesLoading,
    this.coachError,
    this.totalPlanCount,
  );
  final List<PoolPlan> plans;
  final List<PoolResource> pools;
  final PoolPlan? selected;
  final String currency;
  final List<PoolCoach> coaches;
  final bool coachesLoading;
  final String? coachError;
  final int totalPlanCount;
}

class PoolReviewModel {
  const PoolReviewModel(this.configuration, this.currency);
  final PoolConfiguration configuration;
  final String currency;
}
