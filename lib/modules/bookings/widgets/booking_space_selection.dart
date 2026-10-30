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
    this.onPoolMode,
  });
  final BookingFormModel model;
  final List<BookingBusiness> businesses;
  final ValueChanged<String> onBusiness, onSport, onSpace, onOption;
  final ValueChanged<PoolBookingMode>? onPoolMode;

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
        if (s.business?.type == 'pool' && s.space != null) ...[
          heading('Booking option'),
          _PoolBookingOptions(model: s, onOption: onOption, onMode: onPoolMode),
        ] else if (s.poolMode == PoolBookingMode.singleVisit &&
            s.visibleOptions.length > 1) ...[
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

class _PoolBookingOptions extends StatelessWidget {
  const _PoolBookingOptions({
    required this.model,
    required this.onOption,
    this.onMode,
  });
  final BookingFormModel model;
  final ValueChanged<String> onOption;
  final ValueChanged<PoolBookingMode>? onMode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final option in model.visibleOptions) ...[
        _BookingOptionButton(
          key: ValueKey('booking-option-${option.id}'),
          title: option.groupMode == null ? 'Regular admission' : 'Group offer',
          subtitle: option.groupMode == null
              ? null
              : [
                  if (option.name != 'Group offer') option.name,
                  if (option.groupExplanation.isNotEmpty)
                    option.groupExplanation,
                ].join('\n'),
          icon: option.groupMode == null
              ? Icons.schedule_outlined
              : Icons.local_offer_outlined,
          selected:
              model.poolMode == PoolBookingMode.singleVisit &&
              model.draft.optionId == option.id,
          onPressed: model.locked ? null : () => onOption(option.id),
        ),
        const SizedBox(height: 10),
      ],
      if (onMode != null && model.original == null) ...[
        _BookingOptionButton(
          key: const ValueKey('booking-mode-swimming'),
          title: 'Swimming plan',
          icon: Icons.pool_outlined,
          selected: model.poolMode == PoolBookingMode.swimming,
          onPressed: model.locked
              ? null
              : () => onMode!(PoolBookingMode.swimming),
        ),
        const SizedBox(height: 10),
        _BookingOptionButton(
          key: const ValueKey('booking-mode-coaching'),
          title: 'Coaching',
          icon: Icons.sports_outlined,
          selected: model.poolMode == PoolBookingMode.coaching,
          onPressed: model.locked
              ? null
              : () => onMode!(PoolBookingMode.coaching),
        ),
      ],
    ],
  );
}

class _BookingOptionButton extends StatelessWidget {
  const _BookingOptionButton({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    this.subtitle,
    this.onPressed,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: selected
                ? colors.primary
                : colors.surfaceContainerLow,
            foregroundColor: selected ? colors.onPrimary : colors.onSurface,
            surfaceTintColor: Colors.transparent,
            elevation: selected ? 3 : 1,
            shadowColor: colors.shadow.withValues(alpha: .18),
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: theme.textTheme.labelLarge,
          ),
          onPressed: onPressed,
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title),
                    if (subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontWeight: FontWeight.normal),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
              ),
            ],
          ),
        ),
      ),
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
