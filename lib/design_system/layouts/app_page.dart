import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens/spacing.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.eyebrow,
    this.back = false,
    this.actions,
    this.maxWidth = 620,
    this.scrollId,
    this.onBack,
    this.bottomBar,
    this.floatingActionButton,
    this.showAppBar = false,
    this.compactHeader = false,
    this.fillRemaining,
    this.header,
    this.slivers,
  }) : assert(slivers == null || fillRemaining == null);
  final String title;
  final VoidCallback? onBack;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final bool showAppBar;
  final bool compactHeader;

  /// Optional empty/remaining content centered below the scrollable page header.
  final Widget? fillRemaining;

  /// Replaces the default heading block for pages with a custom introduction.
  final Widget? header;

  /// Native slivers share the page scroll position (including drag auto-scroll).
  /// They follow the normal heading and children and respect the content width.
  final List<Widget>? slivers;

  /// Stable identity when the heading contains an editable value.
  final String? scrollId;
  final String? subtitle, eyebrow;
  final List<Widget> children;
  final bool back;
  final List<Widget>? actions;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: back || showAppBar
        ? AppBar(
            automaticallyImplyLeading: back,
            title: showAppBar
                ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            leading: onBack == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: onBack,
                  ),
            actions: actions,
          )
        : null,
    bottomNavigationBar: bottomBar,
    floatingActionButton: floatingActionButton,
    body: SafeArea(
      child: slivers != null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final inset = math.max(
                  AppSpacing.page,
                  (constraints.maxWidth - maxWidth) / 2,
                );
                return CustomScrollView(
                  key: PageStorageKey(scrollId ?? title),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        inset,
                        back || showAppBar ? 0 : 24,
                        inset,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: content(context)),
                    ),
                    for (final sliver in slivers!)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        sliver: sliver,
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: floatingActionButton == null ? 32 : 112,
                      ),
                    ),
                  ],
                );
              },
            )
          : fillRemaining == null
          ? SingleChildScrollView(
              key: PageStorageKey(scrollId ?? title),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.page,
                back || showAppBar ? 0 : 24,
                AppSpacing.page,
                floatingActionButton == null ? 32 : 112,
              ),
              child: content(context),
            )
          : CustomScrollView(
              key: PageStorageKey(scrollId ?? title),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    back || showAppBar ? 0 : 24,
                    AppSpacing.page,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: content(context)),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      16,
                      AppSpacing.page,
                      floatingActionButton == null ? 32 : 96,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: fillRemaining,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );

  Widget content(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?header,
          if (header == null && eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compactHeader ? 6 : 12),
          ],
          if (header == null && !showAppBar)
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
          if (header == null && subtitle != null) ...[
            SizedBox(height: compactHeader && showAppBar ? 0 : 12),
            Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .72),
              ),
            ),
          ],
          SizedBox(height: compactHeader ? 12 : 28),
          ...children,
        ],
      ),
    ),
  );
}
