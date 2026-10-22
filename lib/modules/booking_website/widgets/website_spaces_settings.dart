import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../models/website_settings.dart';
import 'website_photo_settings.dart';

/// Services (businesses) and their spaces: what is shown, photos and booking rules.
class WebsiteSpacesSettings extends StatelessWidget {
  const WebsiteSpacesSettings({
    super.key,
    required this.settings,
    required this.busy,
    required this.photosLocked,
    required this.onToggleBusiness,
    required this.onBusiness,
    required this.onSpace,
    required this.onCopyRules,
    required this.onUpload,
    required this.onRemovePhoto,
  });
  final WebsiteSettings settings;

  /// [photosLocked] while there are unsaved edits; photo changes save immediately.
  final bool busy, photosLocked;
  final void Function(String id, bool enabled) onToggleBusiness;
  final void Function(String id, WebsiteBusiness business) onBusiness;
  final void Function(String businessId, WebsiteSpace space) onSpace;
  final ValueChanged<WebsiteSpace> onCopyRules;
  final void Function(String kind, String businessId, String? resourceId)
  onUpload;
  final ValueChanged<String> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photosDisabled = busy || photosLocked;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Spaces on your website', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Choose the services and spaces visitors can book. Each service is a card on your homepage; each space has its own photos and booking rules.',
          ),
          const SizedBox(height: 6),
          Text(
            photosLocked
                ? 'Save your changes before uploading photos.'
                : 'Photo changes save immediately and are visible on your published website.',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
          if (settings.businesses.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Add and configure a business first.'),
            ),
          for (final business in settings.businesses)
            _BusinessTile(
              key: ValueKey('website-business-${business.id}'),
              settings: settings,
              business: business,
              enabled: settings.businessIds.contains(business.id),
              busy: busy,
              photosDisabled: photosDisabled,
              onToggle: (v) => onToggleBusiness(business.id, v),
              onChanged: (b) => onBusiness(business.id, b),
              onSpace: (s) => onSpace(business.id, s),
              onCopyRules: onCopyRules,
              onUpload: (kind, resourceId) =>
                  onUpload(kind, business.id, resourceId),
              onRemovePhoto: onRemovePhoto,
            ),
          WebsiteUnusedPhotos(
            settings: settings,
            disabled: photosDisabled,
            onRemove: onRemovePhoto,
          ),
        ],
      ),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    super.key,
    required this.settings,
    required this.business,
    required this.enabled,
    required this.busy,
    required this.photosDisabled,
    required this.onToggle,
    required this.onChanged,
    required this.onSpace,
    required this.onCopyRules,
    required this.onUpload,
    required this.onRemovePhoto,
  });
  final WebsiteSettings settings;
  final WebsiteBusiness business;
  final bool enabled, busy, photosDisabled;
  final ValueChanged<bool> onToggle;
  final ValueChanged<WebsiteBusiness> onChanged;
  final ValueChanged<WebsiteSpace> onSpace, onCopyRules;
  final void Function(String kind, String? resourceId) onUpload;
  final ValueChanged<String> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final shown = business.spaces.where((s) => s.visible).length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(business.name),
                subtitle: Text(
                  business.spaces.isEmpty
                      ? '${business.type} · ${business.status} · no bookable spaces'
                      : '${business.type} · ${business.status} · $shown of ${business.spaces.length} spaces shown',
                ),
                value: enabled,
                onChanged: busy ? null : (v) => onToggle(v ?? false),
              ),
              if (enabled && business.spaces.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Homepage card',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                WebsitePhotoSlot(
                  title: 'Card photo',
                  help:
                      'Shown on this service’s card on the homepage. Without one, the first space photo is used.',
                  image: settings.image('card', businessId: business.id),
                  settings: settings,
                  disabled: photosDisabled,
                  height: 140,
                  onUpload: () => onUpload('card', null),
                  onRemove: onRemovePhoto,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: business.description,
                  enabled: !busy,
                  maxLines: 2,
                  maxLength: 300,
                  onChanged: (v) =>
                      onChanged(business.copyWith(description: v)),
                  decoration: const InputDecoration(
                    labelText: 'Card description',
                    helperText: 'Leave empty to use a standard description.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                for (final space in business.spaces)
                  _SpaceTile(
                    key: ValueKey('website-space-${business.id}-${space.id}'),
                    settings: settings,
                    businessId: business.id,
                    space: space,
                    busy: busy,
                    photosDisabled: photosDisabled,
                    onChanged: onSpace,
                    onCopyRules: onCopyRules,
                    onUpload: () => onUpload('space', space.id),
                    onRemovePhoto: onRemovePhoto,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    super.key,
    required this.settings,
    required this.businessId,
    required this.space,
    required this.busy,
    required this.photosDisabled,
    required this.onChanged,
    required this.onCopyRules,
    required this.onUpload,
    required this.onRemovePhoto,
  });
  final WebsiteSettings settings;
  final String businessId;
  final WebsiteSpace space;
  final bool busy, photosDisabled;
  final ValueChanged<WebsiteSpace> onChanged, onCopyRules;
  final VoidCallback onUpload;
  final ValueChanged<String> onRemovePhoto;

  String get summary {
    if (!space.visible) return 'Hidden from visitors';
    final notice = space.noticeMinutes ?? settings.noticeMinutes;
    final window = space.advanceDays ?? settings.advanceDays;
    return '$window-day window · ${notice == 0 ? 'no minimum notice' : '$notice min notice'}'
        '${space.noticeMinutes == null && space.advanceDays == null ? ' (defaults)' : ''}';
  }

  Widget number({
    required String label,
    required int? value,
    required int fallback,
    required int min,
    required int max,
    required ValueChanged<int?> onChanged,
  }) => TextFormField(
    initialValue: value?.toString() ?? '',
    enabled: !busy,
    keyboardType: TextInputType.number,
    onChanged: (v) {
      final n = int.tryParse(v.trim());
      if (v.trim().isEmpty) {
        onChanged(null);
      } else if (n != null && n >= min && n <= max) {
        onChanged(n);
      }
    },
    validator: (v) {
      if ((v ?? '').trim().isEmpty) return null;
      final n = int.tryParse(v!.trim());
      return n != null && n >= min && n <= max ? null : 'Enter $min–$max.';
    },
    decoration: InputDecoration(
      labelText: label,
      hintText: 'Default: $fallback',
      helperText: 'Empty uses the website default',
      border: const OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 16),
    leading: Icon(
      space.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
    ),
    title: Text(space.name),
    subtitle: Text(summary),
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: space.visible,
        onChanged: busy ? null : (v) => onChanged(space.copyWith(visible: v)),
        title: const Text('Show this space on the website'),
        subtitle: const Text(
          'Hidden spaces cannot be booked online. Staff can still book them in the app.',
        ),
      ),
      if (space.visible) ...[
        const SizedBox(height: 8),
        WebsiteSpaceGallery(
          settings: settings,
          businessId: businessId,
          spaceId: space.id,
          disabled: photosDisabled,
          onUpload: onUpload,
          onRemove: onRemovePhoto,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Booking rules',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final notice = number(
              label: 'Minimum notice (minutes)',
              value: space.noticeMinutes,
              fallback: settings.noticeMinutes,
              min: 0,
              max: 10080,
              onChanged: (n) =>
                  onChanged(space.copyWith(noticeMinutes: () => n)),
            );
            final window = number(
              label: 'Advance booking window (days)',
              value: space.advanceDays,
              fallback: settings.advanceDays,
              min: 1,
              max: 365,
              onChanged: (n) => onChanged(space.copyWith(advanceDays: () => n)),
            );
            return c.maxWidth < 560
                ? Column(children: [notice, const SizedBox(height: 12), window])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: notice),
                      const SizedBox(width: 12),
                      Expanded(child: window),
                    ],
                  );
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: space.rules,
          enabled: !busy,
          maxLines: 3,
          maxLength: 1000,
          onChanged: (v) => onChanged(space.copyWith(rules: v)),
          decoration: const InputDecoration(
            labelText: 'Space rules for visitors',
            hintText: 'e.g. Non-marking shoes only. Arrive 10 minutes early.',
            border: OutlineInputBorder(),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : () => onCopyRules(space),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Copy these rules to all spaces'),
          ),
        ),
      ],
    ],
  );
}
