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
    this.fixedBody,
  }) : assert(slivers == null || fillRemaining == null),
       assert(fixedBody == null || (slivers == null && fillRemaining == null));
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

  /// Bounded content below a fixed heading, with its own scrolling panes.
  /// Normal pages retain the existing full-page scrolling behavior.
  final Widget? fixedBody;

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

  /// Content width at which the page switches to its desktop header.
  static const wideWidth = 900.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => page(context, box.maxWidth >= wideWidth),
  );

  Widget page(BuildContext context, bool wide) => Scaffold(
    appBar: !wide && (back || showAppBar)
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
    bottomNavigationBar: bottomBar == null || !wide
        ? bottomBar
        : floatingBar(context),
    floatingActionButton: floatingActionButton,
    body: SafeArea(
      child: fixedBody != null
          ? fixedContent(context, wide)
          : slivers != null
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
                        wide
                            ? 32
                            : back || showAppBar
                            ? 0
                            : 24,
                        inset,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: content(context, wide)),
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
                wide
                    ? 32
                    : back || showAppBar
                    ? 0
                    : 24,
                AppSpacing.page,
                floatingActionButton == null ? 32 : 112,
              ),
              child: content(context, wide),
            )
          : CustomScrollView(
              key: PageStorageKey(scrollId ?? title),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    wide
                        ? 32
                        : back || showAppBar
                        ? 0
                        : 24,
                    AppSpacing.page,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: content(context, wide)),
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

  Widget fixedContent(BuildContext context, bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.page,
      wide
          ? 32
          : back || showAppBar
          ? 0
          : 24,
      AppSpacing.page,
      0,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content(context, wide),
            Expanded(child: fixedBody!),
          ],
        ),
      ),
    ),
  );

  Widget content(BuildContext context, bool wide) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide && (back || onBack != null || showAppBar)) ...[
            webBar(context),
            const SizedBox(height: 20),
          ],
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
          if (header == null && (wide || !showAppBar))
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
          if (header == null && subtitle != null) ...[
            SizedBox(height: compactHeader && showAppBar && !wide ? 0 : 12),
            Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .72),
              ),
            ),
          ],
          SizedBox(height: compactHeader && !wide ? 12 : 28),
          ...children,
        ],
      ),
    ),
  );

  // Desktop replacement for the app bar: back link on the left, actions right.
  Widget webBar(BuildContext context) {
    final canGoBack =
        onBack != null ||
        (back && (ModalRoute.of(context)?.impliesAppBarDismissal ?? false));
    return Row(
      children: [
        if (canGoBack)
          TextButton.icon(
            key: const ValueKey('web-back'),
            onPressed: onBack ?? () => Navigator.maybePop(context),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .75),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        const Spacer(),
        ...?actions,
      ],
    );
  }

  // Bottom actions float as a card aligned with the content on desktop.
  Widget floatingBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: colors.surface,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: .35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: colors.outline.withValues(alpha: .5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: bottomBar!,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
