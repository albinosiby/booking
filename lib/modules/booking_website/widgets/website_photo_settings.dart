import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/website_settings.dart';
import 'website_photo_upload_tile.dart';

class WebsitePhotoTile extends StatelessWidget {
  const WebsitePhotoTile({
    super.key,
    required this.image,
    required this.disabled,
    required this.onRemove,
    this.wide = false,
    this.height,
  });
  final WebsiteImage image;
  final bool disabled, wide;
  final double? height;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    final h = height ?? (wide ? 190.0 : 100.0);
    return SizedBox(
      width: wide ? double.infinity : 150.w.clamp(110, 180).toDouble(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: image.bytes == null
                ? SizedBox(
                    height: h,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  )
                : Image.memory(
                    image.bytes!,
                    height: h,
                    fit: BoxFit.cover,
                    cacheWidth: wide ? 1000 : 320,
                    errorBuilder: (_, _, _) => SizedBox(
                      height: h,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
          ),
          if (image.pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Not saved yet',
                style: Theme.of(context).textTheme.labelSmall,
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
  }
}

/// A single-photo slot (hero, logo or service card) with upload/replace.
class WebsitePhotoSlot extends StatelessWidget {
  const WebsitePhotoSlot({
    super.key,
    required this.title,
    required this.sectionId,
    required this.help,
    required this.image,
    required this.settings,
    required this.disabled,
    required this.onUpload,
    required this.onRemove,
    this.wide = false,
    this.height,
  });
  final String title, help, sectionId;
  final WebsiteImage? image;
  final WebsiteSettings settings;
  final bool disabled, wide;
  final double? height;
  final VoidCallback onUpload;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), c = t.colorScheme;
    final limitReached =
        image == null && settings.images.length >= websitePhotoLimit;
    return Material(
      color: c.surfaceContainerHighest.withValues(alpha: .4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ExpansionTile(
          key: PageStorageKey('website-photo-panel-$sectionId'),
          maintainState: true,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 12),
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(title, style: t.textTheme.titleSmall),
          subtitle: Text(
            image == null
                ? 'No photo selected'
                : image!.pending
                ? '1 photo · Unsaved changes'
                : '1 photo',
          ),
          children: [
            Text(
              help,
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            const Text(
              'JPG, PNG or WebP up to ${websitePhotoSourceMaxBytes ~/ (1024 * 1024)} MB. Photos are optimized for the website.',
            ),
            const SizedBox(height: 16),
            if (image != null) ...[
              WebsitePhotoTile(
                image: image!,
                disabled: disabled,
                onRemove: onRemove,
                wide: wide,
                height: height,
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: WebsitePhotoUploadTile(
                label: image == null ? 'Upload photo' : 'Replace photo',
                onPressed: disabled || limitReached ? null : onUpload,
              ),
            ),
            if (limitReached) ...[
              const SizedBox(height: 8),
              Text(
                'Photo limit reached. Remove a photo to add another.',
                style: t.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Booking page gallery for one space (up to four photos, the first is the cover).
class WebsiteSpaceGallery extends StatelessWidget {
  const WebsiteSpaceGallery({
    super.key,
    required this.settings,
    required this.businessId,
    required this.spaceId,
    required this.disabled,
    required this.onUpload,
    required this.onRemove,
  });
  final WebsiteSettings settings;
  final String businessId, spaceId;
  final bool disabled;
  final VoidCallback onUpload;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    final images = settings.images
        .where(
          (i) =>
              i.kind == 'space' &&
              i.businessId == businessId &&
              i.resourceId == spaceId,
        )
        .toList();
    return ExpansionTile(
      key: PageStorageKey('website-photo-panel-space-$businessId-$spaceId'),
      maintainState: true,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
      leading: const Icon(Icons.photo_library_outlined),
      title: Text(
        'Booking page photos',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        '${images.length}/$websiteSpacePhotoLimit photos${images.any((image) => image.pending) ? ' · Unsaved changes' : ''}',
      ),
      children: [
        Text(
          'Shown in the gallery when visitors book this space. The first photo is the cover.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'JPG, PNG or WebP up to ${websitePhotoSourceMaxBytes ~/ (1024 * 1024)} MB. Photos are optimized for the website.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final image in images)
              WebsitePhotoTile(
                image: image,
                disabled: disabled,
                onRemove: onRemove,
              ),
            WebsitePhotoUploadTile(
              label:
                  'Add space photo (${images.length}/$websiteSpacePhotoLimit)',
              onPressed:
                  disabled ||
                      images.length >= websiteSpacePhotoLimit ||
                      settings.images.length >= websitePhotoLimit
                  ? null
                  : onUpload,
            ),
          ],
        ),
      ],
    );
  }
}

/// Photos left behind by spaces that no longer exist; hidden from visitors.
class WebsiteUnusedPhotos extends StatelessWidget {
  const WebsiteUnusedPhotos({
    super.key,
    required this.settings,
    required this.disabled,
    required this.onRemove,
  });
  final WebsiteSettings settings;
  final bool disabled;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    final unused = settings.images
        .where(
          (image) =>
              (image.kind == 'space' || image.kind == 'card') &&
              !settings.businesses.any(
                (b) =>
                    b.id == image.businessId &&
                    (image.kind == 'card' ||
                        b.spaces.any((s) => s.id == image.resourceId)),
              ),
        )
        .toList();
    if (unused.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          children: [
            for (final image in unused)
              WebsitePhotoTile(
                image: image,
                disabled: disabled,
                onRemove: onRemove,
              ),
          ],
        ),
      ],
    );
  }
}
