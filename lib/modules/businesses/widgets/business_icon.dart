import 'package:flutter/material.dart';
import '../../workspace/models/workspace.dart';

IconData businessIcon(BusinessType type) => switch (type) {
  BusinessType.turf => Icons.sports_soccer,
  BusinessType.badminton => Icons.sports_tennis,
  BusinessType.tennis => Icons.sports_tennis,
  BusinessType.basketball => Icons.sports_basketball,
  BusinessType.pool => Icons.pool,
  BusinessType.hall => Icons.celebration,
};
