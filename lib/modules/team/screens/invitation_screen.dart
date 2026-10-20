import '../cubit/invitation_cubit.dart';
import '../models/invitation_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../workspace/cubit/workspace_cubit.dart';

class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key, required this.token});
  final String token;
  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  late final cubit = getIt<InvitationCubit>(
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
  ) => BlocBuilder<InvitationCubit, InvitationScreenModel>(
    bloc: cubit,
    builder: (c, s) => AppPage(
      eyebrow: 'STAFF INVITATION',
      title: 'Join your team.',
      subtitle:
          'Accept this invitation using the exact email address your owner invited.',
      children: [
        Text('Signed in as ${c.read<AuthCubit>().state.user?.email ?? ''}'),
        const SizedBox(height: 24),
        if (s.error != null) ...[
          AppErrorWidget(message: s.error!),
          const SizedBox(height: 16),
        ],
        AppButton(
          label: 'Accept invitation',
          busy: s.busy,
          onPressed: () async {
            final ok = await cubit.accept(widget.token);
            if (ok && c.mounted) c.go('/home');
          },
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => c.read<AuthCubit>().signOut(),
          child: const Text('Use another account'),
        ),
      ],
    ),
  );
}
