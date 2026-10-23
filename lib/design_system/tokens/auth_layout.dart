import 'package:flutter_screenutil/flutter_screenutil.dart';

class AuthLayout {
  static const desktopBreakpoint = 1200.0;
  static const formWidth = 420.0;
  static const fieldHeight = 56.0;
  static double get gutter => 24.w.clamp(16, 24);
  static double get cardRadius => 24.r.clamp(20, 24);
}
