import '../../../di/injection.dart';
import '../cubit/module_availability_cubit.dart';
import '../models/module_availability_screen_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../workspace/cubit/workspace_cubit.dart';

class FutureModuleScreen extends StatefulWidget {
  const FutureModuleScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.finance = false,
  });
  final String title, message;
  final IconData icon;
  final bool finance;
  @override
  State<FutureModuleScreen> createState() => _FutureModuleScreenState();
}

class _FutureModuleScreenState extends State<FutureModuleScreen> {
  late final cubit = getIt<ModuleAvailabilityCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ModuleAvailabilityCubit, ModuleAvailabilityScreenModel>(
        bloc: cubit,
        builder: (context, state) {
          final allowed =
              !widget.finance || state.data.hasPermission('view_finance');
          return AppPage(
            eyebrow: 'BOOKING OS',
            title: widget.title,
            children: [
              AppEmptyState(
                title: allowed ? 'Next module' : 'Access restricted',
                message: allowed
                    ? widget.message
                    : 'Your current role does not include financial reports.',
                icon: widget.icon,
              ),
            ],
          );
        },
      );
}
