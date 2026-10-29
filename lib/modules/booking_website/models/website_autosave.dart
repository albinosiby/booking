import 'package:flutter/foundation.dart';
import 'website_settings.dart';

/// Rebase a server acknowledgement without overwriting typing done in flight.
WebsiteSettings rebaseWebsiteSave(
  WebsiteSettings submitted,
  WebsiteSettings latest,
  WebsiteSettings result,
) => result.copyWith(
  slug: latest.slug == submitted.slug ? result.slug : latest.slug,
  title: latest.title == submitted.title ? result.title : latest.title,
  description: latest.description == submitted.description
      ? result.description
      : latest.description,
  phone: latest.phone == submitted.phone ? result.phone : latest.phone,
  instructions: latest.instructions == submitted.instructions
      ? result.instructions
      : latest.instructions,
  cancellationPolicy: latest.cancellationPolicy == submitted.cancellationPolicy
      ? result.cancellationPolicy
      : latest.cancellationPolicy,
  heroHeading: latest.heroHeading == submitted.heroHeading
      ? result.heroHeading
      : latest.heroHeading,
  socialLinks: mapEquals(latest.socialLinks, submitted.socialLinks)
      ? result.socialLinks
      : latest.socialLinks,
  publishLogo: latest.publishLogo == submitted.publishLogo
      ? result.publishLogo
      : latest.publishLogo,
  noticeMinutes: latest.noticeMinutes == submitted.noticeMinutes
      ? result.noticeMinutes
      : latest.noticeMinutes,
  advanceDays: latest.advanceDays == submitted.advanceDays
      ? result.advanceDays
      : latest.advanceDays,
  businessIds: listEquals(latest.businessIds, submitted.businessIds)
      ? result.businessIds
      : latest.businessIds,
  businesses: [
    for (final b in result.businesses) _rebaseBusiness(submitted, latest, b),
  ],
  // Photo edits are serialized separately while writes run.
  images: result.images,
);

/// Incomplete input stays editable; the API remains the final validator.
String? websiteAutosaveError(WebsiteSettings d) {
  final slugError = websiteAddressError(d.slug);
  if (slugError != null) return slugError;
  if (d.title.trim().length < 2 || d.title.trim().length > 120) {
    return 'Enter a website title of 2–120 characters.';
  }
  final phone = d.phone.trim(),
      digits = phone.replaceAll(RegExp(r'\D'), '').length;
  if (!RegExp(r'^\+?[\d ()-]{7,25}$').hasMatch(phone) ||
      digits < 7 ||
      digits > 15) {
    return 'Enter a valid public contact phone.';
  }
  if (d.heroHeading.length > 120 ||
      d.description.length > 1200 ||
      d.instructions.length > 2000 ||
      d.cancellationPolicy.length > 2000) {
    return 'Shorten the text to its field limit.';
  }
  if (d.noticeMinutes < 0 ||
      d.noticeMinutes > 10080 ||
      d.advanceDays < 1 ||
      d.advanceDays > 365) {
    return 'Check the notice and advance booking limits.';
  }
  for (final raw in d.socialLinks.values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.host.contains('.') ||
        uri.userInfo.isNotEmpty ||
        value.length > 300) {
      return 'Complete the social media link before saving.';
    }
  }
  for (final b in d.businesses) {
    if (b.description.length > 300) {
      return 'Shorten the business description to 300 characters.';
    }
    for (final s in b.spaces) {
      if ((s.noticeMinutes != null &&
              (s.noticeMinutes! < 0 || s.noticeMinutes! > 10080)) ||
          (s.advanceDays != null &&
              (s.advanceDays! < 1 || s.advanceDays! > 365)) ||
          s.rules.length > 1000) {
        return 'Check the space booking rules.';
      }
      if (s.paymentPercentages.any((p) => p < 1 || p > 100) ||
          s.paymentPercentages.toSet().length != s.paymentPercentages.length) {
        return 'Check the space payment percentages.';
      }
    }
  }
  return null;
}

WebsiteBusiness _rebaseBusiness(
  WebsiteSettings submitted,
  WebsiteSettings latest,
  WebsiteBusiness result,
) {
  final before = submitted.businesses
      .where((b) => b.id == result.id)
      .firstOrNull;
  final now = latest.businesses.where((b) => b.id == result.id).firstOrNull;
  if (before == null || now == null) return result;
  return result.copyWith(
    description: now.description == before.description
        ? result.description
        : now.description,
    spaces: [
      for (final space in result.spaces)
        now.spaces.where((s) => s.id == space.id).firstOrNull !=
                before.spaces.where((s) => s.id == space.id).firstOrNull
            ? now.spaces.where((s) => s.id == space.id).firstOrNull ?? space
            : space,
    ],
  );
}
