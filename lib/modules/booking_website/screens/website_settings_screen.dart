import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/website_settings_cubit.dart';
import '../cubit/website_settings_state.dart';
import '../widgets/website_photo_settings.dart';

class WebsiteSettingsScreen extends StatefulWidget {
  const WebsiteSettingsScreen({super.key});
  @override
  State<WebsiteSettingsScreen> createState() => _WebsiteSettingsScreenState();
}

class _WebsiteSettingsScreenState extends State<WebsiteSettingsScreen> {
  late final cubit = getIt<WebsiteSettingsCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  void save([String? action]) {
    if (form.currentState?.validate() ?? false) cubit.save(action: action);
  }

  Widget field({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int lines = 1,
    int? max,
    String? Function(String?)? validator,
    bool enabled = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      initialValue: value,
      onChanged: onChanged,
      enabled: enabled && !cubit.state.busy,
      maxLines: lines,
      maxLength: max,
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<WebsiteSettingsCubit, WebsiteSettingsState>(
    bloc: cubit,
    builder: (context, s) {
      final d = s.draft;
      return Scaffold(
        appBar: AppBar(title: const Text('Booking website')),
        body: s.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (s.error != null)
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: s.busy ? null : cubit.load,
                                    child: const Text('Reload settings'),
                                  ),
                                ],
                              ),
                            ),
                          if (s.message != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                s.message!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          if (d != null)
                            Form(
                              key: form,
                              child: KeyedSubtree(
                                key: ValueKey(d.version),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AppCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.language_outlined,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  d.title,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleLarge,
                                                ),
                                              ),
                                              Chip(label: Text(d.status)),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            d.url ??
                                                'Configure BOOKING_WEBSITE_URL on the API to enable public links.',
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Customers can book normal visits using their name and phone number. Payments are collected at the venue.',
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: s.busy || s.dirty
                                                    ? null
                                                    : () => cubit.link(
                                                        preview: true,
                                                      ),
                                                icon: const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                                label: const Text('Preview'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed:
                                                    s.busy ||
                                                        s.dirty ||
                                                        d.status == 'draft' ||
                                                        d.status ==
                                                            'unpublished'
                                                    ? null
                                                    : () => cubit.link(),
                                                icon: const Icon(
                                                  Icons.open_in_new,
                                                ),
                                                label: const Text(
                                                  'Open website',
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed:
                                                    s.busy ||
                                                        s.dirty ||
                                                        d.url == null
                                                    ? null
                                                    : () => cubit.link(
                                                        copy: true,
                                                      ),
                                                icon: const Icon(
                                                  Icons.copy_outlined,
                                                ),
                                                label: const Text('Copy link'),
                                              ),
                                            ],
                                          ),
                                          if (s.dirty)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 10),
                                              child: Text(
                                                'Save your changes to preview or share the updated website.',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    AppCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Website details',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 20),
                                          field(
                                            label: 'Website address',
                                            value: d.slug,
                                            enabled: !d.addressLocked,
                                            max: 80,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(slug: v),
                                            ),
                                            validator: (v) =>
                                                RegExp(
                                                      r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                                                    ).hasMatch(v ?? '') &&
                                                    (v?.length ?? 0) >= 3
                                                ? null
                                                : 'Use at least 3 lowercase letters, numbers or hyphens.',
                                          ),
                                          if (d.addressLocked)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 18,
                                              ),
                                              child: Text(
                                                'The address is fixed after publication to preserve shared links.',
                                              ),
                                            ),
                                          field(
                                            label: 'Website title',
                                            value: d.title,
                                            max: 120,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(title: v),
                                            ),
                                            validator: (v) =>
                                                (v?.trim().length ?? 0) >= 2
                                                ? null
                                                : 'Enter a title.',
                                          ),
                                          field(
                                            label: 'Description',
                                            value: d.description,
                                            lines: 3,
                                            max: 1200,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(description: v),
                                            ),
                                          ),
                                          field(
                                            label: 'Public contact phone',
                                            value: d.phone,
                                            max: 25,
                                            keyboard: TextInputType.phone,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(phone: v),
                                            ),
                                            validator: (v) {
                                              final count = (v ?? '')
                                                  .replaceAll(RegExp(r'\D'), '')
                                                  .length;
                                              return RegExp(
                                                        r'^\+?[\d ()-]{7,25}$',
                                                      ).hasMatch(v ?? '') &&
                                                      count >= 7 &&
                                                      count <= 15
                                                  ? null
                                                  : 'Enter a valid phone number.';
                                            },
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            value: d.publishLogo,
                                            onChanged: s.busy
                                                ? null
                                                : (v) => cubit.update(
                                                    d.copyWith(publishLogo: v),
                                                  ),
                                            title: const Text(
                                              'Show organisation logo publicly',
                                            ),
                                            subtitle: const Text(
                                              'Allows visitors to see the logo saved in your organisation profile.',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    AppCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Businesses available online',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 10),
                                          const Text(
                                            'Only active businesses with normal booking options appear. Group offers, swimming plans and coaching plans are excluded.',
                                          ),
                                          if (d.businesses.isEmpty)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 16),
                                              child: Text(
                                                'Add and configure a business first.',
                                              ),
                                            ),
                                          for (final business in d.businesses)
                                            CheckboxListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(business.name),
                                              subtitle: Text(
                                                '${business.type} · ${business.status}',
                                              ),
                                              value: d.businessIds.contains(
                                                business.id,
                                              ),
                                              onChanged: s.busy
                                                  ? null
                                                  : (v) => cubit.toggleBusiness(
                                                      business.id,
                                                      v ?? false,
                                                    ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    WebsitePhotoSettings(
                                      settings: d,
                                      disabled: s.busy || s.dirty,
                                      dirty: s.dirty,
                                      onUpload: (businessId, resourceId) =>
                                          cubit.photo(
                                            businessId: businessId,
                                            resourceId: resourceId,
                                          ),
                                      onRemove: (id) =>
                                          cubit.photo(removeId: id),
                                    ),
                                    const SizedBox(height: 20),
                                    AppCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Booking rules',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 20),
                                          field(
                                            label: 'Minimum notice (minutes)',
                                            value: d.noticeMinutes.toString(),
                                            keyboard: TextInputType.number,
                                            onChanged: (v) {
                                              final n = int.tryParse(v);
                                              if (n != null) {
                                                cubit.update(
                                                  d.copyWith(noticeMinutes: n),
                                                );
                                              }
                                            },
                                            validator: (v) {
                                              final n = int.tryParse(v ?? '');
                                              return n != null &&
                                                      n >= 0 &&
                                                      n <= 10080
                                                  ? null
                                                  : 'Enter 0–10080 minutes.';
                                            },
                                          ),
                                          field(
                                            label:
                                                'Advance booking window (days)',
                                            value: d.advanceDays.toString(),
                                            keyboard: TextInputType.number,
                                            onChanged: (v) {
                                              final n = int.tryParse(v);
                                              if (n != null) {
                                                cubit.update(
                                                  d.copyWith(advanceDays: n),
                                                );
                                              }
                                            },
                                            validator: (v) {
                                              final n = int.tryParse(v ?? '');
                                              return n != null &&
                                                      n >= 1 &&
                                                      n <= 365
                                                  ? null
                                                  : 'Enter 1–365 days.';
                                            },
                                          ),
                                          field(
                                            label: 'Venue instructions',
                                            value: d.instructions,
                                            lines: 3,
                                            max: 2000,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(instructions: v),
                                            ),
                                          ),
                                          field(
                                            label: 'Cancellation policy',
                                            value: d.cancellationPolicy,
                                            lines: 3,
                                            max: 2000,
                                            onChanged: (v) => cubit.update(
                                              d.copyWith(cancellationPolicy: v),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: s.busy || !s.dirty
                                              ? null
                                              : () => save(),
                                          icon: s.busy
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.save_outlined),
                                          label: const Text('Save changes'),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed:
                                              s.busy ||
                                                  d.status == 'published' &&
                                                      !s.dirty
                                              ? null
                                              : () => save('publish'),
                                          icon: const Icon(Icons.public),
                                          label: Text(
                                            d.status == 'paused'
                                                ? 'Resume bookings'
                                                : 'Publish website',
                                          ),
                                        ),
                                        if (d.status == 'published')
                                          OutlinedButton(
                                            onPressed: s.busy
                                                ? null
                                                : () => save('pause'),
                                            child: const Text('Pause bookings'),
                                          ),
                                        if (d.status == 'published' ||
                                            d.status == 'paused')
                                          TextButton(
                                            onPressed: s.busy
                                                ? null
                                                : () => save('unpublish'),
                                            child: const Text('Unpublish'),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}
