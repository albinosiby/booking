import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/website_settings_cubit.dart';
import '../cubit/website_settings_state.dart';
import '../models/website_settings.dart';
import '../repositories/rest_website_repository.dart' show normaliseSocialLink;
import '../widgets/website_photo_settings.dart';
import '../widgets/website_spaces_settings.dart';

/// Profile → Design website: address, branding, spaces, photos, rules and links.
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
  final addressField = GlobalKey<FormFieldState<String>>();
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
    String? helper,
    String? prefix,
    String? suffix,
    Widget? icon,
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
        helperText: helper,
        helperMaxLines: 3,
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: icon,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget section(String title, String? intro, List<Widget> children) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (intro != null) ...[const SizedBox(height: 8), Text(intro)],
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );

  Widget header(WebsiteSettingsState s, WebsiteSettings d) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.language_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                d.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Chip(label: Text(d.status)),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          key: const ValueKey('website-saved-url'),
          s.saved?.url ??
              'Configure BOOKING_WEBSITE_DOMAIN on the API to enable public links.',
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
                  : () => cubit.link(preview: true),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            OutlinedButton.icon(
              onPressed:
                  s.busy ||
                      s.dirty ||
                      d.status == 'draft' ||
                      d.status == 'unpublished'
                  ? null
                  : () => cubit.link(),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open website'),
            ),
            OutlinedButton.icon(
              onPressed: s.busy || s.dirty || d.url == null
                  ? null
                  : () => cubit.link(copy: true),
              icon: const Icon(Icons.copy_outlined),
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
  );

  Widget address(WebsiteSettingsState s, WebsiteSettings d) => section(
    'Website address',
    'Edit the name, then save your website address.',
    [
      LayoutBuilder(
        builder: (context, constraints) {
          final style = Theme.of(context).textTheme.bodyMedium!;
          final prefix = d.domain == null ? null : 'https://';
          final suffix = d.domain == null ? null : '.${d.domain}';
          double textWidth(String text) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          // Wrap the fixed domain on narrow screens to leave room to type.
          final inline =
              prefix == null ||
              constraints.maxWidth >=
                  textWidth(prefix) + textWidth(suffix!) + 120;
          Widget fixed(String text) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(text, style: style),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: addressField,
                initialValue: d.slug,
                enabled: !s.busy,
                maxLength: 63,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.url,
                validator: websiteAddressError,
                onChanged: (v) =>
                    cubit.update(d.copyWith(slug: v.trim().toLowerCase())),
                onFieldSubmitted: (_) => saveAddress(),
                decoration: InputDecoration(
                  labelText: 'Website name',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'your-name',
                  prefixIcon: prefix == null ? null : fixed(prefix),
                  prefixIconConstraints: const BoxConstraints(minHeight: 48),
                  suffixIcon: suffix != null && inline ? fixed(suffix) : null,
                  suffixIconConstraints: const BoxConstraints(minHeight: 48),
                  helperText: 'Lowercase letters, numbers and single hyphens.',
                  helperMaxLines: 3,
                  errorText: s.addressError,
                  errorMaxLines: 4,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (suffix != null && !inline)
                Align(alignment: Alignment.centerRight, child: fixed(suffix)),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('website-address-save'),
          onPressed: s.busy || !s.addressDirty ? null : saveAddress,
          icon: s.savingAddress
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(s.savingAddress ? 'Saving…' : 'Save'),
        ),
      ),
      if (s.addressError != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: s.busy ? null : cubit.load,
            child: const Text('Reload settings'),
          ),
        ),
      const SizedBox(height: 12),
      const Text(
        'After saving a new name, share the updated address. The previous address will no longer open this website.',
      ),
    ],
  );

  void saveAddress() {
    if (addressField.currentState?.validate() ?? false) cubit.saveAddress();
  }

  Widget brand(WebsiteSettingsState s, WebsiteSettings d) => section(
    'Brand & homepage',
    'The title, logo and hero appear at the top of your homepage.',
    [
      WebsitePhotoSlot(
        title: 'Website logo',
        help:
            'A square logo works best. It appears in the header of every page.',
        image: d.image('logo'),
        settings: d,
        disabled: s.busy || s.dirty,
        height: 96,
        onUpload: () => cubit.photo(kind: 'logo'),
        onRemove: (id) => cubit.photo(removeId: id),
      ),
      if (d.image('logo') == null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: d.publishLogo,
          onChanged: s.busy
              ? null
              : (v) => cubit.update(d.copyWith(publishLogo: v)),
          title: const Text('Use my organisation profile logo instead'),
          subtitle: const Text(
            'Shows the logo saved in your organisation profile when no website logo is uploaded.',
          ),
        ),
      const SizedBox(height: 18),
      field(
        label: 'Website title',
        value: d.title,
        max: 120,
        helper: 'Your venue or organisation name.',
        onChanged: (v) => cubit.update(d.copyWith(title: v)),
        validator: (v) =>
            (v?.trim().length ?? 0) >= 2 ? null : 'Enter a title.',
      ),
      field(
        label: 'Hero heading',
        value: d.heroHeading,
        max: 120,
        helper:
            'Large text over the hero image. Empty uses “A space for your next great moment.”',
        onChanged: (v) => cubit.update(d.copyWith(heroHeading: v)),
      ),
      field(
        label: 'Description',
        value: d.description,
        lines: 3,
        max: 1200,
        helper: 'Shown under the heading and used by search engines.',
        onChanged: (v) => cubit.update(d.copyWith(description: v)),
      ),
      field(
        label: 'Public contact phone',
        value: d.phone,
        max: 25,
        keyboard: TextInputType.phone,
        onChanged: (v) => cubit.update(d.copyWith(phone: v)),
        validator: (v) {
          final count = (v ?? '').replaceAll(RegExp(r'\D'), '').length;
          return RegExp(r'^\+?[\d ()-]{7,25}$').hasMatch(v ?? '') &&
                  count >= 7 &&
                  count <= 15
              ? null
              : 'Enter a valid phone number.';
        },
      ),
      WebsitePhotoSlot(
        title: 'Hero image',
        help:
            'Use a wide photo of your venue. The heading and description are placed over it.',
        image: d.image('hero'),
        settings: d,
        disabled: s.busy || s.dirty,
        wide: true,
        onUpload: () => cubit.photo(kind: 'hero'),
        onRemove: (id) => cubit.photo(removeId: id),
      ),
      if (s.dirty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Save your changes before uploading photos.',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
    ],
  );

  Widget social(WebsiteSettings d) => section(
    'Social media',
    'Links appear on your homepage and footer. Leave a field empty to hide it.',
    [
      for (final e in websiteSocialNetworks.entries)
        field(
          label: e.value,
          value: d.socialLinks[e.key] ?? '',
          max: 300,
          keyboard: TextInputType.url,
          icon: const Icon(Icons.link),
          helper: e.key == 'whatsapp'
              ? 'e.g. https://wa.me/919876543210'
              : null,
          onChanged: (v) => cubit.update(
            d.copyWith(socialLinks: {...d.socialLinks, e.key: v}),
          ),
          validator: (v) {
            final value = normaliseSocialLink(v ?? '');
            if (value.isEmpty) return null;
            final uri = Uri.tryParse(value);
            return uri != null &&
                    uri.scheme == 'https' &&
                    uri.host.contains('.') &&
                    value.length <= 300
                ? null
                : 'Enter a full link, e.g. https://instagram.com/yourvenue';
          },
        ),
    ],
  );

  Widget policies(WebsiteSettings d) => section(
    'Default booking rules & policies',
    'Defaults apply to every space unless a space has its own rules.',
    [
      field(
        label: 'Minimum notice (minutes)',
        value: d.noticeMinutes.toString(),
        keyboard: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) cubit.update(d.copyWith(noticeMinutes: n));
        },
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return n != null && n >= 0 && n <= 10080
              ? null
              : 'Enter 0–10080 minutes.';
        },
      ),
      field(
        label: 'Advance booking window (days)',
        value: d.advanceDays.toString(),
        keyboard: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) cubit.update(d.copyWith(advanceDays: n));
        },
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return n != null && n >= 1 && n <= 365 ? null : 'Enter 1–365 days.';
        },
      ),
      field(
        label: 'Venue instructions',
        value: d.instructions,
        lines: 3,
        max: 2000,
        onChanged: (v) => cubit.update(d.copyWith(instructions: v)),
      ),
      field(
        label: 'Cancellation policy',
        value: d.cancellationPolicy,
        lines: 3,
        max: 2000,
        onChanged: (v) => cubit.update(d.copyWith(cancellationPolicy: v)),
      ),
    ],
  );

  Widget actions(WebsiteSettingsState s, WebsiteSettings d) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        onPressed: s.busy || !s.dirty ? null : () => save(),
        icon: s.busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: const Text('Save changes'),
      ),
      FilledButton.tonalIcon(
        onPressed: s.busy || d.status == 'published' && !s.dirty
            ? null
            : () => save('publish'),
        icon: const Icon(Icons.public),
        label: Text(
          d.status == 'paused' ? 'Resume bookings' : 'Publish website',
        ),
      ),
      if (d.status == 'published')
        OutlinedButton(
          onPressed: s.busy ? null : () => save('pause'),
          child: const Text('Pause bookings'),
        ),
      if (d.status == 'published' || d.status == 'paused')
        TextButton(
          onPressed: s.busy ? null : () => save('unpublish'),
          child: const Text('Unpublish'),
        ),
    ],
  );

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<WebsiteSettingsCubit, WebsiteSettingsState>(
    bloc: cubit,
    builder: (context, s) {
      final d = s.draft;
      const gap = SizedBox(height: 20);
      return Scaffold(
        appBar: AppBar(title: const Text('Design website')),
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
                                key: ValueKey('${d.version}-${s.revision}'),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    header(s, d),
                                    gap,
                                    address(s, d),
                                    gap,
                                    brand(s, d),
                                    gap,
                                    WebsiteSpacesSettings(
                                      settings: d,
                                      busy: s.busy,
                                      photosLocked: s.dirty,
                                      onToggleBusiness: cubit.toggleBusiness,
                                      onBusiness: (id, b) =>
                                          cubit.updateBusiness(id, (_) => b),
                                      onSpace: cubit.updateSpace,
                                      onCopyRules: cubit.copyRulesToAll,
                                      onUpload:
                                          (kind, businessId, resourceId) =>
                                              cubit.photo(
                                                kind: kind,
                                                businessId: businessId,
                                                resourceId: resourceId,
                                              ),
                                      onRemovePhoto: (id) =>
                                          cubit.photo(removeId: id),
                                    ),
                                    gap,
                                    social(d),
                                    gap,
                                    policies(d),
                                    gap,
                                    actions(s, d),
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
