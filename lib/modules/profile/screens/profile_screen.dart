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
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ProfileCubit, ProfileScreenModel>(
    bloc: cubit,
    builder: (context, s) {
      final w = s.data, user = context.watch<AuthCubit>().state.user;
      return AppPage(
        title: 'Profile',
        eyebrow: 'YOUR ACCOUNT',
        subtitle: 'Your workspace, account and preferences.',
        scrollId: 'profile',
        children: [
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (w.logo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      w.logo!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.business_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.organization?.name ?? 'Your organization',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      if (user?.name.isNotEmpty == true) Text(user!.name),
                      Text(user?.email ?? ''),
                      const SizedBox(height: 6),
                      Text(
                        s.roleLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ([
            'view_bookings',
            'manage_bookings',
            'collect_payments',
          ].any(w.hasPermission)) ...[
            const SizedBox(height: 20),
            destination(
              context,
              icon: Icons.people_outline,
              title: 'Customers',
              subtitle: 'Find phone numbers and booking history',
              path: Routes.customers,
            ),
          ],
          if ([
            'view_bookings',
            'manage_bookings',
            'manage_attendance',
            'collect_payments',
          ].any(w.hasPermission)) ...[
            const SizedBox(height: 12),
            destination(
              context,
              icon: Icons.pool_outlined,
              title: 'Admissions & Coaching',
              subtitle: 'Plans, attendance, remaining days and renewals',
              path: '/admissions',
            ),
          ],
          if (w.hasPermission('view_finance') ||
              w.hasPermission('record_expenses')) ...[
            const SizedBox(height: 20),
            destination(
              context,
              icon: Icons.receipt_long_outlined,
              title: 'Expenses',
              subtitle: 'Spending, invoices and monthly/yearly reports',
              path: Routes.expenses,
            ),
          ],
          if (w.hasPermission('view_finance') ||
              w.hasPermission('collect_payments')) ...[
            const SizedBox(height: 12),
            destination(
              context,
              icon: Icons.savings_outlined,
              title: 'Income',
              subtitle: 'Bookings, admissions, extra income and reports',
              path: Routes.income,
            ),
          ],
          if (w.isOwner) ...[
            const SizedBox(height: 28),
            Text(
              'Workspace management',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            destination(
              context,
              icon: Icons.business_outlined,
              title: 'Organization details',
              subtitle: 'Organization, contact information and logo',
              path: Routes.organizationDetails,
            ),
            destination(
              context,
              icon: Icons.storefront_outlined,
              title: 'Businesses',
              subtitle: 'Add, configure and reorder your businesses',
              path: Routes.businesses,
            ),
            destination(
              context,
              icon: Icons.groups_outlined,
              title: 'Team & access',
              subtitle: 'People, roles and assigned spaces',
              path: Routes.team,
            ),
            destination(
              context,
              icon: Icons.account_balance_outlined,
              title: 'Accounts & payments',
              subtitle: 'Bank accounts and payment routing',
              path: '/accounts/settings',
            ),
            destination(
              context,
              icon: Icons.chat_bubble_outline,
              title: 'Booking message templates',
              subtitle: 'WhatsApp messages and primary template',
              path: '/profile/message-templates',
            ),
            destination(
              context,
              icon: Icons.support_agent_outlined,
              title: 'Sarvam voice agent',
              subtitle: 'Phone bookings, call logs and transcripts',
              path: Routes.sarvam,
            ),
          ],
          const SizedBox(height: 24),
          Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
              subtitle: Text(
                'Authentication emulator · no production customers',
              ),
            ),
          if (s.error != null) AppErrorWidget(message: s.error!),
          const SizedBox(height: 24),
          AppButton(
            label: 'Sign out',
            secondary: true,
            onPressed: () => context.read<AuthCubit>().signOut(),
          ),
        ],
      );
    },
  );
}
