import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';
import '../widgets/turf_field.dart';

class TurfOfferingsScreen extends StatelessWidget {
  const TurfOfferingsScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfOfferingsScreenModel model;
  final TurfSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...model.layouts.map(
        (layout) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layout.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...model.offerings
                    .where(
                      (offer) =>
                          offer.layoutId == layout.id &&
                          model.sports.contains(offer.sport),
                    )
                    .map(
                      (offer) => Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(offer.sport.label),
                            value: offer.enabled,
                            onChanged: disabled
                                ? null
                                : (value) =>
                                      cubit.offering(offer.id, enabled: value),
                          ),
                          if (offer.enabled) ...[
                            TurfField(
                              key: ValueKey('offer-name-${offer.id}'),
                              label: '${offer.sport.label} offering name',
                              value: offer.name,
                              validator: turfName,
                              enabled: !disabled,
                              onChanged: (value) =>
                                  cubit.offering(offer.id, name: value),
                            ),
                            const SizedBox(height: 12),
                            TurfField(
                              key: ValueKey('offer-format-${offer.id}'),
                              label: '${offer.sport.label} format',
                              value: offer.format,
                              validator: (v) =>
                                  v == null ||
                                      v.trim().length < 2 ||
                                      v.trim().length > 40
                                  ? 'Use 2–40 characters'
                                  : null,
                              enabled: !disabled,
                              onChanged: (value) =>
                                  cubit.offering(offer.id, format: value),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
      const Text(
        '5s and 7s describe football formats. They do not change the number of simultaneous bookings.',
      ),
    ],
  );
}
