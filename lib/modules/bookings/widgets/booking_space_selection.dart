import 'package:flutter/material.dart';
import '../models/booking_form_model.dart';
import '../models/booking_models.dart';
import '../models/booking_space_group.dart';
import 'booking_form_sections.dart';

/// Presentation only. Selection and availability remain owned by BookingFormCubit.
class BookingSpaceSelection extends StatelessWidget {
  const BookingSpaceSelection({
    super.key,
    required this.model,
    required this.businesses,
    required this.onBusiness,
    required this.onSport,
    required this.onSpace,
    required this.onOption,
  });
  final BookingFormModel model;
  final List<BookingBusiness> businesses;
  final ValueChanged<String> onBusiness, onSport, onSpace, onOption;

  Widget spaceCard(
    BookingFormModel s,
    BookingSpace space,
    String title,
    int count,
  ) => BookingChoiceCard(
    key: ValueKey('booking-space-${space.id}'),
    title: title,
    subtitle: s.business!.type == 'pool' || s.business!.type == 'hall'
        ? 'Capacity: ${space.capacity} people'
        : null,
    icon: s.business!.type == 'turf' && s.selectedSport == 'cricket'
        ? Icons.sports_cricket
        : bookingBusinessIcon(s.business!.type),
    selected: s.draft.spaceId == space.id,
    compact: true,
    onTap: s.locked || count == 1 ? null : () => onSpace(space.id),
  );

  @override
  Widget build(BuildContext context) {
    final s = model, theme = Theme.of(context), c = theme.colorScheme;
    Widget heading(String title, {String? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
          if (trailing != null)
            Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
    final spaces = s.sportSpaces;
    final noun = switch (s.business?.type) {
      'turf' => 'turf',
      'pool' => 'pool',
      'hall' => 'hall',
      _ => 'court',
    };
    return BookingFormSection(
      number: 2,
      title: 'Space',
      children: [
        BookingBusinessCards(
          businesses: businesses,
          selected: s.draft.businessId,
          enabled: !s.locked && s.original == null,
          onSelected: onBusiness,
        ),
        if (s.business == null) ...[
          const SizedBox(height: 12),
          Text(
            'Choose a business to see its spaces.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (s.sports.length > 1) ...[
          heading('Sport'),
          _SportToggle(model: s, onSelected: onSport),
        ],
        if (s.business?.type == 'turf')
          for (final group in BookingSpaceGroup.turf(spaces)) ...[
            heading(group.name),
            _ChoiceLayout(
              children: [
                for (final choice in group.choices.where((c) => !c.fullGround))
                  spaceCard(s, choice.space, choice.title, spaces.length),
              ],
            ),
            for (final choice in group.choices.where((c) => c.fullGround)) ...[
              const SizedBox(height: 8),
              spaceCard(s, choice.space, choice.title, spaces.length),
            ],
          ]
        else if (s.business != null && spaces.isNotEmpty) ...[
          heading(spaces.length == 1 ? 'Your $noun' : 'Choose $noun'),
          _ChoiceLayout(
            children: [
              for (final space in spaces)
                spaceCard(s, space, space.name, spaces.length),
            ],
          ),
        ],
        if (s.visibleOptions.length > 1) ...[
          heading('Booking option'),
          _ChoiceLayout(
            children: [
              for (final option in s.visibleOptions)
                BookingChoiceCard(
                  key: ValueKey('booking-option-${option.id}'),
                  title: option.format ?? option.name,
                  subtitle: option.groupExplanation.isEmpty
                      ? null
                      : option.groupExplanation,
                  icon: option.kind == 'hourly'
                      ? Icons.schedule_outlined
                      : Icons.local_offer_outlined,
                  selected: s.draft.optionId == option.id,
                  onTap: s.locked ? null : () => onOption(option.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChoiceLayout extends StatelessWidget {
  const _ChoiceLayout({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      final columns =
          children.length == 1 || (largeText && constraints.maxWidth < 380)
          ? 1
          : constraints.maxWidth >= 620
          ? 3
          : 2;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _SportToggle extends StatelessWidget {
  const _SportToggle({required this.model, required this.onSelected});
  final BookingFormModel model;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (final sport in model.sports)
                Expanded(
                  child: Semantics(
                    key: ValueKey('booking-sport-$sport'),
                    button: true,
                    selected: model.selectedSport == sport,
                    enabled: !model.locked,
                    child: Material(
                      color: model.selectedSport == sport
                          ? colors.primary.withValues(alpha: .16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: model.locked ? null : () => onSelected(sport),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                sport == 'football'
                                    ? Icons.sports_soccer
                                    : Icons.sports_cricket,
                                size: 18,
                                color: model.selectedSport == sport
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  sport == 'football'
                                      ? 'Football'
                                      : sport == 'cricket'
                                      ? 'Cricket'
                                      : sport,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: model.selectedSport == sport
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
