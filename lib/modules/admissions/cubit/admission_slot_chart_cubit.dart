import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/exceptions/app_exception.dart';
import '../models/admission_slot_chart.dart';
import '../repositories/admission_repository.dart';

class AdmissionSlotChartState extends Equatable {
  const AdmissionSlotChartState({
    this.request,
    this.chart,
    this.loading = false,
    this.error,
  });
  final SlotChartRequest? request;
  final AdmissionSlotChart? chart;
  final bool loading;
  final String? error;
  @override
  List<Object?> get props => [request, chart, loading, error];
}

/// Live slot chart for a fixed admission schedule. Availability changes with
/// every booking, so it is always read fresh rather than served from cache.
class AdmissionSlotChartCubit extends Cubit<AdmissionSlotChartState> {
  AdmissionSlotChartCubit(this.repository, {this.delay = _debounce})
    : super(const AdmissionSlotChartState());
  static const _debounce = Duration(milliseconds: 300);
  final AdmissionRepository repository;
  final Duration delay;
  Timer? _timer;
  int _generation = 0;

  /// Loads [request] after a short pause; null clears the chart.
  void load(SlotChartRequest? request) {
    if (request == state.request) return;
    _timer?.cancel();
    final g = ++_generation;
    if (request == null) {
      emit(const AdmissionSlotChartState());
      return;
    }
    // Keep the previous chart visible while the next one loads.
    emit(
      AdmissionSlotChartState(
        request: request,
        chart: state.chart,
        loading: true,
      ),
    );
    _timer = Timer(delay, () => _fetch(g, request));
  }

  Future<void> refresh() async {
    final request = state.request;
    if (request == null || isClosed) return;
    _timer?.cancel();
    final g = ++_generation;
    emit(
      AdmissionSlotChartState(
        request: request,
        chart: state.chart,
        loading: true,
      ),
    );
    await _fetch(g, request);
  }

  Future<void> _fetch(int g, SlotChartRequest request) async {
    try {
      final chart = await repository.slotChart(request);
      if (isClosed || g != _generation) return;
      emit(AdmissionSlotChartState(request: request, chart: chart));
    } catch (e) {
      if (isClosed || g != _generation) return;
      emit(
        AdmissionSlotChartState(
          request: request,
          error: e is AppException
              ? e.message
              : 'Could not check free times. Try again.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
