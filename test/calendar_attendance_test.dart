import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/admissions/widgets/calendar_attendance.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource;

void main() {
  for (final (attendance, label, button) in [
    ('unmarked', 'Plan session · Not marked', true),
    ('present', 'Plan session · Present', false),
    ('absent', 'Plan session · Absent', false),
  ]) {
    testWidgets('a $attendance session shows $label', (tester) async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      addTearDown(workspace.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: MaterialApp(
            home: Scaffold(
              body: CalendarAttendance(
                admissionId: 'admission',
                visitId: 'visit',
                attendance: attendance,
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      // Marked sessions show only their result, not the Attendance button.
      expect(find.text('Attendance'), button ? findsOneWidget : findsNothing);
    });
  }
}
