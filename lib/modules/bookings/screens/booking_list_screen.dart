import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/booking_list_model.dart';
import '../cubit/booking_list_cubit.dart';
import '../widgets/booking_payments_view.dart';
import '../widgets/booking_agenda_view.dart';

class BookingListScreen extends StatefulWidget {
  const BookingListScreen({
    super.key,
    this.mode = BookingListMode.bookings,
    this.initialBusinessId,
    this.initialDueView = false,
  });
  final BookingListMode mode;
  final String? initialBusinessId;
  final bool initialDueView;
  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  late final cubit = getIt<BookingListCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.mode,
  );
  @override
  void initState() {
    super.initState();
    if (widget.mode == BookingListMode.payments && widget.initialDueView) {
      cubit.dueView(true);
    } else if (widget.initialBusinessId != null) {
      cubit.business(widget.initialBusinessId);
    } else {
      cubit.load();
    }
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BookingListCubit, BookingListModel>(
        bloc: cubit,
        builder: (context, s) {
          final calendar = widget.mode == BookingListMode.calendar,
              payments = widget.mode == BookingListMode.payments;
          if (!payments) {
            return BookingAgendaView(
              state: s,
              cubit: cubit,
              calendar: calendar,
              back: widget.initialBusinessId != null,
            );
          }
          return BookingPaymentsView(
            state: s,
            cubit: cubit,
            back: widget.initialDueView,
          );
        },
      );
}
