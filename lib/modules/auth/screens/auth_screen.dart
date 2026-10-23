import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../cubit/auth_cubit.dart';
import '../widgets/google_sign_in_button.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.register = true,
    this.invitationToken,
    this.returnTo,
  });
  final bool register;
  final String? invitationToken, returnTo;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthCubit, AuthState>(
    builder: (context, s) => AppPage(
      eyebrow: widget.invitationToken != null
          ? 'STAFF INVITATION'
          : 'BOOKING OS',
      title: widget.invitationToken != null
          ? 'Join your team.'
          : widget.register
          ? 'Your business.\nOne calm workspace.'
          : 'Welcome back.',
      subtitle: widget.invitationToken != null
          ? context.read<AuthCubit>().supportsGoogleSignIn
                ? 'Continue with the Google account or email address your owner invited.'
                : 'Use the email address your owner invited.'
          : widget.register
          ? context.read<AuthCubit>().supportsGoogleSignIn
                ? 'Continue with Google or create an account with your email. You’ll name your organization next.'
                : 'Enter your personal name, email and password. You’ll name your organization next.'
          : 'Sign in to your organization.',
      children: [
        if (widget.register && widget.invitationToken == null) ...[
          const AppCard(
            child: Row(
              children: [
                Icon(Icons.business_outlined, color: AppColors.lime, size: 32),
                SizedBox(width: 14),
                Expanded(
                  child: Text('One organization.\nEvery business together.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (s.notice != null) ...[
          Text(s.notice!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
        ],
        if (s.error != null) ...[
          AppErrorWidget(message: s.error!),
          const SizedBox(height: 16),
        ],
        Form(
          key: form,
          child: AutofillGroup(
            child: Column(
              children: [
                if (widget.register) ...[
                  AppTextField(
                    label: widget.invitationToken == null
                        ? 'Owner’s full name'
                        : 'Your full name',
                    hint: 'Your personal name',
                    controller: name,
                    validator: Validation.name,
                    autofillHints: const [AutofillHints.name],
                    enabled: !s.busy,
                  ),
                  const SizedBox(height: 16),
                ],
                AppTextField(
                  label: 'Email address',
                  controller: email,
                  validator: Validation.email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  enabled: !s.busy,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Password',
                  controller: password,
                  validator: widget.register
                      ? Validation.password
                      : Validation.required,
                  password: true,
                  enabled: !s.busy,
                  autofillHints: [
                    widget.register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: widget.register ? 'Create account' : 'Sign in',
                  busy: s.busy && !s.googleSignIn,
                  icon: Icons.arrow_forward,
                  onPressed: s.busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          final cubit = context.read<AuthCubit>();
                          if (widget.register) {
                            await cubit.register(
                              name.text,
                              email.text,
                              password.text,
                            );
                          } else {
                            await cubit.signIn(email.text, password.text);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: s.busy
              ? null
              : () => context.go(
                  Uri(
                    path: widget.register ? '/sign-in' : '/register',
                    queryParameters: {
                      if (widget.invitationToken != null)
                        'invite': widget.invitationToken!,
                      if (widget.returnTo != null) 'from': widget.returnTo!,
                    },
                  ).toString(),
                ),
          child: Text(
            widget.register
                ? 'Already have an account? Sign in'
                : 'New here? Create an account',
          ),
        ),
        if (!widget.register)
          TextButton(
            onPressed: s.busy
                ? null
                : () async {
                    if (Validation.email(email.text) != null) {
                      showMessage(context, 'Enter your email address first.');
                      return;
                    }
                    await context.read<AuthCubit>().resetPassword(email.text);
                    if (context.mounted &&
                        context.read<AuthCubit>().state.error == null) {
                      showMessage(
                        context,
                        'If an account exists, a reset email has been requested.',
                      );
                    }
                  },
            child: const Text('Forgot password?'),
          ),
        if (context.read<AuthCubit>().supportsGoogleSignIn) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('or', style: Theme.of(context).textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 22),
          GoogleSignInButton(
            busy: s.busy && s.googleSignIn,
            onPressed: s.busy
                ? null
                : () => context.read<AuthCubit>().signInWithGoogle(
                    invitationToken: widget.invitationToken,
                    returnTo: widget.returnTo,
                  ),
          ),
        ],
      ],
    ),
  );
}
