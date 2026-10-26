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
import '../widgets/website_editor_section.dart';

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
  final sectionKeys = List.generate(5, (_) => GlobalKey());
  final editorScroll = ScrollController();
  bool sectionSyncScheduled = false;
  bool jumpingToSection = false;
  int sectionJump = 0;
  final expanded = <int>{0};
  int selectedSection = 0;
  bool desktop = false;
  static const sections = [
    ('Website address', 'Your public booking link', Icons.language_rounded),
    (
      'Brand & homepage',
      'Logo, photos and introduction',
      Icons.palette_outlined,
    ),
    ('Services & spaces', 'What customers can book', Icons.grid_view_rounded),
    ('Social media', 'Connect with your visitors', Icons.link_rounded),
    ('Booking policies', 'Rules and venue instructions', Icons.policy_outlined),
  ];
  @override
  void initState() {
    super.initState();
    editorScroll.addListener(scheduleSectionSync);
    cubit.load();
  }

  @override
  void dispose() {
    editorScroll.dispose();
    cubit.close();
    super.dispose();
  }

  void save([String? action]) {
    final errors = form.currentState?.validateGranularly();
    if (errors == null) return;
    if (errors.isEmpty) {
      cubit.save(action: action);
      return;
    }
    final field = errors.first;
    final section = field.context
        .findAncestorWidgetOfExactType<WebsiteEditorSection>();
    if (section != null) {
      setState(() {
        expanded.add(section.index);
        selectedSection = section.index;
      });
    }
    ExpansibleController.maybeOf(field.context)?.expand();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && field.mounted) {
        Scrollable.ensureVisible(
          field.context,
          duration: const Duration(milliseconds: 250),
          alignment: .15,
        );
      }
    });
  }

  Future<void> selectPhoto({
    required String kind,
    String? businessId,
    String? resourceId,
  }) async {
    await cubit.photo(
      kind: kind,
      businessId: businessId,
      resourceId: resourceId,
    );
    if (!mounted || cubit.state.error == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(cubit.state.error!), showCloseIcon: true),
    );
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

  Widget editorSection(int index, Widget child) => WebsiteEditorSection(
    key: index == 0 ? null : sectionKeys[index],
    index: index,
    title: sections[index].$1,
    description: sections[index].$2,
    icon: sections[index].$3,
    expanded: expanded.contains(index),
    collapsible: !desktop,
    onToggle: () => setState(() {
      expanded.contains(index) ? expanded.remove(index) : expanded.add(index);
    }),
    child: child,
  );

  Widget section(int index, String? intro, List<Widget> children) {
    return editorSection(
      index,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (intro != null) ...[
            Text(
              intro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget header(WebsiteSettingsState s, WebsiteSettings d) => AppCard(
    key: sectionKeys[0],
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
          ],
        ),
        const SizedBox(height: 16),
        AppStatusBadge(
          label: switch (d.status) {
            'published' => 'Published',
            'paused' => 'Bookings paused',
            'unpublished' => 'Unpublished',
            _ => 'Draft website',
          },
          icon: d.status == 'published' ? Icons.public : Icons.edit_outlined,
        ),
        const SizedBox(height: 16),
        SelectableText(
          key: const ValueKey('website-saved-url'),
          s.saved!.websiteAddress,
        ),
        if (s.saved!.url != s.saved!.websiteAddress) ...[
          const SizedBox(height: 8),
          Text(
            s.saved!.url == null
                ? 'Connect this address before sharing it with customers.'
                : 'This address is not connected yet. Use your current website link:',
          ),
          if (s.saved!.url != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              s.saved!.url!,
              key: const ValueKey('website-current-live-url'),
            ),
          ],
        ],
        const SizedBox(height: 8),
        const Text(
          'Customers book normal visits using their name and phone number. Configure payment collection for each space below; submitted UPI references need bank verification.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        actions(s, d),
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

  Widget address(
    WebsiteSettingsState s,
    WebsiteSettings d,
  ) => section(0, 'Edit the name, then save your website address.', [
    LayoutBuilder(
      builder: (context, constraints) {
        final style = Theme.of(context).textTheme.bodyMedium!;
        const prefix = 'https://';
        final suffix = '.${d.addressDomain}';
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
            constraints.maxWidth >= textWidth(prefix) + textWidth(suffix) + 120;
        Widget fixed(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(text, style: style),
          ),
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
                prefixIcon: fixed(prefix),
                prefixIconConstraints: const BoxConstraints(minHeight: 48),
                suffixIcon: inline ? fixed(suffix) : null,
                suffixIconConstraints: const BoxConstraints(minHeight: 48),
                helperText: 'Lowercase letters, numbers and single hyphens.',
                helperMaxLines: 3,
                errorText: s.addressError,
                errorMaxLines: 4,
                border: const OutlineInputBorder(),
              ),
            ),
            if (!inline)
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
  ]);

  void saveAddress() {
    if (addressField.currentState?.validate() ?? false) cubit.saveAddress();
  }

  Widget brand(
    WebsiteSettingsState s,
    WebsiteSettings d,
  ) => section(1, 'The title, logo and hero appear at the top of your homepage.', [
    WebsitePhotoSlot(
      title: 'Website logo',
      sectionId: 'logo',
      help: 'A square logo works best. It appears in the header of every page.',
      image: d.image('logo'),
      settings: d,
      disabled: s.busy,
      height: 96,
      onUpload: () => selectPhoto(kind: 'logo'),
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
      validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Enter a title.',
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
      sectionId: 'hero',
      help:
          'Use a wide photo of your venue. The heading and description are placed over it.',
      image: d.image('hero'),
      settings: d,
      disabled: s.busy,
      wide: true,
      onUpload: () => selectPhoto(kind: 'hero'),
      onRemove: (id) => cubit.photo(removeId: id),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Logo and photo changes are applied when you save your website.',
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  ]);

  Widget social(WebsiteSettings d) => section(
    3,
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
    4,
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

  Widget saveBar(WebsiteSettingsState s) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              s.busy
                  ? 'Please wait…'
                  : s.dirty
                  ? 'You have unsaved changes'
                  : 'All changes saved',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Save changes',
                  icon: Icons.save_outlined,
                  busy: s.busy,
                  onPressed: s.busy || !s.dirty ? null : save,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Preview',
                  icon: Icons.visibility_outlined,
                  secondary: true,
                  onPressed: s.busy || s.dirty
                      ? null
                      : () => cubit.link(preview: true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void scheduleSectionSync() {
    if (sectionSyncScheduled) return;
    sectionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sectionSyncScheduled = false;
      if (!mounted || !desktop || jumpingToSection) return;
      final viewport = form.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final top = viewport.localToGlobal(Offset.zero).dy + 48;
      var active = 0;
      for (final (index, key) in sectionKeys.indexed) {
        final box = key.currentContext?.findRenderObject();
        if (box is RenderBox &&
            box.hasSize &&
            box.localToGlobal(Offset.zero).dy <= top) {
          active = index;
        }
      }
      if (selectedSection != active) setState(() => selectedSection = active);
    });
  }

  void jumpTo(int index) {
    final jump = ++sectionJump;
    jumpingToSection = true;
    setState(() {
      selectedSection = index;
      expanded.add(index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = sectionKeys[index].currentContext;
      if (mounted && target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          alignment: .03,
        );
      }
      if (mounted && jump == sectionJump) {
        jumpingToSection = false;
        scheduleSectionSync();
      }
    });
  }

  Widget navigation() => SingleChildScrollView(
    key: const PageStorageKey('website-editor-navigation'),
    primary: false,
    padding: const EdgeInsets.only(bottom: 24),
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'WEBSITE EDITOR',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final (i, item) in sections.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                key: ValueKey('website-nav-$i'),
                selected: selectedSection == i,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(item.$3, size: 21),
                title: Text(item.$1),
                subtitle: Text(item.$2),
                onTap: () => jumpTo(i),
              ),
            ),
        ],
      ),
    ),
  );

  Widget editor(WebsiteSettingsState s, WebsiteSettings d) => Form(
    key: form,
    child: SingleChildScrollView(
      key: const PageStorageKey('website-editor-content'),
      controller: editorScroll,
      primary: false,
      padding: const EdgeInsets.only(bottom: 28),
      child: KeyedSubtree(
        key: ValueKey('${d.version}-${s.revision}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.error != null) ...[
              AppCard(
                child: AppErrorWidget(
                  message: s.error!,
                  onRetry: s.busy ? null : cubit.load,
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (s.message != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  s.message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            header(s, d),
            const SizedBox(height: 24),
            address(s, d),
            const SizedBox(height: 20),
            brand(s, d),
            const SizedBox(height: 20),
            editorSection(
              2,
              WebsiteSpacesSettings(
                embedded: true,
                settings: d,
                busy: s.busy,
                onToggleBusiness: cubit.toggleBusiness,
                onBusiness: (id, b) => cubit.updateBusiness(id, (_) => b),
                onSpace: cubit.updateSpace,
                onCopyRules: cubit.copyRulesToAll,
                onUpload: (kind, businessId, resourceId) => selectPhoto(
                  kind: kind,
                  businessId: businessId,
                  resourceId: resourceId,
                ),
                onRemovePhoto: (id) => cubit.photo(removeId: id),
              ),
            ),
            const SizedBox(height: 20),
            social(d),
            const SizedBox(height: 20),
            policies(d),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      desktop = isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth;
      return BlocBuilder<WebsiteSettingsCubit, WebsiteSettingsState>(
        bloc: cubit,
        builder: (context, s) {
          final d = s.draft;
          return AppPage(
            title: 'Design website',
            subtitle: 'Make your booking website feel like your venue.',
            back: true,
            showAppBar: true,
            compactHeader: true,
            maxWidth: 1260,
            bottomBar: d == null ? null : saveBar(s),
            fixedBody: s.loading
                ? const Center(child: CircularProgressIndicator())
                : d == null
                ? Center(
                    child: AppErrorWidget(
                      message: s.error ?? 'Could not load website settings.',
                      onRetry: cubit.load,
                    ),
                  )
                : desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 252, child: navigation()),
                      const SizedBox(width: 28),
                      Expanded(child: editor(s, d)),
                    ],
                  )
                : editor(s, d),
            children: const [],
          );
        },
      );
    },
  );
}
