import 'package:flutter/material.dart';
import '../../constants/asset_path.dart';

/// Uses the original application artwork at every authentication entry point.
class BookingBrand extends StatelessWidget {
  const BookingBrand({super.key, this.color, this.size = 44});
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BookingOS',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size * .26),
            child: Image.asset(
              AssetPath.bookingLogo,
              width: size,
              height: size,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'BookingOS',
            style: TextStyle(
              color: color ?? Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
        ],
      ),
    ),
  );
}
