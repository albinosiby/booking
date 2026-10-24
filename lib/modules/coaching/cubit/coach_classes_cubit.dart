import 'dart:async';
import 'package:uuid/uuid.dart';
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
    Iterable<FlexibleCoachStudent> flexibleStudents = const [],
    this.loading = false,
    this.busy = false,
    this.error,
    this.notice,
    this.pendingCheckIn = false,
  }) : classes = List.unmodifiable(classes),
       flexibleStudents = List.unmodifiable(flexibleStudents);

  /// Local calendar date shown, `YYYY-MM-DD`.
  final String date;
  final List<CoachClass> classes;
  final List<FlexibleCoachStudent> flexibleStudents;
  final bool pendingCheckIn;
  final String? notice;
  // Current flexible students have their own tiles; historical visits stay visible.
  List<CoachClass> get displayClasses {
    final flexibleIds = flexibleStudents.map((s) => s.admissionId).toSet();
    return [
      for (final c in classes)
        if (c.students.any((s) => !flexibleIds.contains(s.admissionId)))
          c.withStudents(
            c.students.where((s) => !flexibleIds.contains(s.admissionId)),
          ),
    ];
  }

  final bool loading, busy;
  final String? error;
  CoachClassesState copy({
    String? date,
    Iterable<CoachClass>? classes,
    Iterable<FlexibleCoachStudent>? flexibleStudents,
    bool? loading,
    bool? busy,
    String? error,
    String? notice,
    bool? pendingCheckIn,
  }) => CoachClassesState(
    date: date ?? this.date,
    classes: classes ?? this.classes,
    flexibleStudents: flexibleStudents ?? this.flexibleStudents,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
    notice: notice,
    pendingCheckIn: pendingCheckIn ?? this.pendingCheckIn,
  );
  @override
  List<Object?> get props => [
    date,
    classes,
    flexibleStudents,
    loading,
    busy,
    error,
    notice,
    pendingCheckIn,
  ];
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
        _pendingFlexible = null;
        emit(CoachClassesState(date: state.date));
        if (snapshot.data.isCoach) unawaited(load());
      });
    }
  }
  StreamSubscription? _access;
  StreamSubscription<void>? _reads;
  final DateTime Function() _now;
  bool _followToday = false;
  (FlexibleCoachStudent, String, bool)? _pendingFlexible;
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
    if (_followToday && state.pendingCheckIn && state.date != today) return;
    if (_followToday && state.date != today) {
      emit(CoachClassesState(date: today));
    }
    final g = ++generation, date = state.date;
    emit(state.copy(loading: true));
    try {
      final roster = await api.classes(date);
      if (!isClosed && g == generation) {
        emit(
          state.copy(
            classes: roster.classes,
            flexibleStudents: roster.flexibleStudents,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          state.copy(
            loading: false,
            classes: const [],
            flexibleStudents: const [],
            error: e is AppException ? e.message : 'Could not load classes.',
          ),
        );
      }
    }
  }

  Future<void> show(DateTime day) async {
    if (isClosed || state.busy || state.pendingCheckIn) return;
    _followToday = false;
    emit(
      state.copy(
        date: coachDate(day),
        classes: const [],
        flexibleStudents: const [],
      ),
    );
    await load();
  }

  /// Home always follows today, including after a retained tab crosses midnight.
  Future<void> refreshToday({bool force = false}) async {
    if (isClosed || state.busy || state.loading || state.pendingCheckIn) return;
    _followToday = true;
    if (force || state.date != coachDate(_now())) await load();
  }

  Future<void> mark(CoachStudent student, String attendance) =>
      _marking([student], attendance);

  Future<void> checkIn(FlexibleCoachStudent student) async {
    if (isClosed ||
        state.busy ||
        state.loading ||
        state.pendingCheckIn ||
        !student.canMark ||
        student.today != state.date) {
      return;
    }
    if (_followToday && state.date != coachDate(_now())) {
      await load();
      return;
    }
    if (!state.flexibleStudents.contains(student)) return;
    _pendingFlexible = (student, const Uuid().v4(), student.action == 'start');
    await retryCheckIn();
  }

  /// A lost response reuses the original command, version and start intent.
  Future<void> retryCheckIn() async {
    final pending = _pendingFlexible;
    if (pending == null || isClosed || state.busy || state.loading) return;
    final g = generation;
    emit(state.copy(busy: true));
    try {
      final result = await api.checkIn(
        pending.$1,
        commandKey: pending.$2,
        startClass: pending.$3,
      );
      if (isClosed || g != generation) return;
      _pendingFlexible = null;
      emit(state.copy(busy: false, pendingCheckIn: false));
      await load();
      if (!isClosed && generation == g + 1) {
        emit(
          state.copy(
            error: state.error,
            notice:
                '${result.started ? 'Class started. ' : ''}${pending.$1.name} marked present${result.localMarkedAt == null ? '.' : ' at ${result.localMarkedAt!.replaceFirst('T', ' ')}.'}',
          ),
        );
      }
    } catch (e) {
      if (isClosed || g != generation) return;
      final definitive =
          e is AppException &&
          const {
            'REQUEST_ERROR',
            'VALIDATION_ERROR',
            'CONFLICT',
            'FORBIDDEN',
            'UNAUTHENTICATED',
            'CANCELLED',
            'NOT_FOUND',
          }.contains(e.code);
      if (definitive) _pendingFlexible = null;
      emit(state.copy(busy: false, pendingCheckIn: !definitive));
      if (definitive) await load();
      if (!isClosed && generation == g + (definitive ? 1 : 0)) {
        emit(
          state.copy(
            error: e is AppException
                ? e.message
                : 'Could not confirm attendance. Retry the saved request.',
          ),
        );
      }
    }
  }

  /// Marks every student still unmarked in [c] present.
  Future<void> markAll(CoachClass c) =>
      _marking(c.students.where((s) => s.markable), 'present');

  Future<void> _marking(Iterable<CoachStudent> students, String value) async {
    if (isClosed ||
        state.busy ||
        state.loading ||
        state.pendingCheckIn ||
        students.isEmpty) {
      return;
    }
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
