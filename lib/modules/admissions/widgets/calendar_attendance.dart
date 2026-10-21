import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';

/// A Calendar action uses the admission's current permissions and session version.
class CalendarAttendance extends StatelessWidget {
  const CalendarAttendance({
    super.key,
    required this.admissionId,
    required this.visitId,
    required this.attendance,
    this.cancelled = false,
  });
  final String admissionId, visitId, attendance;
  final bool cancelled;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text(
        cancelled
            ? 'Admission visit · Cancelled'
            : 'Admission visit · $attendance',
      ),
      if (!cancelled &&
          context.read<WorkspaceCubit>().state.data.hasPermission(
            'manage_attendance',
          ))
        TextButton.icon(
          icon: const Icon(Icons.how_to_reg),
          label: const Text('Attendance'),
          onPressed: () async {
            final cubit = getIt<AdmissionCubit>(
              param1: context.read<WorkspaceCubit>(),
            );
            cubit.loadDetail(admissionId);
            await showAdaptiveSheet<void>(
              context: context,
              isDismissible: false,
              showClose: false,
              builder: (context) => BlocBuilder<AdmissionCubit, AdmissionState>(
                bloc: cubit,
                builder: (context, s) {
                  final visit = s.detail?.visits
                      .where((v) => v.id == visitId)
                      .firstOrNull;
                  return PopScope(
                    canPop: !s.busy && !s.locked,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        MediaQuery.viewInsetsOf(context).bottom + 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            s.detail?.customer.name ?? 'Attendance',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (s.loading || s.busy)
                            const AppLoadingState(initial: false),
                          if (s.error != null)
                            AppErrorWidget(message: s.error!),
                          if (s.locked && !s.busy)
                            AppButton(
                              label: 'Retry attendance',
                              onPressed: cubit.retry,
                            ),
                          if (visit != null) ...[
                            Text('${visit.start} · ${visit.attendance}'),
                            if (!visit.hasStarted)
                              const Text(
                                'Attendance can be marked when the session starts.',
                              ),
                            if (visit.hasStarted &&
                                visit.status != 'cancelled' &&
                                s.detail!.status != 'cancelled' &&
                                s.catalog.canAttend &&
                                visit.attendance == 'unmarked' &&
                                s.detail!.mode == 'fixed' &&
                                DateTime.parse(visit.endsAt).isAfter(
                                  DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                ))
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final value in ['present', 'absent'])
                                    FilledButton(
                                      onPressed: s.busy || s.locked
                                          ? null
                                          : () => cubit.attendance(
                                              visit,
                                              value,
                                              '',
                                            ),
                                      child: Text(
                                        value == 'present'
                                            ? 'Present'
                                            : 'Absent',
                                      ),
                                    ),
                                ],
                              ),
                            if (visit.attendance != 'unmarked')
                              const Text(
                                'Open this admission to make an owner correction with a reason.',
                              ),
                          ],
                          TextButton(
                            onPressed: s.busy || s.locked
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
            await cubit.close();
          },
        ),
    ],
  );
}
