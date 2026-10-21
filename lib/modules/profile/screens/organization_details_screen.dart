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
          if (isDesktopWidth(context)) return desktop(context, state);
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

extension on _OrganizationDetailsScreenState {
  // Wide windows: identity and logo on the left, details as panels on the right.
  Widget desktop(BuildContext context, ProfileScreenModel state) {
    final details = state.organizationDetails;
    final busy = state.busy || picking;
    return AppPage(
      back: true,
      showAppBar: true,
      title: 'Organization details',
      eyebrow: 'WORKSPACE MANAGEMENT',
      subtitle: 'Organization, contact information and logo.',
      scrollId: 'organization-details',
      maxWidth: 1200,
      actions: state.data.isOwner
          ? [
              Tooltip(
                message: 'Edit organization',
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => context.push(Routes.organizationEdit),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit details'),
                ),
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
          AppTwoPane(
            secondaryFirst: true,
            secondaryWidth: 340,
            secondary: [
              _DesktopIdentityCard(
                details: details,
                busy: busy,
                onChangeLogo: pickLogo,
              ),
            ],
            primary: [
              AppPanel(
                title: 'Contact details',
                subtitle: 'How customers and staff reach the organization.',
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 8,
                  ),
                  child: _FieldGrid([
                    _DetailField(label: 'Phone number', value: details.phone),
                    _DetailField(label: 'Currency', value: details.currency),
                  ]),
                ),
              ),
              AppPanel(
                title: 'Locations',
                subtitle: details.locations.isEmpty
                    ? null
                    : '${details.locations.length} '
                          '${details.locations.length == 1 ? 'venue' : 'venues'}',
                child: details.locations.isEmpty
                    ? const AppCard(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No location added yet.')),
                        ),
                      )
                    : Column(
                        children: [
                          for (final (i, location) in details.locations.indexed)
                            Padding(
                              padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                              child: _DesktopLocationCard(location: location),
                            ),
                        ],
                      ),
              ),
              AppPanel(
                title: 'Owner',
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 8,
                  ),
                  child: _FieldGrid([
                    _DetailField(label: 'Full name', value: details.ownerName),
                    _DetailField(
                      label: 'Email address',
                      value: details.ownerEmail,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Lays detail fields out in equal columns with a divider between rows.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid(this.fields, {this.columns = 2});
  final List<Widget> fields;
  final int columns;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row < fields.length; row += columns) ...[
        if (row > 0) const _FieldDivider(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = row; i < row + columns; i++) ...[
              if (i > row) const SizedBox(width: 24),
              Expanded(
                child: i < fields.length ? fields[i] : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    ],
  );
}

class _DesktopIdentityCard extends StatelessWidget {
  const _DesktopIdentityCard({
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
    Widget fallback() =>
        Icon(Icons.business_outlined, size: 48, color: colors.primary);
    Widget fact(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 112,
            height: 112,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.primary.withValues(alpha: .2)),
            ),
            child: details.logo == null
                ? fallback()
                : Image.memory(
                    details.logo!,
                    fit: BoxFit.cover,
                    cacheWidth: 336,
                    errorBuilder: (c, e, stack) => fallback(),
                  ),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 8),
          if (details.phone.isNotEmpty)
            fact(Icons.phone_outlined, details.phone),
          if (details.locations.isNotEmpty)
            fact(
              Icons.location_on_outlined,
              details.locations.length == 1
                  ? [
                      details.locations.single.city,
                      details.locations.single.country,
                    ].where((v) => v.isNotEmpty).join(', ')
                  : '${details.locations.length} locations',
            ),
          if (details.currency.isNotEmpty)
            fact(Icons.payments_outlined, 'Currency ${details.currency}'),
          const SizedBox(height: 20),
          const _FieldDivider(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
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
          ),
          const SizedBox(height: 10),
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

class _DesktopLocationCard extends StatelessWidget {
  const _DesktopLocationCard({required this.location});
  final OrganizationLocationDetails location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  size: 19,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  location.name.isEmpty ? 'Location' : location.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _FieldGrid(columns: 3, [
            _DetailField(label: 'Location name', value: location.name),
            _DetailField(label: 'Address line 1', value: location.addressLine1),
            if (location.addressLine2.isNotEmpty)
              _DetailField(
                label: 'Address line 2',
                value: location.addressLine2,
              ),
            _DetailField(label: 'City', value: location.city),
            if (location.state.isNotEmpty)
              _DetailField(label: 'State', value: location.state),
            _DetailField(label: 'Country', value: location.country),
            _DetailField(label: 'Pincode', value: location.pincode),
            _DetailField(label: 'Timezone', value: location.timezone),
          ]),
        ],
      ),
    );
  }
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
