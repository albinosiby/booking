import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_configuration.dart';
import 'football_ground_diagram.dart';
import 'cricket_ground_diagram.dart';

/// Sport-specific illustrations always describe the same physical ground.
class TurfGroundDiagram extends StatelessWidget {
  const TurfGroundDiagram({
    super.key,
    required this.ground,
    this.sports = TurfSport.values,
  });
  final TurfGround ground;
  final List<TurfSport> sports;
  @override
  Widget build(BuildContext context) {
    final split = ground.arrangement == TurfArrangement.split;
    Widget sportDiagram(TurfSport sport) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            sport.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        sport == TurfSport.football
            ? FootballGroundDiagram(split: split)
            : CricketGroundDiagram(split: split),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 600 && sports.length == 2
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sportDiagram(sports.first)),
                    const SizedBox(width: 16),
                    Expanded(child: sportDiagram(sports.last)),
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < sports.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      sportDiagram(sports[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (split) ...[
              const ReviewTag('Half A'),
              const ReviewTag('Half B'),
            ],
            ReviewTag(
              split ? 'Full Ground = A + B' : 'One full ground',
              active: true,
            ),
          ],
        ),
        if (sports.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Two sports on the same physical ground.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
