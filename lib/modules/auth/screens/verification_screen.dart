import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../cubit/auth_cubit.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<AuthCubit, AuthState>(
    builder: (c, s) => AppPage(
      title: 'Verify your email.',
      subtitle:
          'Open the verification email, then return here. This protects organization and staff access.',
      children: [
        AppButton(
          label: 'I have verified my email',
          busy: s.busy,
          onPressed: () => c.read<AuthCubit>().reload(),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Resend verification email',
          secondary: true,
          onPressed: s.busy ? null : () => c.read<AuthCubit>().verify(),
        ),
        if (s.error != null) AppErrorWidget(message: s.error!),
        TextButton(
          onPressed: () => c.read<AuthCubit>().signOut(),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
}
