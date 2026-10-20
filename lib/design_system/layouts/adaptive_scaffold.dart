import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/app_bottom_nav_bar.dart';
import 'responsive_builder.dart';

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({super.key, required this.shell, this.onTabSelected});
  final StatefulNavigationShell shell;
  final VoidCallback? onTabSelected;
  @override
  Widget build(BuildContext context) => ResponsiveBuilder(
    builder: (context, type) => Scaffold(
      body: SafeArea(bottom: false, child: shell),
      bottomNavigationBar: AppBottomNavBar(
        index: shell.currentIndex,
        onTap: (i) {
          shell.goBranch(i);
          onTabSelected?.call();
        },
      ),
    ),
  );
}
