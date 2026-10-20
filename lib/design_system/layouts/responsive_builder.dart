import 'package:flutter/material.dart';

enum ScreenType { mobile, tablet, desktop }

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});
  final Widget Function(BuildContext, ScreenType) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => builder(
      context,
      c.maxWidth < 600
          ? ScreenType.mobile
          : c.maxWidth < 1200
          ? ScreenType.tablet
          : ScreenType.desktop,
    ),
  );
}
