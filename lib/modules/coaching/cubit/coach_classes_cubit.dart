import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/coach_class.dart';
import '../repositories/coach_api.dart';

class CoachClassesState extends Equatable {
  CoachClassesState({
    required this.date,
    Iterable<CoachClass> classes = const [],
    this.loading = false,
    this.busy = false,
    this.error,
  }) : classes = List.unmodifiable(classes);

  /// Local calendar date shown, `YYYY-MM-DD`.
  final String date;
  final List<CoachClass> classes;
  final bool loading, busy;
  final String? error;
  CoachClassesState copy({
    String? date,
    Iterable<CoachClass>? classes,
    bool? loading,
    bool? busy,
    String? error,
  }) => CoachClassesState(
    date: date ?? this.date,
    classes: classes ?? this.classes,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
  );
  @override
  List<Object?> get props => [date, classes, loading, busy, error];
}

String coachDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class CoachClassesCubit extends Cubit<CoachClassesState> {
  CoachClassesCubit(this.api, {DateTime? today})
    : super(CoachClassesState(date: coachDate(today ?? DateTime.now())));
  final CoachApi api;
  int generation = 0;
  Future<void> load() async {
    if (isClosed) return;
    final g = ++generation, date = state.date;
    emit(state.copy(loading: true));
    try {
      final classes = await api.classes(date);
      if (!isClosed && g == generation) {
        emit(state.copy(classes: classes, loading: false));
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          state.copy(
            loading: false,
            classes: const [],
            error: e is AppException ? e.message : 'Could not load classes.',
          ),
        );
      }
    }
  }

  Future<void> show(DateTime day) async {
    if (state.busy) return;
    emit(state.copy(date: coachDate(day), classes: const []));
    await load();
  }

  Future<void> mark(CoachStudent student, String attendance) =>
      _marking([student], attendance);

  /// Marks every student still unmarked in [c] present.
  Future<void> markAll(CoachClass c) =>
      _marking(c.students.where((s) => s.markable), 'present');

  Future<void> _marking(Iterable<CoachStudent> students, String value) async {
    if (state.busy || state.loading || students.isEmpty) return;
    emit(state.copy(busy: true));
    String? error;
    for (final s in students) {
      try {
        await api.mark(s, value);
      } catch (e) {
        error = e is AppException
            ? e.message
            : 'Could not save attendance for ${s.name}.';
        break;
      }
    }
    if (isClosed) return;
    emit(state.copy(busy: false));
    await load();
    if (error != null && !isClosed) emit(state.copy(error: error));
  }
}
