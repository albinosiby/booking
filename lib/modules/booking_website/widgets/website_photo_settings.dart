import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../design_system/design_system.dart';
import '../models/website_settings.dart';

class WebsitePhotoSettings extends StatelessWidget {
  const WebsitePhotoSettings({
    super.key,
    required this.settings,
    required this.disabled,
    required this.dirty,
    required this.onUpload,
    required this.onRemove,
  });
  final WebsiteSettings settings;
  final bool disabled, dirty;
  final void Function(String? businessId, String? resourceId) onUpload;
  final ValueChanged<String> onRemove;

  Widget photo(WebsiteImage image, {bool hero = false}) => SizedBox(
    width: hero ? double.infinity : 150.w.clamp(110, 180).toDouble(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: image.bytes == null
              ? const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                )
              : Image.memory(
                  image.bytes!,
                  height: hero ? 190 : 100,
                  fit: BoxFit.cover,
                  cacheWidth: hero ? 1000 : 320,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 100,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
        ),
        TextButton.icon(
          onPressed: disabled ? null : () => onRemove(image.id),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Remove photo'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final hero = settings.images.where((i) => i.kind == 'hero').firstOrNull;
    final unused = settings.images
        .where(
          (image) =>
              image.kind == 'space' &&
              !settings.businesses.any(
                (b) =>
                    b.id == image.businessId &&
                    b.spaces.any((s) => s.id == image.resourceId),
              ),
        )
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Homepage & space photos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Visitors first see your organisation homepage, then choose a service to open its booking page.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose JPEG, PNG or WebP images up to 2 MB. Photos are optimised for the website. Up to 4 photos per space and 40 per website.',
          ),
          const SizedBox(height: 8),
          Text(
            dirty
                ? 'Save your changes before uploading photos.'
                : 'Photo changes save immediately and are visible on your published website.',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 22),
          Text(
            'Homepage hero image',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use a wide photo of your venue. The homepage places its heading and description over this image.',
          ),
          const SizedBox(height: 12),
          if (hero != null) photo(hero, hero: true),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed:
                  disabled || hero == null && settings.images.length >= 40
                  ? null
                  : () => onUpload(null, null),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                hero == null ? 'Upload hero image' : 'Replace hero image',
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Booking space photos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Photos appear on the service card and on the booking page for that space. The first photo is the cover.',
          ),
          const SizedBox(height: 10),
          for (final business in settings.businesses.where(
            (b) => b.spaces.isNotEmpty,
          ))
            ExpansionTile(
              key: PageStorageKey('website-photos-${business.id}'),
              tilePadding: EdgeInsets.zero,
              title: Text(business.name),
              subtitle: Text('${business.spaces.length} booking spaces'),
              children: [
                for (final space in business.spaces)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Builder(
                      builder: (_) {
                        final images = settings.images
                            .where(
                              (i) =>
                                  i.businessId == business.id &&
                                  i.resourceId == space.id,
                            )
                            .toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              space.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            if (images.isNotEmpty)
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (final image in images) photo(image),
                                ],
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed:
                                    disabled ||
                                        images.length >= 4 ||
                                        settings.images.length >= 40
                                    ? null
                                    : () => onUpload(business.id, space.id),
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                label: Text(
                                  'Add space photo (${images.length}/4)',
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          if (unused.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Photos of removed spaces',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'These photos are hidden from visitors. Remove them to free up space.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final image in unused) photo(image)],
            ),
          ],
        ],
      ),
    );
  }
}
