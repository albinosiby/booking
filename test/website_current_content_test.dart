import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/booking_website/models/website_content.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_website_test.dart' show TestWebsiteRepository;
import 'booking_module_test.dart' show BookingSource;

void main() {
  test(
    'current default headings and descriptions are available without creating edits',
    () async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(
        session,
        repo,
        autosaveDelay: const Duration(milliseconds: 700),
      );
      await cubit.load();
      final d = cubit.state.draft!;
      expect(d.effectiveHeroHeading, defaultWebsiteHeroHeading);
      expect(d.effectiveDescription, defaultWebsiteDescription('Eden Sports'));
      expect(
        d.businesses.first.effectiveDescription,
        defaultWebsiteBusinessDescription('badminton', 'Badminton'),
      );
      expect(cubit.state.dirty, isFalse);
      expect(repo.saves, 0);
      expect(d.heroHeading, isEmpty);
      expect(d.description, isEmpty);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'custom copy takes priority and clearing restores the public fallback',
    () {
      final d = TestWebsiteRepository().value.copyWith(
        heroHeading: 'Play here',
        description: 'Our facilities.',
      );
      expect(d.effectiveHeroHeading, 'Play here');
      expect(d.effectiveDescription, 'Our facilities.');
      expect(
        d.copyWith(heroHeading: '').effectiveHeroHeading,
        defaultWebsiteHeroHeading,
      );
      for (final type in [
        'turf',
        'pool',
        'badminton',
        'tennis',
        'basketball',
        'hall',
      ]) {
        final b = WebsiteBusiness(
          id: type,
          name: 'My business',
          type: type,
          status: 'ready',
          enabled: true,
        );
        expect(
          b.effectiveDescription,
          defaultWebsiteBusinessDescription(type, b.name),
        );
        expect(
          b.copyWith(description: 'Custom description').effectiveDescription,
          'Custom description',
        );
      }
    },
  );
}
