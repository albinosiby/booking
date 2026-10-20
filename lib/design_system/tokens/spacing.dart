import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSpacing {
  static double get page => 24.w.clamp(18, 28);
  static double get cardRadius => 20.r.clamp(16, 24);
  static const navElevation = 18.0;
  static const navRadius = 28.0;
  static const navGap = 12.0;
  static const navHeight = 76.0;
  static const navMaxWidth = 640.0;
}
