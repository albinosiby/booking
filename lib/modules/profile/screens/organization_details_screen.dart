import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/profile_cubit.dart';
import '../models/profile_screen_model.dart';
import '../models/organization_details_model.dart';

class OrganizationDetailsScreen extends StatefulWidget {
  const OrganizationDetailsScreen({super.key});
  @override
  State<OrganizationDetailsScreen> createState() =>
      _OrganizationDetailsScreenState();
}

class _OrganizationDetailsScreenState extends State<OrganizationDetailsScreen> {
  late final cubit = getIt<ProfileCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  bool picking = false;

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> pickLogo() async {
    if (picking || cubit.state.busy || !cubit.state.data.isOwner) return;
    setState(() => picking = true);
    try {
      final selection = await cubit.selectLogo();
      if (!mounted || selection == null || !cubit.state.data.isOwner) return;
      final saved = await cubit.uploadLogo(
        selection.bytes,
        selection.contentType,
      );
      if (mounted && saved) showMessage(context, 'Organization logo updated.');
    } on AppException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileCubit, ProfileScreenModel>(
        bloc: cubit,
        builder: (context, state) {
          final details = state.organizationDetails;
          return AppPage(
            back: true,
            showAppBar: true,
            compactHeader: true,
            title: 'Organization details',
            scrollId: 'organization-details',
            actions: state.data.isOwner
                ? [
                    IconButton(
                      tooltip: 'Edit organization',
                      onPressed: state.busy || picking
                          ? null
                          : () => context.push(Routes.organizationEdit),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ]
                : null,
            children: [
              if (!state.data.isOwner)
                const AppErrorWidget(
                  message: 'Only the owner can manage organization details.',
                )
              else ...[
                if (state.error != null) ...[
                  AppErrorWidget(message: state.error!),
                  const SizedBox(height: 16),
                ],
                _IdentityCard(
                  details: details,
                  busy: state.busy || picking,
                  onChangeLogo: pickLogo,
                ),
                const _SectionTitle(
                  icon: Icons.contact_phone_outlined,
                  title: 'Contact details',
                ),
                AppCard(
                  child: Column(
                    children: [
                      _DetailField(label: 'Phone number', value: details.phone),
                      const _FieldDivider(),
                      _DetailField(label: 'Currency', value: details.currency),
                    ],
                  ),
                ),
                const _SectionTitle(
                  icon: Icons.location_on_outlined,
                  title: 'Locations',
                ),
                if (details.locations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No location added yet.')),
                  ),
                for (final location in details.locations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _LocationCard(location: location),
                  ),
                const _SectionTitle(icon: Icons.person_outline, title: 'Owner'),
                AppCard(
                  child: Column(
                    children: [
                      _DetailField(
                        label: 'Full name',
                        value: details.ownerName,
                      ),
                      const _FieldDivider(),
                      _DetailField(
                        label: 'Email address',
                        value: details.ownerEmail,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.details,
    required this.busy,
    required this.onChangeLogo,
  });
  final OrganizationDetailsModel details;
  final bool busy;
  final VoidCallback onChangeLogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final size = 72.r.clamp(64.0, 80.0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: details.logo == null
                    ? Icon(
                        Icons.business_outlined,
                        size: 34,
                        color: colors.primary,
                      )
                    : Image.memory(
                        details.logo!,
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (c, e, stack) => Icon(
                          Icons.business_outlined,
                          size: 34,
                          color: colors.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR ORGANIZATION',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      details.name.isEmpty ? 'Your organization' : details.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldDivider(),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: busy ? null : onChangeLogo,
            icon: busy
                ? const AppSavingDots()
                : const Icon(Icons.add_photo_alternate_outlined, size: 20),
            label: Text(
              busy
                  ? 'Updating logo…'
                  : details.logo == null
                  ? 'Add logo'
                  : 'Change logo',
            ),
          ),
          Text(
            'Optional · PNG, JPEG or WebP · up to 2 MB',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location});
  final OrganizationLocationDetails location;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailField(label: 'Location name', value: location.name),
        const _FieldDivider(),
        _DetailField(label: 'Address line 1', value: location.addressLine1),
        if (location.addressLine2.isNotEmpty) ...[
          const _FieldDivider(),
          _DetailField(label: 'Address line 2', value: location.addressLine2),
        ],
        const _FieldDivider(),
        _DetailField(label: 'City', value: location.city),
        if (location.state.isNotEmpty) ...[
          const _FieldDivider(),
          _DetailField(label: 'State', value: location.state),
        ],
        const _FieldDivider(),
        _DetailField(label: 'Country', value: location.country),
        const _FieldDivider(),
        _DetailField(label: 'Pincode', value: location.pincode),
        const _FieldDivider(),
        _DetailField(label: 'Timezone', value: location.timezone),
      ],
    ),
  );
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value.isEmpty ? 'Not provided' : value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
