import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/dashboard_repository.dart';
import '../models/module_availability_screen_model.dart';

class ModuleAvailabilityCubit extends Cubit<ModuleAvailabilityScreenModel> {
  ModuleAvailabilityCubit(this.repository)
    : super(ModuleAvailabilityScreenModel.fromSnapshot(repository.current)) {
    _subscription = repository.changes.listen((snapshot) {
      if (!isClosed) {
        emit(ModuleAvailabilityScreenModel.fromSnapshot(snapshot));
      }
    });
  }
  final DashboardRepository repository;
  late final StreamSubscription<Object?> _subscription;
  Future<void> reload() => repository.refresh();
  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
