import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/location_catalog_model.dart';
export '../models/location_catalog_model.dart';
import '../repositories/organization_repository.dart';

class LocationCatalogCubit extends Cubit<LocationCatalogState> {
  LocationCatalogCubit(this.repository) : super(const LocationCatalogState());
  final OrganizationRepository repository;
  int generation = 0;
  Future<void> load() async {
    final g = ++generation;
    emit(
      LocationCatalogState(
        countries: state.countries,
        states: state.states,
        timezones: state.timezones,
        country: state.country,
      ),
    );
    try {
      final data = await repository.catalog();
      final states = await repository.states(state.country);
      if (!isClosed && g == generation) {
        emit(
          LocationCatalogState(
            countries: data.countries,
            states: states,
            timezones: data.timezones,
            busy: false,
            country: state.country,
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          LocationCatalogState(
            countries: state.countries,
            states: state.states,
            timezones: state.timezones,
            country: state.country,
            busy: false,
            error: e is AppException
                ? e.message
                : 'Unable to load location options.',
          ),
        );
      }
    }
  }

  Future<void> selectCountry(String country) async {
    final g = ++generation;
    emit(
      LocationCatalogState(
        countries: state.countries,
        timezones: state.timezones,
        country: country,
      ),
    );
    try {
      final states = await repository.states(country);
      if (!isClosed && g == generation) {
        emit(
          LocationCatalogState(
            countries: state.countries,
            timezones: state.timezones,
            states: states,
            busy: false,
            country: country,
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          LocationCatalogState(
            countries: state.countries,
            timezones: state.timezones,
            country: country,
            busy: false,
            error: e is AppException ? e.message : 'Unable to load states.',
          ),
        );
      }
    }
  }
}
