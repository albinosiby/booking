import '../../../di/injection.dart';
import '../cubit/startup_cubit.dart';
import '../models/startup_screen_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../workspace/cubit/workspace_cubit.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late final cubit = getIt<StartupCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<StartupCubit, StartupScreenModel>(
    bloc: cubit,
    builder: (c, s) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: s.status == LoadStatus.failure
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppErrorWidget(
                          message: s.error ?? 'Could not load your workspace.',
                        ),
                        const SizedBox(height: 20),
                        AppButton(label: 'Try again', onPressed: cubit.reload),
                        TextButton(
                          onPressed: () => c.read<AuthCubit>().signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    )
                  : const AppLoadingState(initial: true),
            ),
          ),
        ),
      ),
    ),
  );
}
