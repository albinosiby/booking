import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../cubit/auth_cubit.dart';

class PasswordUpdateScreen extends StatefulWidget {
  const PasswordUpdateScreen({super.key});
  @override
  State<PasswordUpdateScreen> createState() => _PasswordUpdateScreenState();
}

class _PasswordUpdateScreenState extends State<PasswordUpdateScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(), _confirm = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthCubit, AuthState>(
    builder: (context, state) => AppPage(
      title: 'Choose a new password.',
      subtitle: 'After saving, sign in with your new password.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              AppTextField(
                label: 'New password',
                controller: _password,
                password: true,
                validator: Validation.password,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Confirm password',
                controller: _confirm,
                password: true,
                validator: (value) =>
                    value == _password.text ? null : 'Passwords must match.',
              ),
              const SizedBox(height: 20),
              if (state.error != null) AppErrorWidget(message: state.error!),
              AppButton(
                label: 'Save password',
                busy: state.busy,
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    context.read<AuthCubit>().updatePassword(_password.text);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
