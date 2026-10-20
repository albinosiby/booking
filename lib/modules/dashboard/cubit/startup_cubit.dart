import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/dashboard_repository.dart';
import '../models/startup_screen_model.dart';

class StartupCubit extends Cubit<StartupScreenModel> {
  StartupCubit(this.repository)
    : super(StartupScreenModel.fromSnapshot(repository.current)) {
    _subscription = repository.changes.listen((snapshot) {
      if (!isClosed) {
        emit(StartupScreenModel.fromSnapshot(snapshot));
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
