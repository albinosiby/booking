import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../cubit/auth_cubit.dart';
import '../widgets/auth_form_layout.dart';
import '../widgets/auth_text_field.dart';
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
  final emailFocus = FocusNode(), passwordFocus = FocusNode();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final cubit = context.read<AuthCubit>();
    if (cubit.state.busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (widget.register) {
      await cubit.register(name.text, email.text, password.text);
    } else {
      await cubit.signIn(email.text, password.text);
    }
  }

  Future<void> resetPassword() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (Validation.email(email.text) != null) {
      showMessage(context, 'Enter your email address first.');
      emailFocus.requestFocus();
      return;
    }
    await context.read<AuthCubit>().resetPassword(email.text);
    if (mounted && context.read<AuthCubit>().state.error == null) {
      showMessage(
        context,
        'If an account exists, a reset email has been requested.',
      );
    }
  }

  void switchMode() => context.go(
    Uri(
      path: widget.register ? '/sign-in' : '/register',
      queryParameters: {
        if (widget.invitationToken != null) 'invite': widget.invitationToken!,
        if (widget.returnTo != null) 'from': widget.returnTo!,
      },
    ).toString(),
  );

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthCubit, AuthState>(
    builder: (context, state) {
      final cubit = context.read<AuthCubit>();
      final invited = widget.invitationToken != null;
      final scheme = Theme.of(context).colorScheme;
      return AuthFormLayout(
        eyebrow: invited ? 'STAFF INVITATION' : null,
        title: invited
            ? 'Join your team.'
            : widget.register
            ? 'Create your account.'
            : 'Welcome back.',
        subtitle: invited
            ? 'Use the email address your owner invited to join your team.'
            : widget.register
            ? 'One account for your bookings, team and everyday operations.'
            : 'Sign in to your BookingOS workspace.',
        error: state.error,
        notice: state.notice,
        footer: TextButton(
          onPressed: state.busy ? null : switchMode,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface.withValues(alpha: .7),
            minimumSize: const Size(48, 48),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: widget.register
                      ? 'Already have an account? '
                      : 'New here? ',
                ),
                TextSpan(
                  text: widget.register ? 'Sign in' : 'Create an account',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Form(
              key: form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.register) ...[
                      AuthTextField(
                        label: invited ? 'Your full name' : 'Owner’s full name',
                        hint: 'Your personal name',
                        controller: name,
                        icon: Icons.person_outline_rounded,
                        validator: Validation.name,
                        autofillHints: const [AutofillHints.name],
                        enabled: !state.busy,
                        onSubmitted: (_) => emailFocus.requestFocus(),
                      ),
                      const SizedBox(height: 20),
                    ],
                    AuthTextField(
                      label: 'Email address',
                      hint: 'you@example.com',
                      controller: email,
                      focusNode: emailFocus,
                      icon: Icons.mail_outline_rounded,
                      validator: Validation.email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      enabled: !state.busy,
                      onSubmitted: (_) => passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: 'Password',
                      hint: widget.register
                          ? 'Create a password'
                          : 'Enter your password',
                      controller: password,
                      focusNode: passwordFocus,
                      icon: Icons.lock_outline_rounded,
                      validator: widget.register
                          ? Validation.password
                          : Validation.required,
                      password: true,
                      enabled: !state.busy,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      labelAction: widget.register
                          ? null
                          : TextButton(
                              onPressed: state.busy ? null : resetPassword,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                minimumSize: const Size(48, 48),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              child: const Text('Forgot password?'),
                            ),
                      autofillHints: [
                        widget.register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: widget.register ? 'Create account' : 'Sign in',
                      busyLabel: widget.register
                          ? 'Creating account…'
                          : 'Signing in…',
                      busy: state.busy && !state.googleSignIn,
                      onPressed: state.busy ? null : submit,
                    ),
                  ],
                ),
              ),
            ),
            if (cubit.supportsGoogleSignIn) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'or',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: .45),
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              GoogleSignInButton(
                busy: state.busy && state.googleSignIn,
                onPressed: state.busy
                    ? null
                    : () => cubit.signInWithGoogle(
                        invitationToken: widget.invitationToken,
                        returnTo: widget.returnTo,
                      ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
