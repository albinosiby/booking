import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../config/app_config.dart';
import '../../../config/routes/routes.dart';
import '../../../core/settings/application_setting.dart';
import '../../../di/injection.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/profile_cubit.dart';
import '../models/profile_screen_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final cubit = getIt<ProfileCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Widget destination(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String path,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(path),
  );
  // Destinations grouped by section; mobile lists them, desktop tiles them.
  List<(String?, List<_Destination>)> sections(Workspace w) => [
    (
      null,
      [
        if (w.isCoach)
          const _Destination(
            Icons.sports_outlined,
            'My classes',
            'Your coaching classes and attendance',
            Routes.myClasses,
          ),
        if ([
          'view_bookings',
          'manage_bookings',
          'collect_payments',
        ].any(w.hasPermission))
          const _Destination(
            Icons.people_outline,
            'Customers',
            'Find phone numbers and booking history',
            Routes.customers,
          ),
        if ([
          'view_bookings',
          'manage_bookings',
          'manage_attendance',
          'collect_payments',
        ].any(w.hasPermission))
          const _Destination(
            Icons.pool_outlined,
            'Admissions & Coaching',
            'Plans, attendance, remaining days and renewals',
            '/admissions',
          ),
        if (w.hasPermission('view_finance') ||
            w.hasPermission('record_expenses'))
          const _Destination(
            Icons.receipt_long_outlined,
            'Expenses',
            'Spending, invoices and monthly/yearly reports',
            Routes.expenses,
          ),
        if (w.hasPermission('view_finance') ||
            w.hasPermission('collect_payments'))
          const _Destination(
            Icons.savings_outlined,
            'Income',
            'Bookings, admissions, extra income and reports',
            Routes.income,
          ),
      ],
    ),
    if (w.isOwner)
      (
        'Workspace management',
        const [
          _Destination(
            Icons.business_outlined,
            'Organization details',
            'Organization, contact information and logo',
            Routes.organizationDetails,
          ),
          _Destination(
            Icons.storefront_outlined,
            'Businesses',
            'Add, configure and reorder your businesses',
            Routes.businesses,
          ),
          _Destination(
            Icons.groups_outlined,
            'Team & access',
            'People, roles and assigned spaces',
            Routes.team,
          ),
          _Destination(
            Icons.account_balance_outlined,
            'Accounts & payments',
            'Bank accounts and payment routing',
            '/accounts/settings',
          ),
          _Destination(
            Icons.chat_bubble_outline,
            'Booking message templates',
            'WhatsApp messages and primary template',
            '/profile/message-templates',
          ),
          _Destination(
            Icons.support_agent_outlined,
            'Sarvam voice agent',
            'Phone bookings, call logs and transcripts',
            Routes.sarvam,
          ),
        ],
      ),
  ];

  Widget identity(BuildContext context, ProfileScreenModel s, bool wide) {
    final w = s.data, user = context.watch<AuthCubit>().state.user;
    final colors = Theme.of(context).colorScheme;
    final size = wide ? 72.0 : 56.0;
    return AppCard(
      padding: EdgeInsets.all(wide ? 24 : 18),
      child: Row(
        crossAxisAlignment: wide
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (w.logo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                w.logo!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            )
          else
            CircleAvatar(
              radius: size / 2,
              backgroundColor: colors.primaryContainer,
              child: Icon(
                Icons.business_outlined,
                color: colors.onPrimaryContainer,
              ),
            ),
          SizedBox(width: wide ? 20 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.organization?.name ?? 'Your organization',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: wide ? 6 : 10),
                if (user?.name.isNotEmpty == true) Text(user!.name),
                Text(user?.email ?? ''),
                if (!wide) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.roleLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.primary),
                  ),
                ],
              ],
            ),
          ),
          if (wide)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                s.roleLabel,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> preferences(BuildContext context, ProfileScreenModel s) => [
    BlocBuilder<SettingsCubit, ThemeMode>(
      builder: (context, mode) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        secondary: const Icon(Icons.light_mode_outlined),
        title: const Text('Light appearance'),
        value: mode == ThemeMode.light,
        onChanged: (_) => context.read<SettingsCubit>().toggle(),
      ),
    ),
    if (AppConfig.useAuthEmulator)
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.science_outlined),
        title: Text('Local development'),
        subtitle: Text('Authentication emulator · no production customers'),
      ),
    if (s.error != null) AppErrorWidget(message: s.error!),
  ];

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileCubit, ProfileScreenModel>(
        bloc: cubit,
        builder: (context, s) => LayoutBuilder(
          builder: (context, box) =>
              box.maxWidth >= 900 ? wide(context, s) : narrow(context, s),
        ),
      );

  Widget narrow(BuildContext context, ProfileScreenModel s) => AppPage(
    title: 'Profile',
    eyebrow: 'YOUR ACCOUNT',
    subtitle: 'Your workspace, account and preferences.',
    scrollId: 'profile',
    children: [
      identity(context, s, false),
      for (final (title, items) in sections(s.data))
        if (items.isNotEmpty) ...[
          SizedBox(height: title == null ? 20 : 28),
          if (title != null) ...[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (final d in items)
            destination(
              context,
              icon: d.icon,
              title: d.title,
              subtitle: d.subtitle,
              path: d.path,
            ),
        ],
      const SizedBox(height: 24),
      Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ...preferences(context, s),
      const SizedBox(height: 24),
      AppButton(
        label: 'Sign out',
        secondary: true,
        onPressed: () => context.read<AuthCubit>().signOut(),
      ),
    ],
  );

  Widget wide(BuildContext context, ProfileScreenModel s) => AppPage(
    title: 'Profile',
    eyebrow: 'YOUR ACCOUNT',
    subtitle: 'Your workspace, account and preferences.',
    scrollId: 'profile',
    maxWidth: 1120,
    children: [
      identity(context, s, true),
      for (final (title, items) in sections(s.data))
        if (items.isNotEmpty) ...[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(
              title ?? 'Daily work',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 16.0;
              final columns = box.maxWidth >= 1000 ? 3 : 2;
              final width = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final d in items)
                    SizedBox(
                      width: width,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 104),
                        child: _DestinationTile(d),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      const SizedBox(height: 32),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 14),
        child: Text(
          'Preferences',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(children: preferences(context, s)),
      ),
      const SizedBox(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => context.read<AuthCubit>().signOut(),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
      ),
    ],
  );
}

class _Destination {
  const _Destination(this.icon, this.title, this.subtitle, this.path);
  final IconData icon;
  final String title, subtitle, path;
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile(this.d);
  final _Destination d;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => context.push(d.path),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(d.icon, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  d.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward,
            size: 18,
            color: colors.onSurface.withValues(alpha: .4),
          ),
        ],
      ),
    );
  }
}
