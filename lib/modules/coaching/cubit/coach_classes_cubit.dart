import 'dart:async';
import '../../workspace/repositories/workspace_session.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/coach_class.dart';
import '../repositories/coach_api.dart';
import '../../workspace/repositories/refreshable_reads.dart';

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
  CoachClassesCubit(
    this.api, {
    DateTime? today,
    WorkspaceSession? session,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(
         CoachClassesState(date: coachDate(today ?? (now ?? DateTime.now)())),
       ) {
    if (api is RetainedReadEvents) {
      _reads = (api as RetainedReadEvents).readChanges.listen((_) {
        if (!isClosed && !state.busy) unawaited(load());
      });
    }
    if (session != null) {
      var previous = session.state.data.withLogo(null);
      _access = session.snapshots.listen((snapshot) {
        final next = snapshot.data.withLogo(null);
        if (previous == next || isClosed) return;
        previous = next;
        generation++;
        emit(CoachClassesState(date: state.date));
        if (snapshot.data.isCoach) unawaited(load());
      });
    }
  }
  StreamSubscription? _access;
  StreamSubscription<void>? _reads;
  final DateTime Function() _now;
  bool _followToday = false;
  @override
  Future<void> close() async {
    generation++;
    await _access?.cancel();
    await _reads?.cancel();
    return super.close();
  }

  final CoachApi api;
  int generation = 0;
  Future<void> load() async {
    if (isClosed || state.busy) return;
    final today = coachDate(_now());
    if (_followToday && state.date != today) {
      emit(CoachClassesState(date: today));
    }
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
    if (isClosed || state.busy) return;
    _followToday = false;
    emit(state.copy(date: coachDate(day), classes: const []));
    await load();
  }

  /// Home always follows today, including after a retained tab crosses midnight.
  Future<void> refreshToday({bool force = false}) async {
    if (isClosed || state.busy || state.loading) return;
    _followToday = true;
    if (force || state.date != coachDate(_now())) await load();
  }

  Future<void> mark(CoachStudent student, String attendance) =>
      _marking([student], attendance);

  /// Marks every student still unmarked in [c] present.
  Future<void> markAll(CoachClass c) =>
      _marking(c.students.where((s) => s.markable), 'present');

  Future<void> _marking(Iterable<CoachStudent> students, String value) async {
    if (isClosed || state.busy || state.loading || students.isEmpty) return;
    if (_followToday && state.date != coachDate(_now())) {
      await load();
      return;
    }
    final g = generation;
    emit(state.copy(busy: true));
    String? error;
    for (final s in students) {
      if (isClosed || g != generation) return;
      try {
        await api.mark(s, value);
      } catch (e) {
        error = e is AppException
            ? e.message
            : 'Could not save attendance for ${s.name}.';
        break;
      }
    }
    if (isClosed || g != generation) return;
    emit(state.copy(busy: false));
    await load();
    if (error != null && !isClosed) emit(state.copy(error: error));
  }
}
