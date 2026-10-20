import 'turf_configuration.dart';

/// Typed projections of the shared wizard; all six screens use TurfSetupCubit.
class TurfSportsScreenModel {
  TurfSportsScreenModel(this.selected);
  final List<TurfSport> selected;
}

class TurfGroundsScreenModel {
  TurfGroundsScreenModel(this.grounds, [this.sports = TurfSport.values]);
  final List<TurfGround> grounds;
  final List<TurfSport> sports;
}

class TurfSpacesScreenModel {
  TurfSpacesScreenModel(
    this.grounds,
    this.layouts, [
    this.sports = TurfSport.values,
  ]);
  final List<TurfGround> grounds;
  final List<TurfLayout> layouts;
  final List<TurfSport> sports;
}

class TurfOfferingsScreenModel {
  TurfOfferingsScreenModel(this.layouts, this.offerings, this.sports);
  final List<TurfLayout> layouts;
  final List<TurfOffering> offerings;
  final List<TurfSport> sports;
}

class TurfRulesScreenModel {
  TurfRulesScreenModel(
    this.hours,
    this.offerings,
    this.currency,
    this.layouts,
    this.grounds,
    this.selectedSport,
    this.selectedOfferingId,
    this.cricketUsesFootball,
    this.canUseFootballForCricket,
  );
  final TurfHours hours;
  final List<TurfOffering> offerings;
  final String currency;
  final List<TurfLayout> layouts;
  final List<TurfGround> grounds;
  final TurfSport? selectedSport;
  final String? selectedOfferingId;
  final bool cricketUsesFootball, canUseFootballForCricket;
  TurfOffering? get selectedOffering =>
      offerings.where((o) => o.id == selectedOfferingId).firstOrNull;
  List<TurfSport> get sports => TurfSport.values
      .where((s) => offerings.any((o) => o.sport == s))
      .toList();
  ({TurfHours operating, TurfHours offering})? closingExtension(
    TurfOffering offer,
    TurfPriceBand band,
  ) => turfClosingExtension(hours, offer.hoursOverride ?? hours, band.hours);
  String spaceName(String layoutId) =>
      layouts.firstWhere((layout) => layout.id == layoutId).name;
}

class TurfReviewScreenModel {
  TurfReviewScreenModel(this.configuration);
  final TurfConfiguration configuration;
  String? get validation => configuration.validate(complete: true);
}

class TurfSettingsOverviewModel {
  const TurfSettingsOverviewModel({
    required this.name,
    required this.configuration,
    required this.ready,
    required this.dirty,
  });
  final String name;
  final TurfConfiguration configuration;
  final bool ready, dirty;
}
